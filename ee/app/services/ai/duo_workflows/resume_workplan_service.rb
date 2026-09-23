# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Triggered by the user, so unanswered questions do not block the resume -
    # whatever has been answered is what the flow gets.
    class ResumeWorkplanService
      include ::Gitlab::Utils::StrongMemoize

      LEASE_TTL = 2.minutes

      PROJECT_REQUIRED_ERROR = 'Workplan generation is only available for project work items'
      FEATURE_DISABLED_ERROR = 'Async workplan generation is not enabled for this project'
      NO_WORKFLOW_ERROR = 'No workplan generation to resume for this work item'
      NOT_RESUMABLE_ERROR = 'Workplan generation is not awaiting input, or its previous run has not finished'
      EXECUTE_DENIED_ERROR = 'You are not allowed to run Duo Agent Platform flows in this project'
      RESUME_IN_PROGRESS_ERROR = 'A workplan resume is already in progress for this work item'

      # Exists so an unanswered resume sends an explicit "carry on" instead of
      # an empty goal the flow can't interpret.
      NO_REPLIES_MESSAGE = 'No answers were provided. Continue with your best assumptions.'

      def initialize(work_item:, current_user:)
        @work_item = work_item
        @current_user = current_user
      end

      def execute
        return error(PROJECT_REQUIRED_ERROR, :project_required) unless project
        return error(FEATURE_DISABLED_ERROR, :feature_disabled) unless feature_enabled?
        return error(NO_WORKFLOW_ERROR, :not_found) unless workflow
        return error(EXECUTE_DENIED_ERROR, :forbidden) unless can_resume?
        return error(NOT_RESUMABLE_ERROR, :not_resumable) unless input_resumable?

        resume
      end

      private

      attr_reader :work_item, :current_user

      # Whoever may update the work item may resume it, matching
      # GenerateWorkplan. `resume_duo_workflow` is deliberately not used - it
      # additionally requires the resuming user to be the flow owner, which
      # would lock out everyone else on the work item.
      def can_resume?
        current_user.can?(:update_work_item, work_item) && project.duo_remote_flows_enabled
      end

      # Two clicks landing together can both pass the checks above. The lease
      # serializes them, and the reload afterwards means only one resumes.
      def resume
        lease_uuid = Gitlab::ExclusiveLease.new(lease_key, timeout: LEASE_TTL.to_i).try_obtain
        return error(RESUME_IN_PROGRESS_ERROR, :resume_in_progress) unless lease_uuid

        begin
          workflow.reload # rubocop:disable Cop/ActiveRecordAssociationReload -- the record, not an association
          return error(NOT_RESUMABLE_ERROR, :not_resumable) unless input_resumable?

          oauth_token_result = workflow_context_generation_service
            .generate_oauth_token_with_composite_identity_support
          return oauth_token_result if oauth_token_result.error?

          service_token_result = workflow_context_generation_service.generate_workflow_token(
            flow_config_id: foundational_flow_start_params[:flow_config_id]
          )
          return service_token_result if service_token_result.error?

          result = ::Ai::DuoWorkflows::ResumeWorkflowService.new(
            workflow: workflow,
            params: resume_params(
              oauth_token: oauth_token_result.payload[:oauth_access_token].plaintext_token,
              service_token: service_token_result.payload.fetch(:token)
            )
          ).execute

          return result if result.error?

          ServiceResponse.success(payload: { workflow: workflow })
        ensure
          Gitlab::ExclusiveLease.cancel(lease_key, lease_uuid)
        end
      end

      def lease_key
        "duo_workflows_resume_workplan:#{workflow.id}"
      end

      def project
        work_item.project
      end
      strong_memoize_attr :project

      def feature_enabled?
        ::Feature.enabled?(:duo_workplan_async_flow, project.root_ancestor)
      end

      def workflow
        workplan_workflows.order_id_desc.first
      end
      strong_memoize_attr :workflow

      def workplan_workflows
        work_item.duo_workflows
          .with_workflow_definition(::Ai::DuoWorkflows::GenerateWorkplanService::WORKFLOW_DEFINITION_REFERENCE)
      end

      # Tokens stay bound to the user who started the flow, not whoever clicks
      # resume, so the conversation keeps one identity across its turns.
      def workflow_user
        workflow.user
      end

      def input_resumable?
        workflow.resumable? && workflow.input_required?
      end

      def error(message, reason)
        ServiceResponse.error(message: message, reason: reason)
      end

      # human_approval and human_message are deliberately unset: this is a
      # plain input_required resume, not an approval decision.
      def resume_params(oauth_token:, service_token:)
        {
          goal: reply_message,
          workflow_id: workflow.id,
          workflow_oauth_token: oauth_token,
          workflow_service_token: service_token,
          service_account: workflow.service_account,
          source_branch: project.default_branch,
          workflow_metadata: Gitlab::DuoWorkflow::Client.metadata(
            workflow_user,
            namespace: project.root_ancestor,
            project: project
          ).to_json,
          duo_agent_platform_feature_setting: workflow_context_generation_service.duo_agent_platform_feature_setting
        }.merge(foundational_flow_start_params)
      end

      # The same resolved flow ID must go into the token mint and the start
      # params, so DWS can reject a resume that names a different flow.
      def foundational_flow_start_params
        ::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver.call(
          workflow.workflow_definition, project, user: workflow_user
        )
      end
      strong_memoize_attr :foundational_flow_start_params

      # Restates every question ever posted so no "delivered" marker is needed.
      def reply_message
        questions = question_notes
        replies = replies_by_discussion_id(questions)

        # One Q per discussion, the note that opened it: the flow can post more
        # than once in a thread, and only the first of those is the question the
        # replies are answering.
        message = questions.uniq(&:discussion_id)
          .filter_map { |note| discussion_reply_text(note, replies) }
          .join(' ')
        return NO_REPLIES_MESSAGE if message.blank?

        # The goal is never written to the workflow record on this path, so the
        # model's own length validation never runs. Cap it here instead, to keep
        # DUO_WORKFLOW_GOAL under Linux's MAX_ARG_STRLEN.
        message
          .truncate(::Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH, omission: '')
          .truncate_bytes(::Ai::DuoWorkflows::Workflow::GOAL_MAX_BYTESIZE, omission: '')
      end

      # Only notes the flow wrote are questions. `linked_notes` also covers the
      # note that triggered the flow, which would hand the agent its own prompt
      # back as a question to answer.
      #
      # Spans every workplan run on the work item: a failed or stopped run
      # leaves its questions open, and the next run does not ask them again,
      # so their answers have to travel with this resume.
      def question_notes
        ::Note.id_in(
          ::Ai::DuoWorkflows::WorkflowNote.link_type_created.for_workflows(workplan_workflows).select(:note_id)
        ).order_created_at_id_asc.to_a
      end
      strong_memoize_attr :question_notes

      def flow_note_ids
        question_notes.map(&:id)
      end
      strong_memoize_attr :flow_note_ids

      # `Note#discussion` isn't a real association - it queries per call - so
      # looping the questions would be an N+1; this does one query instead.
      #
      # Anyone can post a reply, and whether it counts toward the goal is
      # decided below in `trusted_notes`, not here. What this does exclude is
      # the flow's own notes, by the whole id set rather than just the
      # question being answered: it posts more than once per discussion, and
      # its later messages would otherwise come back to it as answers to its
      # earlier ones.
      def replies_by_discussion_id(questions)
        return {} if questions.empty?

        notes = Note.with_discussion_ids(questions.map(&:discussion_id))
          .id_not_in(flow_note_ids)
          .order_created_at_id_asc
          .to_a

        trusted_notes(notes).group_by(&:discussion_id)
      end

      # Replies from Guest and below do not count toward the goal, regardless
      # of whether their author can press resume: `update_work_item` reaches a
      # Guest who authored or is assigned the item, but the flow they'd be
      # steering runs under the owner's identity, tokens and push access - a
      # narrower boundary than who can update the work item. Batched in one
      # query rather than checked per note, which would be an N+1 across
      # distinct authors.
      def trusted_notes(notes)
        access_levels = project.team.max_member_access_for_user_ids(notes.map(&:author_id).uniq)

        notes.select do |note|
          access_levels.fetch(note.author_id, ::Gitlab::Access::NO_ACCESS) > ::Gitlab::Access::GUEST
        end
      end

      def discussion_reply_text(question_note, replies_by_discussion_id)
        replies = replies_by_discussion_id.fetch(question_note.discussion_id, [])
        return if replies.empty?

        "Q: #{single_line(question_note.note)} A: #{replies.map { |reply| single_line(reply.note) }.join(' ')}"
      end

      # The goal rides a CI variable set with `expand: false`, and the sandbox
      # wrapper passes it by reference rather than by value, so it needs no
      # shell escaping. This only keeps the Q/A framing on one line.
      def single_line(text)
        text.to_s.split.join(' ')
      end

      def workflow_context_generation_service
        ::Ai::DuoWorkflows::WorkflowContextGenerationService.new(
          current_user: workflow_user,
          organization: project.organization,
          container: project,
          workflow_definition: workflow.workflow_definition,
          service_account: workflow.service_account,
          environment: workflow.environment
        )
      end
      strong_memoize_attr :workflow_context_generation_service
    end
  end
end
