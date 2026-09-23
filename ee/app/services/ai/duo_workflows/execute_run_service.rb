# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Executes the next run of a Duo session: the caller hands over a session
    # and what just happened (input arrived, a tool or plan approval was
    # decided), and the run goes to the runtime the flow's coding environment
    # implies unless the caller overrides it. Intended as the single entry
    # point every surface calls. Callers authorize the acting user; this
    # service enforces no permissions of its own.
    class ExecuteRunService
      RUNTIMES = %i[ci workhorse].freeze
      SUPPORTED_CODING_ENVIRONMENTS = {
        ci: %i[full none],
        workhorse: %i[none]
      }.freeze

      def self.runtime_for(workflow_definition, override: nil)
        runtime = override&.to_sym
        return runtime if RUNTIMES.include?(runtime)
        return if runtime

        ::Ai::Catalog::CodingEnvironment.default_runtime(
          ::Ai::Catalog::CodingEnvironment.resolve(workflow_definition: workflow_definition)
        )
      end

      def initialize(workflow, event:, runtime: nil)
        @workflow = workflow
        @event = RunEvent.new(event)
        @runtime = runtime&.to_sym
      end

      def execute
        return invalid_event unless event.valid_for?(workflow)

        resolved_runtime = resolve_runtime
        return runtime_unknown unless resolved_runtime
        return runtime_mismatch(resolved_runtime) if runtime_mismatch?
        return unsupported_environment(resolved_runtime) unless supported?(resolved_runtime)

        result = resolved_runtime == :ci ? start_ci_run : start_workhorse_run
        return result if result.error?

        ServiceResponse.success(payload: { workflow: workflow, **result.payload })
      end

      private

      attr_reader :workflow, :event, :runtime

      def start_ci_run
        return ci_session_error('Only project-level workflow is supported') unless workflow.project
        return ci_session_error('Service account is required for CI execution') unless workflow.service_account

        provisioning_error = provision_service_account
        return provisioning_error if provisioning_error

        params = build_ci_params
        return params if params.is_a?(ServiceResponse) && params.error?

        service_class.new(workflow: workflow, params: params).execute
      end

      def start_workhorse_run
        approval = event.approval? ? event.workhorse_approval : nil
        # A reply carries the user's text; the first turn passes none, so the
        # worker answers the session's own goal.
        goal = event.input? && workflow.input_required? ? event.text : nil
        ::Ai::Messaging::ServerSideTurnWorker.perform_async(workflow.id, approval, goal)

        ServiceResponse.success
      end

      def resolve_runtime
        return runtime if RUNTIMES.include?(runtime)
        return if runtime

        continuation? ? workflow.last_runtime : inferred_runtime
      end

      def runtime_mismatch?
        continuation? && runtime && runtime != workflow.last_runtime
      end

      def inferred_runtime
        ::Ai::Catalog::CodingEnvironment.default_runtime(coding_environment)
      end

      def coding_environment
        @coding_environment ||= ::Ai::Catalog::CodingEnvironment.resolve(
          workflow_definition: workflow.workflow_definition
        )
      end

      def supported?(resolved_runtime)
        SUPPORTED_CODING_ENVIRONMENTS.fetch(resolved_runtime).include?(coding_environment)
      end

      def provision_service_account
        link_composite_identity!

        result = ::Ai::ServiceAccountMemberAddService.new(workflow.project, workflow.service_account).execute
        return if result.success?

        ServiceResponse.error(message: result.message, reason: :service_account_error)
      end

      def link_composite_identity!
        return unless workflow.user
        return unless workflow.service_account.composite_identity_enforced?
        return if ai_settings.duo_workflow_oauth_application.nil?

        ::Gitlab::Auth::Identity.link_from_web_request(
          service_account: workflow.service_account,
          scoped_user: workflow.user
        )
      end

      def ai_settings
        ::Ai::Setting.for_organization_read_only(workflow.project.organization)
      end

      def build_ci_params
        context_service = ::Ai::DuoWorkflows::WorkflowContextGenerationService.new(
          current_user: workflow.user,
          organization: workflow.project.organization,
          container: workflow.project,
          service_account: workflow.service_account,
          workflow_definition: workflow.workflow_definition,
          environment: workflow.environment
        )
        oauth_token_result = context_service.generate_oauth_token_with_composite_identity_support
        return oauth_token_result if oauth_token_result.error?

        flow_config = ::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver.call(
          workflow.workflow_definition, workflow.project, user: workflow.user
        )
        workflow_token_result = context_service.generate_workflow_token(flow_config_id: flow_config[:flow_config_id])
        return workflow_token_result if workflow_token_result.error?

        # No report_artifacts, additional_context or trigger context here, unlike
        # ExecuteWorkflowService#build_start_workflow_params: those belong to
        # catalog and trigger flows, which this service does not start.
        {
          goal: workflow.goal,
          workflow_id: workflow.id,
          workflow_oauth_token: oauth_token_result.payload[:oauth_access_token].plaintext_token,
          workflow_service_token: workflow_token_result.payload[:token],
          service_account: workflow.service_account,
          source_branch: source_branch,
          workflow_metadata: Gitlab::DuoWorkflow::Client.metadata(
            workflow.user, namespace: workflow.project.root_ancestor, project: workflow.project
          ).to_json,
          duo_agent_platform_feature_setting: context_service.duo_agent_platform_feature_setting,
          flow_definition: workflow.workflow_definition,
          **flow_config,
          **resume_params
        }
      end

      def service_class
        continuation? ? ::Ai::DuoWorkflows::ResumeWorkflowService : ::Ai::DuoWorkflows::StartWorkflowService
      end

      def source_branch
        workflow.merge_request&.source_branch || workflow.project.default_branch_or_main
      end

      # An approval answers through human_approval/human_message; an input reply
      # carries its text as the fresh goal, overriding the stale
      # DUO_WORKFLOW_GOAL in ResumeWorkflowService. Approval ignores text.
      def resume_params
        return {} unless continuation?
        return { human_approval: event.approved?, human_message: event.message } if event.approval?

        { goal: event.text }
      end

      def continuation?
        !workflow.created?
      end

      def invalid_event
        ServiceResponse.error(message: 'The event is invalid for this workflow', reason: :invalid_event)
      end

      def runtime_unknown
        ServiceResponse.error(message: 'Could not resolve a runtime for this workflow', reason: :runtime_unknown)
      end

      def runtime_mismatch(resolved_runtime)
        ServiceResponse.error(
          message: "The #{resolved_runtime} runtime does not match the workflow's #{workflow.last_runtime} runtime",
          reason: :runtime_mismatch
        )
      end

      def unsupported_environment(resolved_runtime)
        ServiceResponse.error(
          message: "The #{workflow.workflow_definition} flow requires #{coding_environment} coding environment, " \
            "which #{resolved_runtime} does not support",
          reason: :unsupported_environment
        )
      end

      def ci_session_error(message)
        ServiceResponse.error(message: message, reason: :invalid_ci_session)
      end
    end
  end
end
