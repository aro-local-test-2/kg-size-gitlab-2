# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Manager, feature_category: :ai_agents do
  let(:mock_tool_handler) { Class.new { def initialize(...); end } }

  before do
    custom_tools = {
      'get_mcp_server_version' => mock_tool_handler
    }
    ee_custom_tools = {
      'get_ee_mcp_server_version' => mock_tool_handler
    }
    stub_const("#{described_class}::CUSTOM_TOOLS", custom_tools)
    stub_const("::EE::#{described_class}::EE_CUSTOM_TOOLS", ee_custom_tools)

    # Stub the GRAPHQL_TOOLS with GraphQL tools
    graphql_tools = {
      'add_commit' => mock_tool_handler,
      'create_workitem_note' => mock_tool_handler
    }
    ee_graphql_tools = {
      'ee_create_workitem_note' => mock_tool_handler
    }
    stub_const("#{described_class}::GRAPHQL_TOOLS", graphql_tools)
    stub_const("::EE::#{described_class}::EE_GRAPHQL_TOOLS", ee_graphql_tools)
  end

  describe '#get_tool' do
    let(:manager) { described_class.new }

    describe 'semantic search tool' do
      let(:semantic_search_app) { instance_double(Grape::Endpoint) }
      let(:semantic_search_route) { instance_double(Grape::Router::Route, app: semantic_search_app) }
      let(:semantic_search_api_tool) { instance_double(Mcp::Tools::Base::ApiTool) }
      let(:aggregated_service) { instance_double(Mcp::Tools::SemanticSearch::SemanticSearchService) }
      let(:fake_api_class) { Class.new(API::Base) }

      before do
        allow(semantic_search_app).to receive(:route_setting).with(:mcp)
          .and_return({
            tool_name: :semantic_code_search,
            aggregators: [Mcp::Tools::SemanticSearch::SemanticSearchService]
          })
        allow(API::Base).to receive(:descendants).and_return([fake_api_class])
        allow(fake_api_class).to receive(:routes).and_return([semantic_search_route])
        allow(Mcp::Tools::Base::ApiTool).to receive(:new)
          .with(name: 'semantic_code_search', route: semantic_search_route)
          .and_return(semantic_search_api_tool)
        allow(Mcp::Tools::SemanticSearch::SemanticSearchService)
          .to receive(:tool_name).and_return('semantic_search')
        allow(Mcp::Tools::SemanticSearch::SemanticSearchService)
          .to receive(:new).with(tools: [semantic_search_api_tool]).and_return(aggregated_service)
        allow(aggregated_service).to receive_messages(tool_aliases: ['semantic_code_search'], version: '0.1.0')
      end

      it 'surfaces semantic_search not semantic_code_search as a standalone tool' do
        expect(manager.list_tools.keys).to include('semantic_search')
        expect(manager.list_tools.keys).not_to include('semantic_code_search')
      end

      it 'resolves semantic_code_search alias to semantic_search' do
        tool = manager.get_tool(name: 'semantic_code_search')

        expect(tool).to eq(aggregated_service)
      end
    end
  end

  describe '#initialize' do
    let(:routes) { [] }
    let(:fake_api_class) { Class.new(API::Base) }

    before do
      allow(API::Base).to receive(:descendants).and_return([fake_api_class])
      allow(fake_api_class).to receive(:routes).and_return(routes)
    end

    context 'with no API routes' do
      it 'initializes with custom and graphql tools' do
        manager = described_class.new

        expect(manager.tools.keys).to contain_exactly(
          'get_mcp_server_version',
          'get_ee_mcp_server_version',
          'create_workitem_note',
          'ee_create_workitem_note',
          'add_commit'
        )
      end
    end
  end
end
