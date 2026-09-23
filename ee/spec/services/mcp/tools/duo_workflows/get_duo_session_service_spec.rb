# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::GetDuoSessionService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }

  let(:service) { described_class.new(name: 'get_duo_session') }

  before do
    service.set_cred(current_user: user)
  end

  describe 'class configuration' do
    it 'registers version 0.1.0 and the deprecated alias' do
      expect(described_class.available_versions).to include('0.1.0')
      expect(described_class.tool_aliases).to contain_exactly('get_duo_workflow_status')
    end

    it 'is registered as an EE GraphQL tool and resolves its alias' do
      expect(::EE::Mcp::Tools::Manager::EE_GRAPHQL_TOOLS).to include('get_duo_session' => described_class)
      expect(::Mcp::Tools::Manager.new.get_tool(name: 'get_duo_workflow_status')).to be_a(described_class)
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        required: %w[workflow_id],
        properties: {
          workflow_id: {
            type: 'integer',
            description: 'Workflow ID returned by trigger_duo_flow or ask_duo_agent.'
          }
        }
      })
    end
  end

  describe '#execute' do
    let(:request) { instance_double(ActionDispatch::Request) }
    let(:params) { { arguments: { workflow_id: 1 } } }

    it 'delegates to the GraphQL tool with the selected version and arguments' do
      expect(Mcp::Tools::DuoWorkflows::GetDuoSessionTool).to receive(:new).with(
        current_user: user,
        params: params[:arguments],
        version: '0.1.0'
      ).and_call_original

      service.execute(request: request, params: params)
    end

    it 'rejects unknown arguments' do
      result = service.execute(
        request: request,
        params: { arguments: { workflow_id: 1, project_id: 'gitlab-org/gitlab' } }
      )

      expect(result.dig(:content, 0, :text)).to include('project_id is invalid')
    end

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response' do
        result = service.execute(request: request, params: params)

        expect(result).to include(isError: true)
        expect(result.dig(:content, 0, :text)).to include('current_user is not set')
      end
    end
  end
end
