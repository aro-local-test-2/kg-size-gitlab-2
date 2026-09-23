# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ConnectionConfigService, feature_category: :duo_agent_platform do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, organizations: [organization]) }
  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_namespace) }
  let_it_be(:foreign_namespace) { create(:group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }

  let(:gitlab_token) { 'gitlab-oauth-token' }
  let(:namespace) { root_namespace }
  let(:passed_project) { nil }
  let(:passed_workflow) { workflow }
  let(:server_capabilities) { ['some_capability'] }
  let(:forwarded_grpc_metadata) { {} }
  let(:client_type) { nil }
  let(:feature_setting) { nil }
  let(:should_bill) { false }
  let(:model_metadata_from_service) { {} }
  let(:cloud_connector_headers) do
    { 'authorization' => 'Bearer cc-token', 'x-gitlab-authentication-type' => 'oidc' }
  end

  # Captured so the tool access policies, which are only observable through the
  # cloud connector token claims, can be asserted on.
  let(:captured_cloud_connector_args) { {} }

  let(:mcp_config_service) do
    instance_double(
      Ai::DuoWorkflows::McpConfigService,
      execute: { gitlab: { URL: 'http://mcp.example.com' } },
      gitlab_enabled_tools: %w[get_issue list_issues],
      preapproved_tool_names: []
    )
  end

  let(:request_metadata) do
    described_class::RequestMetadata.new(
      project_id: '11',
      namespace_id: '22',
      client_type: client_type,
      organization_id: organization.id,
      feature_setting_name: :duo_agent_platform,
      user_selected_model_identifier: nil,
      workflow_definition: 'chat',
      ai_catalog_item_version_id: nil,
      forwarded_grpc_metadata: forwarded_grpc_metadata
    )
  end

  let(:service) do
    described_class.new(
      user,
      gitlab_token,
      root_namespace: root_namespace,
      namespace: namespace,
      request_metadata: request_metadata,
      server_capabilities: server_capabilities,
      workflow: passed_workflow,
      project: passed_project
    )
  end

  subject(:config) { service.execute }

  before do
    allow(Gitlab::DuoWorkflow::Client).to receive(:cloud_connector_headers) do |**args|
      captured_cloud_connector_args.replace(args)
      cloud_connector_headers
    end
    allow(Gitlab::DuoWorkflow::Client).to receive_messages(
      url_for: 'dws.example.com:443',
      secure?: true,
      enable_extended_logging?: false
    )

    allow(Ai::FeatureSettingSelectionService).to receive(:new).and_return(
      instance_double(
        Ai::FeatureSettingSelectionService,
        execute: ServiceResponse.success(payload: feature_setting)
      )
    )
    allow(Ai::DuoWorkflows::McpConfigService).to receive(:new).and_return(mcp_config_service)
    allow(Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).to receive(:new).and_return(
      instance_double(
        Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService,
        execute: model_metadata_from_service
      )
    )
    allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).and_return(should_bill)
  end

  describe '#execute' do
    it 'returns the payload Workhorse expects' do
      expect(config).to include(
        Service: {
          Headers: a_hash_including('x-gitlab-oauth-token' => gitlab_token),
          URI: 'dws.example.com:443',
          Secure: true
        },
        McpServers: { gitlab: { URL: 'http://mcp.example.com' } },
        LockConcurrentFlow: true,
        ServerCapabilities: ['some_capability']
      )
    end

    it 'resolves the DWS endpoint from the feature setting' do
      config

      expect(Gitlab::DuoWorkflow::Client).to have_received(:url_for)
        .with(feature_setting: feature_setting, user: user)
      expect(Gitlab::DuoWorkflow::Client).to have_received(:secure?).with(feature_setting: feature_setting)
    end

    describe 'TimeoutHTTPRequests' do
      it 'follows the feature flag' do
        stub_feature_flags(timeout_dap_http_requests_in_workhorse: false)

        expect(config[:TimeoutHTTPRequests]).to be(false)
      end
    end
  end

  describe 'gRPC headers' do
    subject(:grpc_headers) { config.dig(:Service, :Headers) }

    it 'builds on the cloud connector headers' do
      expect(grpc_headers).to include(
        'authorization' => 'Bearer cc-token',
        'x-gitlab-authentication-type' => 'oidc',
        'x-gitlab-oauth-token' => gitlab_token,
        'x-gitlab-unidirectional-streaming' => 'enabled',
        'x-gitlab-enabled-mcp-server-tools' => 'get_issue,list_issues',
        'x-gitlab-self-hosted-dap-billing-enabled' => 'false',
        'x-gitlab-extended-logging' => 'false'
      )
    end

    it 'adds the organization header' do
      expect(grpc_headers).to include('x-gitlab-organization-id' => organization.id.to_s)
    end

    it 'attributes usage to the workflow service account when there is one' do
      grpc_headers

      expect(Gitlab::DuoWorkflow::Client).to have_received(:cloud_connector_headers)
        .with(hash_including(
          user: user,
          project_id: '11',
          namespace_id: 22,
          governing_namespace_id: root_namespace.id,
          subject: workflow.service_account || user
        ))
    end

    context 'when there is no workflow' do
      let(:passed_workflow) { nil }

      it 'attributes usage to the current user' do
        grpc_headers

        expect(Gitlab::DuoWorkflow::Client).to have_received(:cloud_connector_headers)
          .with(hash_including(subject: user))
      end
    end

    describe 'client type' do
      context 'when sent as a param' do
        let(:client_type) { 'browser' }

        it 'is used' do
          expect(grpc_headers).to include('x-gitlab-client-type' => 'browser')
        end
      end

      context 'when sent as both a param and a header' do
        let(:client_type) { 'browser' }
        let(:forwarded_grpc_metadata) { { 'x-gitlab-client-type' => 'vscode' } }

        it 'prefers the forwarded header' do
          expect(grpc_headers).to include('x-gitlab-client-type' => 'vscode')
        end
      end
    end

    describe 'forwarded metadata' do
      let(:forwarded_grpc_metadata) { { 'x-gitlab-client-name' => 'gitlab-vscode-extension' } }

      it 'is merged in' do
        expect(grpc_headers).to include('x-gitlab-client-name' => 'gitlab-vscode-extension')
      end
    end

    describe 'model prompt cache' do
      it 'reads the namespace setting' do
        allow(namespace).to receive(:namespace_settings).and_return(
          instance_double(NamespaceSetting, model_prompt_cache_enabled: true)
        )

        expect(grpc_headers).to include('x-gitlab-model-prompt-cache-enabled' => 'true')
      end

      context 'when the namespace has no settings' do
        it 'falls back to the root namespace' do
          allow(namespace).to receive(:namespace_settings).and_return(nil)
          allow(root_namespace).to receive(:model_prompt_cache_enabled).and_return(true)

          expect(grpc_headers).to include('x-gitlab-model-prompt-cache-enabled' => 'true')
        end
      end
    end

    describe 'model metadata' do
      let(:model_metadata_from_service) { { 'x-gitlab-model-metadata' => 'from-service' } }

      it 'uses the resolved model metadata' do
        expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
      end

      context 'when the workflow pinned its model and stickiness is enabled' do
        let(:header_key) { Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY }

        before do
          allow(workflow).to receive(:model_metadata_json).and_return('{"provider":"anthropic"}')
        end

        it 'reuses the pinned metadata instead of re-resolving' do
          expect(grpc_headers).to include(header_key => '{"provider":"anthropic"}')
          expect(Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).not_to have_received(:new)
        end

        it 're-resolves when stickiness is disabled' do
          stub_feature_flags(duo_workflow_provider_stickiness: false)

          expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
        end
      end
    end
  end

  describe 'CloudServiceForSelfHosted' do
    it 'is absent when the instance is not billed for self-hosted DAP' do
      expect(config[:CloudServiceForSelfHosted]).to be_nil
    end

    context 'when the instance is billed for self-hosted DAP' do
      let(:should_bill) { true }

      before do
        allow(CloudConnector::Tokens).to receive(:cloud_connector_token).and_return('self-hosted-token')
        allow(Gitlab::DuoWorkflow::Client).to receive(:cloud_connected_url).and_return('cloud.example.com:443')
      end

      it 'points at the cloud service with a cloud connector token' do
        expect(config[:CloudServiceForSelfHosted]).to match(
          Headers: a_hash_including('authorization' => 'Bearer self-hosted-token'),
          URI: 'cloud.example.com:443',
          Secure: true
        )
      end

      it 'leaves the gRPC authorization header untouched' do
        expect(config.dig(:Service, :Headers)).to include('authorization' => 'Bearer cc-token')
      end
    end
  end

  describe 'MCP enforcement namespace' do
    context 'when a project is in scope' do
      let(:passed_project) { project }

      it 'enforces on the project namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: project.project_namespace))
      end
    end

    context 'when the namespace belongs to the validated root' do
      let(:namespace) { subgroup }

      it 'enforces on the most specific namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: subgroup))
      end
    end

    context 'when the namespace is outside the validated root' do
      let(:namespace) { foreign_namespace }

      it 'anchors enforcement to the root namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: root_namespace))
      end
    end
  end

  describe 'tool access policies' do
    let(:no_policies) { { allow: [], ask: [], deny: [] } }

    def resolved_policies
      config

      captured_cloud_connector_args[:tool_access_policies]
    end

    context 'when governance resolves a verdict' do
      before do
        allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :web, ungoverned?: false)
        allow(Ai::ToolRules::ResolutionService).to receive(:new).and_return(
          instance_double(Ai::ToolRules::ResolutionService, execute: resolution_result)
        )
      end

      let(:resolution_result) do
        ServiceResponse.success(payload: {
          pre_approved_tools: %w[get_issue read_file],
          ask_tools: %w[read_file],
          denied_tools: %w[run_command]
        })
      end

      it 'subtracts ask and deny verdicts from the allow list' do
        expect(resolved_policies).to eq(
          allow: %w[get_issue],
          ask: %w[read_file],
          deny: %w[run_command]
        )
      end

      context 'when MCP contributes pre-approved tools' do
        let(:mcp_config_service) do
          instance_double(
            Ai::DuoWorkflows::McpConfigService,
            execute: {},
            gitlab_enabled_tools: [],
            preapproved_tool_names: %w[gitlab_search read_file]
          )
        end

        it 'appends them but still honours the ask verdict' do
          expect(resolved_policies).to eq(
            allow: %w[get_issue gitlab_search],
            ask: %w[read_file],
            deny: %w[run_command]
          )
        end
      end

      it 'stays empty when the surface is ungoverned' do
        allow(Ai::ToolRules::GovernanceSurface).to receive(:ungoverned?).and_return(true)

        expect(resolved_policies).to eq(no_policies)
      end

      context 'when resolution fails' do
        let(:resolution_result) { ServiceResponse.error(message: 'nope') }

        it 'stays empty' do
          expect(resolved_policies).to eq(no_policies)
        end
      end
    end
  end
end
