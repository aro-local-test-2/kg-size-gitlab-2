# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::GetWorkItemTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let_it_be(:work_item) do
    create(:work_item, project: project, title: 'An issue', health_status: :on_track)
  end

  let(:arguments) { { project_id: project.id.to_s, work_item_iid: work_item.iid } }
  let(:tool) { described_class.new(current_user: user, params: arguments, version: '0.1.0') }

  before_all do
    project.add_developer(user)
  end

  describe 'the EE query document' do
    it 'adds the EE widget fragments on top of the CE base selection', :aggregate_failures do
      operation = tool.graphql_operation

      # EE fragments
      expect(operation).to include('WorkItemWidgetHealthStatus', 'WorkItemWidgetStatus', 'WorkItemWidgetAgentPlan')

      # CE base markers, guarding against drift between the two documents
      expect(operation).to include('WorkItemWidgetNotes', 'WorkItemWidgetDevelopment', 'reference(full: true)')
    end
  end

  describe '#execute with licensed features' do
    before do
      stub_licensed_features(issuable_health_status: true)
    end

    it 'returns the health status widget', :aggregate_failures do
      result = tool.execute

      expect(result[:isError]).to be(false)

      health_widget = result[:structuredContent]['widgets']
        .find { |widget| widget['type'] == 'HEALTH_STATUS' }
      expect(health_widget['healthStatus']).to eq('onTrack')
    end
  end

  describe '#execute with an epic URL' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:epic) { create(:epic, group: group, title: 'An epic') }

    let(:arguments) { { url: "https://gitlab.com/groups/#{group.full_path}/-/epics/#{epic.iid}" } }

    before_all do
      group.add_developer(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    it 'resolves the epic work item through its /-/epics/ URL', :aggregate_failures do
      result = tool.execute

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]['iid']).to eq(epic.iid.to_s)
      expect(result[:structuredContent]['title']).to eq('An epic')
      expect(result[:structuredContent]['workItemType']['name']).to eq('Epic')
    end
  end

  describe '#execute with agent plan readiness_score' do
    let_it_be(:work_item_with_plan) { create(:work_item, project: project, title: 'Planned issue') }
    let_it_be(:agent_plan) do
      create(:work_item_agent_plan, work_item: work_item_with_plan, content: 'Plan content', readiness_score: 75)
    end

    let(:arguments) { { project_id: project.id.to_s, work_item_iid: work_item_with_plan.iid } }

    before do
      stub_licensed_features(ai_workflows: true)
    end

    context 'when workplan_score feature flag is enabled' do
      it 'returns readinessScore in the agent plan widget', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)

        agent_plan_widget = result[:structuredContent]['widgets']
          .find { |widget| widget['type'] == 'AGENT_PLAN' }
        expect(agent_plan_widget['readinessScore']).to eq(75)
      end
    end

    context 'when workplan_score feature flag is disabled' do
      before do
        stub_feature_flags(workplan_score: false)
      end

      it 'omits readinessScore from the agent plan widget', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)

        agent_plan_widget = result[:structuredContent]['widgets']
          .find { |widget| widget['type'] == 'AGENT_PLAN' }
        expect(agent_plan_widget['readinessScore']).to be_nil
      end
    end

    context 'when no agent plan exists' do
      let(:arguments) { { project_id: project.id.to_s, work_item_iid: work_item.iid } }

      it 'returns nil readinessScore', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)

        agent_plan_widget = result[:structuredContent]['widgets']
          .find { |widget| widget['type'] == 'AGENT_PLAN' }
        expect(agent_plan_widget['readinessScore']).to be_nil
      end
    end
  end
end
