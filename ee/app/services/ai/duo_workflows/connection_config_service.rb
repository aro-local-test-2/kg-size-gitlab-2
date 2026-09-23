# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Everything Workhorse needs to open the DWS gRPC stream on the caller's behalf.
    # Shared by the WebSocket handshake, where the client drives the flow, and by
    # :execute, where Workhorse itself does; the two differ only in how the workflow
    # is resolved, so it is passed in.
    #
    # Keys are PascalCase because Workhorse unmarshals this payload into Go structs.
    # See workhorse/internal/ai_assist/duoworkflow.
    class ConnectionConfigService
      include ::Gitlab::Utils::StrongMemoize

      # The raw request attributes the payload depends on. Held raw rather than
      # resolved because the outgoing headers echo caller-supplied ids verbatim.
      RequestMetadata = Data.define(
        :project_id,
        :namespace_id,
        :client_type,
        :organization_id,
        :feature_setting_name,
        :user_selected_model_identifier,
        :workflow_definition,
        :ai_catalog_item_version_id,
        # Already downcased for gRPC metadata, and pruned of blank values.
        :forwarded_grpc_metadata
      )

      def initialize(
        current_user, gitlab_token,
        root_namespace:, namespace:, request_metadata:, server_capabilities:,
        workflow: nil, project: nil)
        @current_user = current_user
        @gitlab_token = gitlab_token
        @root_namespace = root_namespace
        @namespace = namespace
        @request_metadata = request_metadata
        @server_capabilities = server_capabilities
        @workflow = workflow
        @project = project
      end

      def execute
        {
          Service: {
            Headers: grpc_headers,
            URI: ::Gitlab::DuoWorkflow::Client.url_for(feature_setting: feature_setting, user: current_user),
            Secure: ::Gitlab::DuoWorkflow::Client.secure?(feature_setting: feature_setting)
          },
          CloudServiceForSelfHosted: cloud_service_for_self_hosted,
          McpServers: mcp_config_service.execute,
          LockConcurrentFlow: true,
          TimeoutHTTPRequests: Feature.enabled?(:timeout_dap_http_requests_in_workhorse, current_user),
          ServerCapabilities: server_capabilities
        }
      end

      private

      attr_reader :current_user, :gitlab_token, :root_namespace, :namespace, :request_metadata,
        :server_capabilities, :workflow, :project

      def grpc_headers
        headers = cloud_connector_headers.merge(
          'x-gitlab-oauth-token' => gitlab_token,
          'x-gitlab-unidirectional-streaming' => 'enabled',
          'x-gitlab-enabled-mcp-server-tools' => mcp_config_service.gitlab_enabled_tools.join(','),
          'x-gitlab-model-prompt-cache-enabled' => model_prompt_cache_enabled.to_s,
          'x-gitlab-self-hosted-dap-billing-enabled' => self_hosted_dap_billing_enabled?.to_s,
          'x-gitlab-extended-logging' =>
            ::Gitlab::DuoWorkflow::Client.enable_extended_logging?(current_user, namespace: namespace).to_s
        ).merge(model_metadata_headers)

        # Forwarded last so a caller-sent header wins, matching the previous behaviour
        # for x-gitlab-client-type.
        headers.merge(request_metadata.forwarded_grpc_metadata)
      end

      def cloud_connector_headers
        headers = ::Gitlab::DuoWorkflow::Client.cloud_connector_headers(
          user: current_user,
          project_id: request_metadata.project_id,
          namespace_id: request_metadata.namespace_id.presence&.to_i,
          governing_namespace_id: root_namespace.id,
          feature_setting: feature_setting,
          tool_access_policies: tool_access_policies,
          subject: workflow&.service_account || current_user
        )

        # client type from the browser is sent as a param rather than a header
        headers['x-gitlab-client-type'] ||= request_metadata.client_type.presence
        ::Gitlab::AiGateway.add_organization_header!(headers, request_metadata.organization_id)

        headers
      end
      strong_memoize_attr :cloud_connector_headers

      def cloud_service_for_self_hosted
        return unless self_hosted_dap_billing_enabled?

        {
          Headers: cloud_connector_headers.merge(
            'authorization' => "Bearer #{::CloudConnector::Tokens.cloud_connector_token}"
          ),
          URI: ::Gitlab::DuoWorkflow::Client.cloud_connected_url(user: current_user),
          Secure: true
        }
      end

      def self_hosted_dap_billing_enabled?
        return false if workflow&.triggered_by_verification?

        ::Ai::SelfHostedDapBilling.should_bill?(feature_setting)
      end
      strong_memoize_attr :self_hosted_dap_billing_enabled?

      def feature_setting
        ::Ai::FeatureSettingSelectionService.new(
          current_user,
          request_metadata.feature_setting_name,
          root_namespace
        ).execute.payload
      end
      strong_memoize_attr :feature_setting

      def model_metadata_headers
        if Feature.enabled?(:duo_workflow_provider_stickiness, root_namespace) &&
            workflow&.model_metadata_json.present?
          return {
            ::Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY => workflow.model_metadata_json
          }
        end

        ::Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService.new(
          root_namespace: root_namespace,
          current_user: current_user,
          user_selected_model_identifier: request_metadata.user_selected_model_identifier,
          feature_name: request_metadata.feature_setting_name
        ).execute
      end
      strong_memoize_attr :model_metadata_headers

      def model_prompt_cache_enabled
        ns_settings = namespace.namespace_settings

        ns_settings ? ns_settings.model_prompt_cache_enabled : root_namespace.model_prompt_cache_enabled
      end

      def mcp_config_service
        ::Ai::DuoWorkflows::McpConfigService.new(
          current_user,
          gitlab_token,
          workflow_definition: request_metadata.workflow_definition,
          ai_catalog_item_version_id: request_metadata.ai_catalog_item_version_id,
          namespace: project&.project_namespace || enforcement_namespace
        )
      end
      strong_memoize_attr :mcp_config_service

      # Project-level blocks live on the project namespace (SetBlockService), so it wins.
      # The group namespace is anchored to the validated root because it can come from the
      # unvalidated X-Gitlab-Namespace-Id header; unanchored, a foreign header would skip
      # this hierarchy's blocks. Freshness relies on the web client reconnecting per message
      # and per approval; a persistent socket would degrade enforcement to per-session. See
      # https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/work_items/2694.
      def enforcement_namespace
        return namespace if namespace.root_ancestor.id == root_namespace.id

        root_namespace
      end

      def tool_access_policies
        governance_surface = ::Ai::ToolRules::GovernanceSurface.for(
          environment: workflow.presence&.environment,
          container: root_namespace,
          workflow_definition: workflow.presence&.workflow_definition
        )
        # Must stay empty: DWS reads empty allow/ask/deny as governance inactive and
        # keeps the client's pre-approvals. A non-empty allow would replace them.
        # Pinned DWS-side by test_compile_and_run_graph_keeps_client_preapproved_when_governance_inactive.
        return no_tool_access_policies if ::Ai::ToolRules::GovernanceSurface.ungoverned?(governance_surface)

        result = ::Ai::ToolRules::ResolutionService.new(
          namespace: root_namespace,
          surface: governance_surface || :web,
          project: project
        ).execute

        return no_tool_access_policies unless result.success?

        # MCP pre-approvals are appended after governance has resolved, so a verdict
        # has to be subtracted again here or the append outlives it.
        allowed_tools = result.payload[:pre_approved_tools] + mcp_config_service.preapproved_tool_names
        allowed_tools -= result.payload[:ask_tools]
        allowed_tools -= result.payload[:denied_tools]

        {
          allow: allowed_tools.uniq,
          ask: result.payload[:ask_tools],
          deny: result.payload[:denied_tools]
        }
      end
      strong_memoize_attr :tool_access_policies

      def no_tool_access_policies
        { allow: [], ask: [], deny: [] }
      end
    end
  end
end
