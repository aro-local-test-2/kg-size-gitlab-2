# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class WorkflowContextGenerationService
      include ::Gitlab::Utils::StrongMemoize

      AI_WORKFLOWS_SCOPES = (::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE]).to_set.freeze

      def initialize(
        current_user:, organization:, workflow_definition: nil, container: nil, service_account: nil,
        environment: nil, trigger_source: nil)
        @current_user = current_user
        @container = container
        @organization = organization
        @service_account = service_account
        @workflow_definition = workflow_definition
        @environment = environment
        @trigger_source = trigger_source
      end

      def generate_oauth_token
        ::Ai::DuoWorkflows::CreateOauthAccessTokenService.new(
          current_user: current_user,
          organization: organization,
          workflow_definition: workflow_definition
        ).execute
      end

      def generate_composite_oauth_token
        ::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService.new(
          current_user: current_user,
          organization: organization,
          service_account: service_account,
          container: container
        ).execute
      end

      def generate_workflow_token(flow_config_id: nil, flow_config: nil)
        feature_setting = duo_agent_platform_feature_setting
        tool_policies = resolve_tools

        ::Ai::DuoWorkflow::DuoWorkflowService::Client.new(
          duo_workflow_service_url: Gitlab::DuoWorkflow::Client.url_for(
            feature_setting: feature_setting,
            user: current_user
          ),
          current_user: current_user,
          secure: Gitlab::DuoWorkflow::Client.secure?(feature_setting: feature_setting),
          container: container,
          pre_approved_tools: tool_policies[:pre_approved_tools],
          denied_tools: tool_policies[:denied_tools],
          ask_tools: tool_policies.fetch(:ask_tools, [])
        ).generate_token(flow_config_id: flow_config_id, flow_config: flow_config)
      end

      def generate_oauth_token_with_composite_identity_support
        if autonomous_execution?
          generate_autonomous_oauth_token
        elsif composite_identity_enabled?
          generate_composite_oauth_token
        else
          generate_oauth_token
        end
      end

      def generate_autonomous_oauth_token
        ::Ai::DuoWorkflows::CreateAutonomousOauthAccessTokenService.new(
          service_account: service_account,
          organization: organization,
          container: container,
          trigger_source: trigger_source
        ).execute
      end

      # Returns true when the given access_token already carries all required AI workflow
      # scopes, so a new OAuth token does not need to be created for this request.
      def already_scoped_for_ai_workflows?(access_token)
        return false unless access_token&.scopes

        token_scopes = access_token.scopes.map(&:to_sym).to_set

        expected_scopes = if composite_identity_enabled?
                            (AI_WORKFLOWS_SCOPES + [:"user:#{current_user.id}"]).to_set
                          else
                            AI_WORKFLOWS_SCOPES
                          end

        token_scopes == expected_scopes
      end

      def duo_agent_platform_feature_setting
        ::Ai::FeatureSettingSelectionService
          .new(current_user, ai_feature, container&.root_ancestor)
          .execute.payload
      end
      strong_memoize_attr :duo_agent_platform_feature_setting

      private

      attr_reader :current_user, :container, :organization, :workflow_definition, :service_account, :environment,
        :trigger_source

      # Autonomous execution: SA acts alone with no human user. Keyed on
      # trigger_source because an SA authenticating as itself is the normal state
      # for any SA-owned token, so the identity check alone would also reroute
      # pre-existing API callers.
      def autonomous_execution?
        return false unless Workflow::AUTONOMOUS_TRIGGER_SOURCES.include?(trigger_source.to_s)

        current_user&.service_account? && service_account == current_user
      end

      def composite_identity_enabled?
        @service_account&.composite_identity_enforced
      end

      def ai_feature
        flow = ::Ai::Catalog::FoundationalFlow[workflow_definition]
        flow&.resolve_ai_feature(current_user: current_user)&.to_sym || :duo_agent_platform
      end

      def resolve_tools
        empty_hash = { pre_approved_tools: [], denied_tools: [], ask_tools: [] }
        return empty_hash unless container

        namespace = container.root_ancestor

        surface = ::Ai::ToolRules::GovernanceSurface.for(
          environment: environment, container: container, workflow_definition: workflow_definition
        )
        return empty_hash if ::Ai::ToolRules::GovernanceSurface.ungoverned?(surface)

        result = ::Ai::ToolRules::ResolutionService.new(
          namespace: namespace,
          surface: surface || :web,
          project: container.is_a?(::Project) ? container : nil
        ).execute

        result.success? ? result.payload : empty_hash
      end
    end
  end
end
