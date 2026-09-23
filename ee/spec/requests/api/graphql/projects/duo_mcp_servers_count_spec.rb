# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'querying duoMcpServersCount', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:project) { create(:project, :with_duo_features_enabled, group: group) }
  let_it_be(:organization) { project.organization }
  let_it_be(:current_user) { create(:user, maintainer_of: project, organizations: [organization]) }

  def query_field(user: current_user)
    result = GitlabSchema.execute(%(
      query {
        project(fullPath: "#{project.full_path}") {
          duoMcpServersCount
        }
      }
    ), context: { current_user: user }).as_json

    result.dig('data', 'project', 'duoMcpServersCount')
  end

  before_all do
    group.ai_settings.update!(duo_workflow_mcp_enabled: true)
  end

  before do
    # Stub the entitlement seams so the real :read_ai_catalog_mcp_server policy grant is exercised.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(true)
  end

  it 'is zero when no configured agent uses an MCP server' do
    expect(query_field).to eq(0)
  end

  context 'when configured agents use MCP servers' do
    let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization) }
    let_it_be(:shared_server) { create(:ai_catalog_mcp_server, organization: organization) }

    before_all do
      [[server.id, shared_server.id], [shared_server.id]].each do |server_ids|
        agent = create(:ai_catalog_agent, organization: organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => server_ids
        })
        create(:ai_catalog_item_consumer, project: project, item: agent)
      end

      group.namespace_settings.update!(duo_custom_agents_enabled: true)
    end

    it 'counts each server of the configured agents once' do
      expect(query_field).to eq(2)
    end
  end

  # Which MCP servers a project's agents use is not public information.
  it 'is nil for a user who cannot read MCP servers here' do
    outsider = create(:user)

    expect(query_field(user: outsider)).to be_nil
  end

  it 'is not resolved unless it is requested' do
    expect(::Ai::DuoWorkflow::ProjectReadiness).not_to receive(:new)

    GitlabSchema.execute(%(
      query { project(fullPath: "#{project.full_path}") { id } }
    ), context: { current_user: current_user })
  end
end
