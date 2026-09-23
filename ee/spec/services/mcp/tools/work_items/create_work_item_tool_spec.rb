# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::CreateWorkItemTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, developers: [user]) }

  describe '#mcp_tool_identifier' do
    let(:tool) { described_class.new(current_user: user, params: { project_id: project.id.to_s }) }

    it 'identifies itself as :create_work_item' do
      expect(tool.send(:mcp_tool_identifier)).to eq(:create_work_item)
    end
  end

  describe 'AI planning integration' do
    let(:params) { { project_id: project.id.to_s, title: 'MCP work item', type_name: 'Issue' } }
    let(:tool) { described_class.new(current_user: user, params: params) }

    context 'when ai_workflows is licensed' do
      before do
        stub_licensed_features(ai_workflows: true)
      end

      it 'creates a work item with ai_planning_enabled set to true' do
        result = tool.execute

        expect(result[:isError]).to be(false)

        created = GlobalID::Locator.locate(result[:structuredContent]['id'])
        expect(created.agent_plan).to be_present
        expect(created.agent_plan.ai_planning_enabled).to be(true)
      end

      context 'when the work item type does not support the agent plan widget' do
        let(:params) { { project_id: project.id.to_s, title: 'MCP incident', type_name: 'Incident' } }

        it 'creates the work item without an agent plan' do
          result = tool.execute

          expect(result[:isError]).to be(false)

          created = GlobalID::Locator.locate(result[:structuredContent]['id'])
          expect(created.agent_plan).to be_nil
        end
      end

      context 'when the request originates from a different MCP tool' do
        before do
          # No other MCP tool creates work items, so this is the only way to supply a
          # different identifier. The mutation's context check stays real.
          allow(tool).to receive(:mcp_tool_identifier).and_return(:some_other_tool)
        end

        it 'creates the work item without enabling AI planning' do
          result = tool.execute

          expect(result[:isError]).to be(false)

          created = GlobalID::Locator.locate(result[:structuredContent]['id'])
          expect(created.agent_plan).to be_nil
        end
      end

      context 'when the work item type is a custom type' do
        let_it_be(:group) { create(:group, :private, developers: [user]) }
        let_it_be(:group_project) { create(:project, group: group) }
        let_it_be(:custom_type) { create(:work_item_custom_type, namespace: group) }

        let(:params) do
          { project_id: group_project.id.to_s, title: 'MCP custom typed item', type_name: custom_type.name }
        end

        before do
          stub_licensed_features(ai_workflows: true, configurable_work_item_types: true)
          stub_saas_features(namespace_scoped_work_item_types: true)
        end

        it 'creates the work item with ai_planning_enabled set to true', :aggregate_failures do
          result = tool.execute

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]['type']).to eq(custom_type.name)

          created = GlobalID::Locator.locate(result[:structuredContent]['id'])
          expect(created.agent_plan).to be_present
          expect(created.agent_plan.ai_planning_enabled).to be(true)
        end
      end

      context 'when agent_plan content is also supplied' do
        let(:params) do
          {
            project_id: project.id.to_s,
            title: 'MCP work item with plan',
            type_name: 'Issue',
            agent_plan: 'Plan content from MCP'
          }
        end

        it 'preserves the supplied content and enables AI planning', :aggregate_failures do
          result = tool.execute

          expect(result[:isError]).to be(false)

          created = GlobalID::Locator.locate(result[:structuredContent]['id'])
          expect(created.agent_plan).to be_present
          expect(created.agent_plan.content).to eq('Plan content from MCP')
          expect(created.agent_plan.ai_planning_enabled).to be(true)
        end
      end
    end

    context 'when ai_workflows is not licensed' do
      before do
        stub_licensed_features(ai_workflows: false)
      end

      it 'creates the work item successfully without an agent plan' do
        result = tool.execute

        expect(result[:isError]).to be(false)

        created = GlobalID::Locator.locate(result[:structuredContent]['id'])
        expect(created.agent_plan).to be_nil
      end
    end

    context 'when workplan feature flag is disabled' do
      before do
        stub_licensed_features(ai_workflows: true)
        stub_feature_flags(workplan: false)
      end

      it 'creates the work item successfully without enabling AI planning' do
        result = tool.execute

        expect(result[:isError]).to be(false)

        created = GlobalID::Locator.locate(result[:structuredContent]['id'])
        expect(created.agent_plan).to be_nil
      end
    end
  end
end
