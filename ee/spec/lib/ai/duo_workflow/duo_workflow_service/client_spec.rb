# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::DuoWorkflowService::Client, feature_category: :duo_agent_platform do
  shared_examples 'returns error when service url is blank' do |method|
    context 'when duo_workflow_service_url is blank' do
      where(:duo_workflow_service_url) { [nil, '', '   '] }

      with_them do
        it 'returns an error ServiceResponse without calling the stub' do
          result = client.public_send(method)

          expect(result).to be_error
          expect(result.message).to eq('Duo Workflow service URL is not configured')
          expect(DuoWorkflowService::DuoWorkflow::Stub).not_to have_received(:new)
        end
      end
    end
  end

  let_it_be(:current_user) { create(:user) }
  let(:duo_workflow_service_url) { 'example.com:443' }
  let(:secure) { true }
  let(:feature_setting) { nil }
  let(:container) { nil }
  let(:stub) { instance_double('DuoWorkflowService::DuoWorkflow::Stub') }
  let(:request) { instance_double('DuoWorkflowService::GenerateTokenRequest') }
  let(:response) { double(token: 'a user jwt', expiresAt: 'a timestamp') } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error  the DuoWorkflowService::GenerateTokenResponse class does not implement the class method: token
  let(:channel_credentials) { instance_of(GRPC::Core::ChannelCredentials) }

  subject(:client) do
    described_class.new(
      duo_workflow_service_url: duo_workflow_service_url,
      current_user: current_user,
      secure: secure,
      feature_setting: feature_setting,
      container: container
    )
  end

  before do
    allow(DuoWorkflowService::DuoWorkflow::Stub).to receive(:new).with(anything, channel_credentials).and_return(stub)
    allow(stub).to receive(:generate_token).and_return(response)
    allow(DuoWorkflowService::GenerateTokenRequest).to receive(:new).and_return(request)
    allow(::CloudConnector::Tokens).to receive(:get).and_return('instance jwt')
  end

  describe '#generate_token' do
    it 'sends the correct metadata hash' do
      allow(::Gitlab::AiGateway).to receive(:enabled_instance_verbose_ai_logs).and_return('true')
      expect(::CloudConnector::Tokens).to receive(:get).and_return('instance jwt')

      client.generate_token

      expect(stub).to have_received(:generate_token).with(
        request,
        metadata: {
          "authorization" => "Bearer instance jwt",
          "x-gitlab-authentication-type" => "oidc",
          "x-gitlab-client-type" => "gitlab-rails",
          "x-gitlab-instance-id" => ::Gitlab::GlobalAnonymousId.instance_id,
          "x-gitlab-realm" => ::CloudConnector.gitlab_realm,
          "x-gitlab-global-user-id" => ::Gitlab::GlobalAnonymousId.user_id(current_user),
          "x-gitlab-user-id" => current_user.id.to_s,
          "x-gitlab-version" => ::Gitlab.version_info.to_s,
          "x-gitlab-deployment-type" => "self-managed",
          "x-gitlab-enabled-feature-flags" => "",
          "x-gitlab-enabled-instance-verbose-ai-logs" => "true",
          "x-gitlab-feature-enabled-by-namespace-ids" => "",
          "x-gitlab-feature-enablement-type" => "",
          "x-gitlab-host-name" => "localhost",
          "x-gitlab-subject-type" => "human",
          "x-gitlab-is-team-member" => "false",
          "x-gitlab-unit-primitive" => "duo_agent_platform",
          "x-gitlab-rails-send-start" => a_kind_of(String),
          "x-request-id" => a_kind_of(String)
        }
      )
    end

    it 'includes the authorized foundational flow ID in the request' do
      expect(DuoWorkflowService::GenerateTokenRequest.descriptor.lookup('flow_config_id')).not_to be_nil
      expect(DuoWorkflowService::GenerateTokenRequest).to receive(:new).with(
        flow_config_id: 'developer', flow_config: nil
      ).and_return(request)

      client.generate_token(flow_config_id: 'developer')
    end

    it 'includes the authoritative flow config in the request' do
      flow_config = { 'version' => 'v1', 'flow' => { 'entry_point' => 'agent' } }

      expect(DuoWorkflowService::GenerateTokenRequest.descriptor.lookup('flow_config').number).to eq(3)
      expect(DuoWorkflowService::GenerateTokenRequest).to receive(:new).with(
        flow_config_id: nil, flow_config: Google::Protobuf::Struct.decode_json(flow_config.to_json)
      ).and_return(request)

      client.generate_token(flow_config: flow_config)
    end

    it 'omits the flow ID and flow config for existing callers' do
      expect(DuoWorkflowService::GenerateTokenRequest).to receive(:new).with(
        flow_config_id: nil, flow_config: nil
      ).and_return(request)

      client.generate_token
    end

    context 'when a feature setting is provided' do
      let(:feature_setting) { create(:ai_feature_setting, :code_completions, provider: :self_hosted) }

      it 'forwards feature_setting to Gitlab::AiGateway.cloud_connector_token' do
        expect(::Gitlab::AiGateway).to receive(:cloud_connector_token)
          .with(:duo_agent_platform, current_user, hash_including(feature_setting: feature_setting))
          .and_return('instance jwt')

        client.generate_token
      end
    end

    it 'returns a success ServiceResponse with token and expires_at' do
      result = client.generate_token

      expect(result).to be_success
      expect(result.message).to eq('JWT Generated')
      expect(result.payload[:token]).to eq('a user jwt')
      expect(result.payload[:expires_at]).to eq('a timestamp')
    end

    context 'when secure is false' do
      let(:secure) { false }
      let(:channel_credentials) { :this_channel_is_insecure }

      it 'calls with insecure channel credentials' do
        result = client.generate_token

        expect(result).to be_success
      end
    end

    it_behaves_like 'returns error when service url is blank', :generate_token

    context 'when an error occurs' do
      before do
        allow(stub).to receive(:generate_token).and_raise(StandardError.new('Test error'))
      end

      it 'returns an error ServiceResponse' do
        result = client.generate_token

        expect(result).to be_error
        expect(result.message).to eq('Test error')
      end
    end

    context 'when the flow config cannot be encoded' do
      before do
        allow(Google::Protobuf::Struct).to receive(:decode_json)
          .and_raise(Google::Protobuf::ParseError.new('Invalid JSON'))
      end

      it 'returns an error ServiceResponse without calling the stub' do
        expect(stub).not_to receive(:generate_token)

        result = client.generate_token(flow_config: { 'version' => 'v1' })

        expect(result).to be_error
        expect(result.message).to eq('Invalid JSON')
      end
    end

    context 'when the user is a GitLab team member' do
      before do
        allow_next_instance_of(::Gitlab::Tracking::StandardContext) do |instance|
          allow(instance).to receive(:gitlab_team_member?).and_return(true)
        end
      end

      it 'adds extra claims into the CloudConnector token' do
        expect(::CloudConnector::Tokens)
          .to receive(:get)
          .with(hash_including(extra_claims: { gitlab_team_member: true, skip_usage_cutoff: true,
                                               tool_access_policies: '{"allow":[],"ask":[],"deny":[]}' }))
          .and_return('instance jwt')

        client.generate_token
      end
    end

    context 'when the user is not a GitLab team member' do
      before do
        allow_next_instance_of(::Gitlab::Tracking::StandardContext) do |instance|
          allow(instance).to receive(:gitlab_team_member?).and_return(false)
        end
      end

      it 'adds extra claims into the CloudConnector token' do
        expect(::CloudConnector::Tokens)
          .to receive(:get)
          .with(hash_including(extra_claims: { gitlab_team_member: false, skip_usage_cutoff: false,
                                               tool_access_policies: '{"allow":[],"ask":[],"deny":[]}' }))
          .and_return('instance jwt')

        client.generate_token
      end
    end

    context 'when the current_user is nil' do
      let(:current_user) { nil }

      it 'handles the extra claims in the CloudConnector token' do
        expect(::CloudConnector::Tokens)
          .to receive(:get)
          .with(hash_including(extra_claims: { gitlab_team_member: false, skip_usage_cutoff: false,
                                               tool_access_policies: '{"allow":[],"ask":[],"deny":[]}' }))
          .and_return('instance jwt')

        client.generate_token
      end
    end

    context 'when the resolution service returned ask tools' do
      let(:client) do
        described_class.new(
          duo_workflow_service_url: duo_workflow_service_url,
          current_user: current_user,
          secure: secure,
          pre_approved_tools: ['list_issues'],
          denied_tools: ['create_work_item'],
          ask_tools: ['run_command']
        )
      end

      it 'carries all three lists in the tool_access_policies claim' do
        expect(::CloudConnector::Tokens)
          .to receive(:get)
          .with(hash_including(extra_claims: hash_including(
            tool_access_policies: '{"allow":["list_issues"],"ask":["run_command"],"deny":["create_work_item"]}'
          )))
          .and_return('instance jwt')

        client.generate_token
      end
    end

    context 'when a container is provided' do
      let_it_be(:project) { create(:project) }
      let(:container) { project }

      it 'scopes governing_namespace to the container' do
        expect(current_user).to receive(:governing_namespace).with(container).and_call_original

        client.generate_token
      end
    end

    context 'when no container is provided' do
      it 'resolves governing_namespace without a scope' do
        expect(current_user).to receive(:governing_namespace).with(nil).and_call_original

        client.generate_token
      end
    end

    context 'when propagating the root namespace claim' do
      let_it_be(:governing_namespace) { create(:group) }

      before do
        allow(current_user).to receive(:governing_namespace).and_return(governing_namespace)
      end

      context 'when gitlab_com_subscriptions SaaS feature is available' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it 'includes gitlab_root_namespace_id in the CloudConnector extra claims' do
          expect(::CloudConnector::Tokens)
            .to receive(:get)
            .with(hash_including(extra_claims: hash_including(gitlab_root_namespace_id: governing_namespace.id)))
            .and_return('instance jwt')

          client.generate_token
        end
      end

      context 'when gitlab_com_subscriptions SaaS feature is not available' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'does not include gitlab_root_namespace_id in the CloudConnector extra claims' do
          expect(::CloudConnector::Tokens)
            .to receive(:get)
            .with(hash_including(extra_claims: hash_excluding(:gitlab_root_namespace_id)))
            .and_return('instance jwt')

          client.generate_token
        end
      end

      context 'when the user has no governing namespace' do
        before do
          allow(current_user).to receive(:governing_namespace).and_return(nil)
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it 'does not raise and omits the root namespace claim' do
          expect(::CloudConnector::Tokens)
            .to receive(:get)
            .with(hash_including(extra_claims: hash_excluding(:gitlab_root_namespace_id)))
            .and_return('instance jwt')

          expect { client.generate_token }.not_to raise_error
        end
      end
    end

    context 'when response does not have server_capabilities method (backward compatibility)' do
      let(:legacy_response) { double(token: 'a user jwt', expiresAt: 'a timestamp') } # rubocop:disable RSpec/VerifiedDoubles -- instance_double raises error for DuoWorkflowService::GenerateTokenResponse

      before do
        allow(stub).to receive(:generate_token).and_return(legacy_response)
      end

      it 'returns success with empty capabilities array' do
        result = client.generate_token

        expect(result).to be_success
        expect(result.payload[:capabilities]).to eq([])
      end
    end

    context 'when response has server_capabilities method' do
      let(:modern_response) do
        double( # rubocop:disable RSpec/VerifiedDoubles -- instance_double raises error for DuoWorkflowService::GenerateTokenResponse
          token: 'a user jwt',
          expiresAt: 'a timestamp',
          server_capabilities: %w[advanced_search tool_call_approval]
        )
      end

      before do
        allow(stub).to receive(:generate_token).and_return(modern_response)
      end

      it 'returns success with capabilities from response' do
        result = client.generate_token

        expect(result).to be_success
        expect(result.payload[:capabilities]).to eq(%w[advanced_search tool_call_approval])
      end
    end
  end

  describe '#track_self_hosted_client_event' do
    let(:request_id) { 'req-123' }
    let(:feature_qualified_name) { 'code_suggestions' }
    let(:event) { instance_double('DuoWorkflowService::TrackSelfHostedClientEvent') }
    let(:responses) { [double('TrackSelfHostedAction')] } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error

    before do
      allow(DuoWorkflowService::TrackSelfHostedClientEvent).to receive(:new).and_return(event)
      allow(stub).to receive(:track_self_hosted_execute_workflow).and_return(responses)
      allow(::CloudConnector::Tokens).to receive(:get).and_return('derived-token')
    end

    it 'builds the event with correct fields' do
      expect(DuoWorkflowService::TrackSelfHostedClientEvent).to receive(:new).with(
        requestID: request_id,
        workflowID: request_id,
        featureQualifiedName: feature_qualified_name,
        featureAiCatalogItem: false
      )

      client.track_self_hosted_client_event(
        request_id: request_id,
        feature_qualified_name: feature_qualified_name
      )
    end

    it 'sends the event array and consumes the response' do
      expect(stub).to receive(:track_self_hosted_execute_workflow).with([event], metadata: anything)

      result = client.track_self_hosted_client_event(
        request_id: request_id,
        feature_qualified_name: feature_qualified_name
      )

      expect(result).to be_success
      expect(result.message).to eq('Billing event tracked')
    end

    it 'passes feature_ai_catalog_item when provided' do
      expect(DuoWorkflowService::TrackSelfHostedClientEvent).to receive(:new).with(
        hash_including(featureAiCatalogItem: true)
      )

      client.track_self_hosted_client_event(
        request_id: request_id,
        feature_qualified_name: feature_qualified_name,
        feature_ai_catalog_item: true
      )
    end

    context 'when the stub raises' do
      before do
        allow(stub).to receive(:track_self_hosted_execute_workflow).and_raise(StandardError, 'network error')
      end

      it 'returns an error ServiceResponse' do
        result = client.track_self_hosted_client_event(
          request_id: request_id,
          feature_qualified_name: feature_qualified_name
        )

        expect(result).to be_error
        expect(result.message).to eq('network error')
      end
    end
  end

  describe '#list_tools' do
    let(:list_response) { double('ListToolsResponse') } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error

    before do
      allow(stub).to receive(:list_tools).and_return(list_response)
      allow(Google::Protobuf).to receive(:encode_json).with(list_response)
        .and_return('{"tools":[{"name":"foo"}],"evalDataset":{"count":1}}')
    end

    it 'returns success with sliced tools and evalDataset' do
      result = client.list_tools

      expect(result).to be_success
      expect(result.message).to eq('Tools listed')
      expect(result.payload).to eq({ 'tools' => [{ 'name' => 'foo' }], 'evalDataset' => { 'count' => 1 } })
    end

    it_behaves_like 'returns error when service url is blank', :list_tools

    it 'returns error when stub raises' do
      allow(stub).to receive(:list_tools).and_raise(StandardError, 'boom')

      result = client.list_tools

      expect(result).to be_error
      expect(result.message).to eq('boom')
    end
  end

  describe '#list_capabilities' do
    let(:capability_without_metadata) { double(name: 'tool_call_approval', metadata: '') } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error for protobuf response classes
    let(:capability_with_metadata) { double(name: 'duo_developer', metadata: '{"flow_version":"2.0.0"}') } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error for protobuf response classes
    let(:list_response) { double(capabilities: [capability_without_metadata, capability_with_metadata]) } # rubocop:disable RSpec/VerifiedDoubles -- instance_double keeps raising error for protobuf response classes

    before do
      allow(stub).to receive(:list_capabilities).and_return(list_response)
    end

    it 'returns success with capability names and parsed metadata' do
      result = client.list_capabilities

      expect(result).to be_success
      expect(result.message).to eq('Capabilities listed')
      expect(result.payload[:capabilities]).to eq(
        [
          { name: 'tool_call_approval', metadata: nil },
          { name: 'duo_developer', metadata: { 'flow_version' => '2.0.0' } }
        ]
      )
    end

    it_behaves_like 'returns error when service url is blank', :list_capabilities

    it 'returns error when stub raises' do
      allow(stub).to receive(:list_capabilities).and_raise(StandardError, 'boom')

      result = client.list_capabilities

      expect(result).to be_error
      expect(result.message).to eq('boom')
    end
  end

  describe '#validate_flow_config' do
    let(:flow_config) { { 'version' => 'v1', 'environment' => 'ambient' } }
    let(:valid_response) { double(valid: true, errors: []) } # rubocop:disable RSpec/VerifiedDoubles -- instance_double raises error for protobuf response classes
    let(:invalid_response) { double(valid: false, errors: ['Component missing input variables: goal']) } # rubocop:disable RSpec/VerifiedDoubles -- instance_double raises error for protobuf response classes

    before do
      allow(stub).to receive(:validate_flow_config).and_return(valid_response)
    end

    context 'when the flow config is valid' do
      it 'returns a success ServiceResponse' do
        result = client.validate_flow_config(flow_config: flow_config)

        expect(result).to be_success
      end
    end

    context 'when the flow config is invalid' do
      before do
        allow(stub).to receive(:validate_flow_config).and_return(invalid_response)
      end

      it 'returns an error ServiceResponse with the validation errors' do
        result = client.validate_flow_config(flow_config: flow_config)

        expect(result).to be_error
        expect(result.message).to eq(['Component missing input variables: goal'])
        expect(result.reason).to eq(described_class::ERROR_REASON_INVALID_FLOW_CONFIG)
      end
    end

    context 'when duo_workflow_service_url is blank' do
      where(:duo_workflow_service_url) { [nil, '', '   '] }

      with_them do
        it 'returns an error ServiceResponse without calling the stub' do
          result = client.validate_flow_config(flow_config: flow_config)

          expect(result).to be_error
          expect(result.message).to eq('Duo Workflow service URL is not configured')
          expect(result.reason).to eq(described_class::ERROR_REASON_SERVICE_UNAVAILABLE)
          expect(DuoWorkflowService::DuoWorkflow::Stub).not_to have_received(:new)
        end
      end
    end

    context 'when the flow config is blank' do
      where(:flow_config) { [nil, {}] }

      with_them do
        it 'returns an invalid-config error' do
          result = client.validate_flow_config(flow_config: flow_config)

          expect(result).to be_error
          expect(result.message).to eq('Flow definition is missing and cannot be validated')
          expect(result.reason).to eq(described_class::ERROR_REASON_INVALID_FLOW_CONFIG)
        end
      end
    end

    context 'when the gRPC call raises an error' do
      before do
        allow(stub).to receive(:validate_flow_config).and_raise(StandardError.new('connection refused'))
      end

      it 'returns a user-friendly error message' do
        result = client.validate_flow_config(flow_config: flow_config)

        expect(result).to be_error
        expect(result.message).to eq(
          'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.'
        )
        expect(result.reason).to eq(described_class::ERROR_REASON_SERVICE_UNAVAILABLE)
      end

      it 'logs the error to AppLogger' do
        expect(Gitlab::AppLogger).to receive(:error).with('DWS ValidateFlowConfig failed: connection refused')

        client.validate_flow_config(flow_config: flow_config)
      end
    end
  end
end
