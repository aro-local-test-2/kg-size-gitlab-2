# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat -- JSON-RPC has single path for method invocation
RSpec.describe API::Mcp, 'Call tool request', feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }
  let_it_be(:consumer_group) { create(:group) }
  let_it_be(:flow_project) { create(:project, group: consumer_group) }
  let_it_be(:flow) { create(:ai_catalog_flow, :public, project: flow_project) }

  let_it_be_with_reload(:execution_project) do
    create(:project, :repository, group: consumer_group, developers: user)
  end

  let_it_be(:group_consumer) { create(:ai_catalog_item_consumer, item: flow, group: consumer_group) }

  let_it_be(:project_consumer) do
    create(:ai_catalog_item_consumer, item: flow, project: execution_project,
      parent_item_consumer: group_consumer)
  end

  let(:params) do
    { jsonrpc: '2.0', method: 'tools/call', params: tool_params, id: '1' }
  end

  before_all do
    consumer_group.add_developer(user)
    execution_project.update!(duo_features_enabled: true, duo_remote_flows_enabled: true)
    flow_project.update!(duo_features_enabled: true)
  end

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(flow_project, :ai_catalog).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(execution_project, :ai_catalog).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(execution_project, :duo_workflow).and_return(true)
  end

  describe '#start_duo_session' do
    let(:tool_params) do
      {
        name: 'start_duo_session',
        arguments: {
          project_id: execution_project.id.to_s,
          ai_catalog_item_consumer_id: project_consumer.id,
          goal: 'Fix the flaky spec'
        }
      }
    end

    let(:workflow) { build(:duo_workflows_workflow, user: user, project: execution_project) }

    let(:execute_service) do
      instance_double(::Ai::Catalog::Flows::ExecuteService,
        execute: ServiceResponse.success(payload: { workflow: workflow, workload_id: 124 }))
    end

    it 'forces start_workflow, which the model never sends', :aggregate_failures do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(execute_workflow: true)
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.dig('result', 'isError')).to be(false)
    end

    # The path is the only reliable signal: the MCP handler re-dispatches with the original
    # env, so PATH_INFO still points at /api/v4/mcp when the route runs.
    it 'marks the session as started over MCP' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(source_type: :mcp)
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns the session identifiers and a poll hint, not the raw workflow entity' do
      allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      content = json_response.dig('result', 'structuredContent')
      expect(content.keys).to match_array(%w[workflow_id status workload_id poll_after_seconds])
      expect(content['workload_id']).to eq(124)
      expect(json_response.dig('result', 'content', 0, 'text')).to include('get_duo_session')
    end

    context 'when the caller is not allowed to run the flow' do
      let_it_be(:outsider) { create(:user) }
      let_it_be(:outsider_token) { create(:oauth_access_token, user: outsider, scopes: [:mcp]) }

      it 'does not start a session' do
        expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        post api('/mcp', outsider, oauth_access_token: outsider_token), params: params, as: :json

        expect(json_response.dig('result', 'isError')).to be(true)
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
