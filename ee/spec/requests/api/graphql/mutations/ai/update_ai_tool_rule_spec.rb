# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'UpdateAiToolRule', feature_category: :ai_agents do
  include GraphqlHelpers

  let_it_be(:namespace) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: namespace) }
  let_it_be(:project) { create(:project, namespace: namespace) }

  let(:params) do
    {
      full_path: namespace.full_path,
      tool_id: 'create_issue',
      web_access: 'ASK'
    }
  end

  let(:mutation) do
    graphql_mutation(
      :update_ai_tool_rule,
      params,
      <<~GQL
        toolRule {
          webAccess
        }
        errors
      GQL
    )
  end

  before do
    ::Ai::ToolRules::Registry.instance_variable_set(:@all_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@catalog_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@action_type_for, nil)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: owner) }

  it 'updates the tool rule and returns no errors', :aggregate_failures do
    request

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_blank
    expect(graphql_data_at(:update_ai_tool_rule, :errors)).to be_empty
    expect(graphql_data_at(:update_ai_tool_rule, :tool_rule, :web_access)).to eq('ASK')
  end

  context 'with a GitLab MCP server tool' do
    let(:input) { { full_path: namespace.full_path, tool_id: 'search', web_access: :DENY } }
    let(:mutation) do
      graphql_mutation(:update_ai_tool_rule, input,
        'errors toolRule { id webAccess actionType category source }')
    end

    context 'when MCP governance is inactive' do
      before do
        stub_feature_flags(duo_mcp_tool_governance: false)
      end

      it 'rejects the MCP tool name' do
        request

        expect(graphql_errors).to include(a_hash_including('message' => /search is not a known tool name/))
      end
    end

    context 'when MCP governance is active' do
      before do
        mcp_tools = instance_double(::Ai::ToolRules::GovernedMcpTools, empty?: false, rulable_names: ['search'])
        allow(mcp_tools).to receive(:action_type_for).with('search').and_return(:read)
        allow(::Ai::ToolRules::GovernedMcpTools).to receive(:for).and_return(mcp_tools)
      end

      it 'saves the rule and returns every non-null field populated' do
        request

        response = graphql_mutation_response(:update_ai_tool_rule)
        expect(response['errors']).to be_empty
        expect(response['toolRule']).to include(
          'id' => 'search',
          'webAccess' => 'DENY',
          'actionType' => 'READ',
          'category' => 'MCP',
          'source' => 'MCP'
        )
      end

      it 'persists the rule with the MCP source' do
        request

        expect(::Ai::ToolRule.find_by(namespace: namespace, tool_name: 'search').tool_source).to eq('mcp')
      end
    end
  end

  context 'with a group boundary' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_tool_rule do
      let(:user) { owner }
      let(:boundary_object) { namespace }
      let(:authz_mutation) do
        graphql_mutation(
          :update_ai_tool_rule,
          { full_path: namespace.full_path, tool_id: 'create_issue', web_access: 'ASK' },
          'errors'
        )
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with a project boundary' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_tool_rule do
      let(:user) { owner }
      let(:boundary_object) { project }
      let(:authz_mutation) do
        graphql_mutation(
          :update_ai_tool_rule,
          {
            full_path: project.root_ancestor.full_path,
            project_path: project.full_path,
            tool_id: 'create_issue',
            web_access: 'ASK'
          },
          'errors'
        )
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end
end
