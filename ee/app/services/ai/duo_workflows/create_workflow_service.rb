# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class CreateWorkflowService
      include ::Services::ReturnServiceResponses
      include ::Gitlab::Loggable
      include Concerns::LinkArtifact
      include Concerns::WorkflowEventTracking
      include Concerns::GovernanceResolution

      CouldNotDropWorkflowError = Class.new(StandardError)

      # `execution` is a FlowExecutionAuthorizer::Classification. Anything else,
      # nil or a raw value, gets the strictest access check.
      def initialize(container:, current_user:, params:, execution: nil, privileges_from_client: false)
        @container = container || current_user.default_duo_namespace
        @current_user = current_user
        @execution = execution
        # Caller-supplied privileges are clamped to governance; app-set ones are not.
        # A client-facing caller that omits this skips the clamp and silently reopens
        # https://gitlab.com/gitlab-org/gitlab/-/issues/618863, the way app-set callers do.
        @privileges_from_client = privileges_from_client
        # Remove ids to avoid confusion - @container determines the workflow scope, not raw IDs
        @params = params.except(:namespace_id, :project_id)
      end

      def execute
        unless @container.is_a?(::Project) || @container.is_a?(::Namespace)
          return error('container must be a Project or Namespace', :bad_request)
        end

        resolve_agent_privileges

        credit_check_response = check_usage_quota

        if credit_check_response.error?
          # http status should not be part of Service, but needs significant refactoring in the callers of
          # CreateWorkflowService.execute
          http_status = http_status_for_quota_error(credit_check_response.reason)
          message = enriched_error_message(credit_check_response)
          return error(message, http_status, pass_back: { reason: credit_check_response.reason })
        end

        response = check_flow_feature_flag || check_ai_catalog_item_access || check_access
        return response if response&.error?

        log_goal_size

        workflow = Ai::DuoWorkflows::Workflow.new(workflow_attributes)

        return error(workflow.errors.full_messages.join(', '), :bad_request) unless workflow.save

        link_artifact(workflow, link_type: :source) { workflow.work_item }
        link_artifact(workflow, link_type: :source) { workflow.merge_request }
        link_artifact(workflow, link_type: :source) { resolve_source_pipeline(workflow) }

        unless workflow.triggered_by_verification?
          Ai::DuoWorkflows::GenerateWorkflowTitleWorker.perform_async(workflow.id)
        end

        track_workflow_event("agent_platform_session_created", workflow, source: workflow.source_type)

        audit_workflow_creation(workflow)

        create_workflow_system_note(workflow)

        readiness_error = enforce_precondition_check(workflow)
        return readiness_error if readiness_error

        unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?
          Ai::DuoWorkflows::SyncSessionArtifactWorker.perform_async(workflow.id)
        end

        success(workflow: workflow)
      end

      def workflow_attributes
        base_params.merge(
          user: @current_user,
          # This is needed until the column can be safely removed
          # https://gitlab.com/gitlab-org/gitlab/-/work_items/627332
          incremental_checkpoints_enabled: true,
          **container_attributes,
          **noteable_attributes,
          **service_account_attributes,
          **execution_mode_attributes,
          **source_type_attributes
        )
      end

      private

      def audit_workflow_creation(workflow)
        audit_context = {
          name: 'duo_session_created',
          author: @current_user,
          scope: workflow.project || workflow.namespace,
          target: workflow,
          target_details: "#{'[Verification Run] ' if workflow.triggered_by_verification?}" \
            "#{workflow.workflow_definition} session #{workflow.id}",
          message: 'Created Duo session'
        }
        audit_context[:additional_details] = { verification_run: true } if workflow.triggered_by_verification?

        ::Gitlab::Audit::Auditor.audit(audit_context)
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(e, workflow_id: workflow.id)
      end

      # A verification run is a synthetic diagnostic, not real user activity - gating it on
      # remaining credits would block the check for exactly the customers who need it.
      def check_usage_quota
        return ServiceResponse.success if verification_run?

        namespace = @container.is_a?(::Project) ? @container.namespace : @container
        Ai::UsageQuotaService.new(
          user: @current_user,
          namespace: namespace,
          workflow_definition: workflow_definition
        ).execute
      end

      def log_goal_size
        goal = @params[:goal]
        return if goal.blank?

        Gitlab::AppLogger.info(
          build_structured_payload_labkit(
            message: 'Duo Workflow goal size',
            goal_size: goal.to_s.size,
            Labkit::Fields::DUO_WORKFLOW_DEFINITION => workflow_definition
          )
        )
      end

      def resolve_source_pipeline(workflow)
        return unless @container.is_a?(::Project)

        flow = ::Ai::Catalog::FoundationalFlow[workflow_definition]
        flow&.resolve_source_pipeline_for(project: @container, goal: @params[:goal])
      rescue StandardError => err
        Gitlab::ErrorTracking.track_exception(err, workflow_id: workflow.id, container_id: @container.id)
        nil
      end

      # `execution_mode` is excluded so it can only come from the sealed classification.
      # `source`/`source_type` are excluded so the column is only set via #source_type_attributes.
      def base_params
        params = @params.except(:issue_id, :merge_request_id, :service_account, :source, :source_type, :execution_mode)
        return params if explicit_catalog_item_version?

        params.except(:ai_catalog_item_version, :ai_catalog_item_version_id)
          .merge(ai_catalog_item_version_id: foundational_item_version&.id)
      end

      def source_type_attributes
        source_type = (@params[:source_type] || @params[:source]).to_s
        return {} unless Workflow.source_types.key?(source_type)

        { source_type: source_type }
      end

      def explicit_catalog_item_version?
        @params[:ai_catalog_item_version].present? || @params[:ai_catalog_item_version_id].present?
      end

      def foundational_item_version
        flow = ::Ai::Catalog::FoundationalFlow[workflow_definition]
        flow&.catalog_item&.latest_released_version_with_fallback
      end

      # `trigger_source` isn't a client-settable param anywhere (not declared in the REST
      # `workflow_params` block or any GraphQL mutation) - only trusted, server-side callers
      # (e.g. Ai::FlowTriggers::RunService, for system/scheduled/verification triggers) ever
      # set it, so it's safe to read straight off `@params`.
      def verification_run?
        @params[:trigger_source] == :verification
      end

      def service_account_attributes
        return {} unless @params[:service_account]

        { service_account: @params[:service_account] }
      end

      def create_workflow_system_note(workflow)
        noteable = workflow.noteable
        return unless noteable
        return if workflow.suppress_agent_session_note?

        # Who/what initiated the workflow
        # currently the user, but could be another agent
        # in future iterations
        trigger_source = @current_user
        note_author = workflow.service_account

        SystemNoteService.agent_session_started(
          noteable,
          noteable.project,
          workflow.id,
          trigger_source,
          note_author
        )
      rescue StandardError => err
        # `noteable` is nil when `workflow.noteable` itself raised
        Gitlab::ErrorTracking.track_exception(
          err,
          workflow_id: workflow.id,
          noteable_type: noteable&.class&.name,
          noteable_id: noteable&.id
        )
      end

      # Fail a CI-backed flow at creation when the project cannot run it, rather than queuing a
      # gitlab--duo job that no runner will pick up. Drops the session through UpdateWorkflowStatusService
      # (real summary + failure note) and returns an error to the caller.
      def enforce_precondition_check(workflow)
        project = workflow.project
        return unless project
        return unless Feature.enabled?(:duo_workflow_precondition_check, project)
        # Client-executed sessions (IDE, CLI, and create-without-start) run locally; chat runs
        # server-side. Neither submits a gitlab--duo CI job, so the runner check does not apply.
        return if client_executed?
        return if chat?

        # Only the readiness determination fails open: a probe error must not block session
        # creation (the current behaviour). Once a reason is known the session is always stopped.
        reason, summary =
          begin
            precondition_failure(project)
          rescue StandardError => e
            Gitlab::ErrorTracking.track_exception(e, workflow_id: workflow.id)
            nil
          end
        return unless reason

        # Drop the session, but still return the 422 even if the drop fails; a session left stuck
        # in `created` is reaped out of band by CleanStuckWorkflowsService.
        drop_unready_workflow(workflow, summary, reason)

        error(summary, :unprocessable_entity, pass_back: { reason: reason })
      end

      # Runner availability first: compute-minute exhaustion only strips instance runners, so a
      # project with a usable top-level group runner tagged gitlab--duo can still run the job. Only
      # when no runner is available do we use the minutes check to choose the right message.
      def precondition_failure(project)
        return if ::Ai::DuoWorkflow::ProjectReadiness.new(project, @current_user).runner_available?

        if project.ci_minutes_usage.minutes_used_up?
          [:namespace_ci_minutes_used_up, ::Ai::FoundationalFlowMessages.namespace_ci_minutes_used_up_error]
        else
          [:no_eligible_runner, ::Ai::FoundationalFlowMessages.no_eligible_runner_error]
        end
      end

      def drop_unready_workflow(workflow, summary, reason)
        result = ::Ai::DuoWorkflows::UpdateWorkflowStatusService.new(
          workflow: workflow,
          status_event: 'drop',
          current_user: @current_user,
          summary: summary,
          reason: note_reason_for(reason)
        ).execute
        return unless result.error?

        # The drop returns an error (not raises) if the transition or permission check fails, which
        # would leave the session stuck in `created` until the reaper cleans it up. Surface it.
        Gitlab::ErrorTracking.track_exception(
          CouldNotDropWorkflowError.new(result.message.to_s),
          workflow_id: workflow.id,
          reason: reason
        )
      rescue StandardError => e
        # A raised drop must not stop the caller from getting the 422 either; the stuck session is
        # reaped out of band. Track it here instead of letting it reach the fail-open probe rescue.
        Gitlab::ErrorTracking.track_exception(e, workflow_id: workflow.id, reason: reason)
      end

      def note_reason_for(reason)
        case reason
        when :no_eligible_runner
          "no instance or top-level group runner with the `#{::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG}` tag"
        when :namespace_ci_minutes_used_up then 'no compute minutes'
        end
      end

      # If flow is foundational AND gated by a feature flag, the flag is the authority on availability:
      # a flag can be disabled while the flow was enabled and the flag must have a higher precedence.
      def check_flow_feature_flag
        flow = ::Ai::Catalog::FoundationalFlow[workflow_definition]
        return unless flow&.blocked_by_feature_flag?(@container.root_ancestor)

        error('This flow is not available', :forbidden, pass_back: { reason: :flow_disabled_by_feature_flag })
      end

      def check_ai_catalog_item_access
        return unless @params[:ai_catalog_item_version]

        finder_params = {
          item_id: @params[:ai_catalog_item_version].ai_catalog_item_id
        }

        if @container.is_a?(::Project)
          finder_params[:project_id] = @container.id
        elsif @container.is_a?(::Namespace)
          finder_params[:group_id] = @container.id
        end

        return if Ai::Catalog::ItemConsumersFinder.new(@current_user, params: finder_params).execute.exists?

        error('ItemVersion not found', :not_found)
      end

      def check_access
        # Chat is never client-executed (not a FoundationalFlow, so FlowExecutionAuthorizer
        # never classifies it CLIENT). Handle it first so its agent-specific gates are never skipped.
        return check_agentic_chat_access if chat?

        # A client-executed classification is only ever minted by FlowExecutionAuthorizer,
        # which already authorized the run; re-checking here would refuse a valid seat used
        # outside its own namespace. https://gitlab.com/gitlab-org/gitlab/-/issues/623975
        return if client_executed?

        check_duo_workflow_access
      end

      def check_agentic_chat_access
        unless Ability.allowed?(@current_user, :access_duo_agentic_chat, @container)
          return error('forbidden to access agentic chat', :forbidden)
        end

        reference = FoundationalChatAgent.reference_from_workflow_definition(workflow_definition)

        agent = FoundationalChatAgent.with_workflow_definition(workflow_definition)
        if agent&.ultimate_only
          root_namespace = @container.root_ancestor
          return error('agent requires Ultimate plan', :forbidden) unless
            root_namespace.licensed_feature_available?(:ai_features)
        end

        return if foundational_agents_settings_container&.foundational_agent_enabled?(reference)

        error('foundation agent disabled for namespace', :forbidden)
      end

      def check_duo_workflow_access
        return if Ability.allowed?(@current_user, :create_duo_workflow_for_ci, @container)

        error('forbidden to access duo workflow', :forbidden, pass_back: { reason: :cannot_create_workflow_pipeline })
      end

      def client_executed?
        !!classification&.client_executed?
      end

      # The only writer of `execution_mode`: later resolution sites hold a workflow but no
      # classification, so it has to be recorded here to reach them.
      def execution_mode_attributes
        return {} unless classification

        { execution_mode: client_executed? ? :client : :background }
      end

      def classification
        return unless @execution.is_a?(FlowExecutionAuthorizer::Classification)

        @execution
      end

      def workflow_definition
        @params['workflow_definition'] || @params[:workflow_definition]
      end

      def chat?
        FoundationalChatAgent.foundational_workflow_definition?(workflow_definition)
      end

      def container_attributes
        if @container.is_a?(::Project)
          { project: @container }
        elsif @container.is_a?(::Namespace)
          { namespace: @container }
        end
      end

      def noteable_attributes
        attributes = {}

        if @params[:issue_id].present?
          work_item = find_issue(@params[:issue_id])
          attributes[:issue_id] = work_item.id if work_item
        end

        if @params[:merge_request_id].present?
          mr = find_merge_request(@params[:merge_request_id])
          attributes[:merge_request_id] = mr.id if mr
        end

        # When no explicit noteable is provided, resolve from the foundational flow.
        # E.g. fix_pipeline derives merge_request from the pipeline URL (goal).
        # Also skip resolution when the API layer has already resolved AR objects
        # (e.g. agent_workflows passes :issue or :merge_request directly).
        resolve_noteable_from_flow(attributes) unless explicit_noteable?(attributes)

        attributes
      end

      def explicit_noteable?(attributes)
        attributes.any? || @params[:issue].present? || @params[:merge_request].present?
      end

      def resolve_noteable_from_flow(attributes)
        return unless @container.is_a?(::Project)

        flow = ::Ai::Catalog::FoundationalFlow[workflow_definition]
        noteable = flow&.resolve_noteable_for(project: @container, goal: @params[:goal])

        attributes[:merge_request_id] = noteable.id if noteable.is_a?(::MergeRequest)
        attributes[:issue_id] = noteable.id if noteable.is_a?(::Issue)
      end

      def find_issue(issue_iid)
        return unless @container.is_a?(::Project)

        IssuesFinder.new(@current_user, project_id: @container.id, iids: [issue_iid]).execute.first
      rescue StandardError => err
        Gitlab::ErrorTracking.track_exception(err, issue_iid: issue_iid, container_id: @container.id)
        nil
      end

      def find_merge_request(mr_iid)
        MergeRequestsFinder.new(@current_user, project_id: @container.id, iids: [mr_iid]).execute.first
      rescue StandardError => err
        Gitlab::ErrorTracking.track_exception(err, merge_request_iid: mr_iid, project_id: @container.id)
        nil
      end

      def enriched_error_message(response)
        case response.reason
        when :namespace_missing
          ::Ai::FoundationalFlowMessages.namespace_missing_error(@current_user)
        when :usage_billing_forbidden
          ::Ai::FoundationalFlowMessages.usage_billing_forbidden_error
        else
          response.message
        end
      end

      def http_status_for_quota_error(reason)
        case reason
        when :user_missing, :namespace_missing
          :bad_request
        when :usage_quota_exceeded
          :payment_required
        when :usage_billing_forbidden
          :forbidden
        else
          :internal_server_error
        end
      end

      def foundational_agents_settings_container
        @current_user.duo_foundational_agents_container(@container.root_ancestor)
      end

      def resolve_agent_privileges
        return unless @container
        return unless valid_container_for_governance?

        if @params[:agent_privileges]
          return clamp_client_privileges if @privileges_from_client

          # App-set privileges keep their previous behaviour. Returning rather than
          # falling through matters: server resolution would overwrite them.
          return if web_surface?
          return unless Feature.enabled?(:duo_workflow_local_tool_governance, @container.root_ancestor)

          return clamp_client_privileges
        end

        # Not governed, so keep platform defaults.
        if ::Ai::ToolRules::GovernanceSurface.ungoverned?(resolved_surface)
          @params[:agent_privileges] = ::Ai::DuoWorkflows::Workflow::AgentPrivileges::DEFAULT_PRIVILEGES
          return
        end

        result = execute_governance_resolution_with_retry

        if result&.success?
          @params[:agent_privileges] = result.payload[:agent_privileges]
          @params[:pre_approved_agent_privileges] = result.payload[:pre_approved_agent_privileges]
        else
          Gitlab::AppLogger.error(
            message: governance_failure_message('failing closed with no tools', result),
            container_id: @container.id,
            container_type: @container.class.name
          )
          @params[:agent_privileges] = []
          @params[:pre_approved_agent_privileges] = []
        end
      end

      # Callers cannot be trusted to self-report privileges, so intersect them with the
      # governance resolution. The surface only selects which rule column is read.
      def clamp_client_privileges
        return unless known_privileges?(@params[:agent_privileges], @params[:pre_approved_agent_privileges])
        # Load-bearing now the flag check is gone: an ungoverned session must not clamp to web rules.
        return if ::Ai::ToolRules::GovernanceSurface.ungoverned?(resolved_surface)

        result = execute_governance_resolution_with_retry(surface: clamp_surface)

        if result&.success?
          @params[:agent_privileges] &= result.payload[:agent_privileges]

          # Always set pre-approved privileges: leaving them unset would let the
          # DB column default apply unclamped. When adopting the resolved list,
          # constrain it to the clamped grants (a model invariant).
          @params[:pre_approved_agent_privileges] =
            if @params[:pre_approved_agent_privileges]
              @params[:pre_approved_agent_privileges] & result.payload[:pre_approved_agent_privileges]
            else
              result.payload[:pre_approved_agent_privileges] & @params[:agent_privileges]
            end
        else
          Gitlab::AppLogger.error(
            message: governance_failure_message('failing closed with no privileges', result),
            container_id: @container.id,
            container_type: @container.class.name
          )
          @params[:agent_privileges] = []
          @params[:pre_approved_agent_privileges] = []
        end
      end

      def web_surface?
        surface = @params[:environment].presence || :web

        ::Ai::ToolRule::WEB_SURFACES.include?(surface.to_s)
      end

      # `defined?`, not `||=`: nil is the common web result and must be cached too,
      # or background_surface repeats its query.
      def resolved_surface
        return @resolved_surface if defined?(@resolved_surface)

        @resolved_surface = ::Ai::ToolRules::GovernanceSurface.for(
          environment: @params[:environment],
          container: @container,
          workflow_definition: workflow_definition
        )
      end

      # Unrecognized environments (notably `external`) clamp against web rules, unlike
      # degraded_surface which sends them to local_access. Pre-existing, see
      # https://gitlab.com/gitlab-org/gitlab/-/issues/624032
      def clamp_surface
        resolved_surface || :web
      end

      def execute_governance_resolution_with_retry(surface: nil)
        resolve_governance_with_retry(
          build_resolution_service(surface: surface),
          container_id: @container.id,
          container_type: @container.class.name
        )
      end

      def build_resolution_service(surface: nil)
        surface ||= resolved_surface || degraded_surface

        ::Ai::ToolRules::ResolutionService.new(
          namespace: @container.root_ancestor,
          surface: surface,
          project: @container.is_a?(::Project) ? @container : nil
        )
      end

      # Surface to use when background governance does not apply (flag off, or a
      # non-background environment). The environment passes through to its default
      # surface (ambient/web route to web_access), matching the pre-flag behaviour.
      def degraded_surface
        env = @params[:environment]&.to_s
        env.presence || 'web'
      end

      def valid_container_for_governance?
        @container.is_a?(::Project) || @container.is_a?(::Namespace)
      end
    end
  end
end
