# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::SaveWorkItemService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let(:service) { described_class.new(name: 'save_work_item') }
  let(:request) { instance_double(ActionDispatch::Request) }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe '#input_schema' do
    let(:properties) { service.input_schema[:properties] }

    it 'adds the EE-only properties', :aggregate_failures do
      expect(properties[:health_status]).to eq(
        type: 'string',
        enum: %w[onTrack needsAttention atRisk],
        description: 'Health status of the work item.'
      )
      expect(properties[:weight]).to eq(
        type: 'integer',
        minimum: 0,
        description: 'Weight of the work item.'
      )
      expect(properties[:clear_weight]).to eq(
        type: 'boolean',
        description: 'Update only. Removes the weight; wins over weight.'
      )
      expect(properties[:status_id]).to eq(
        type: 'string',
        description: 'Global ID of the status to set.'
      )
      expect(properties[:is_fixed]).to eq(
        type: 'boolean',
        description: 'Whether start and due dates are fixed. When false, dates roll up ' \
          'from child items and start_date/due_date are ignored.'
      )
      expect(properties[:agent_plan]).to eq(
        type: 'string',
        description: 'Markdown content of the agent plan. Requires the workplan feature.'
      )
      expect(properties[:readiness_score]).to eq(
        type: 'integer',
        minimum: 0,
        maximum: 100,
        description: 'Readiness score of the agent plan (0-100). ' \
          'Requires the workplan_score feature flag. ' \
          'Omit to leave the existing score unchanged.'
      )
    end

    it 'preserves the CE properties', :aggregate_failures do
      expect(properties).to include(:url, :title, :type_name, :work_item_iid)
      expect(service.input_schema[:required]).to eq([])
    end
  end

  describe '#execute' do
    before do
      stub_licensed_features(issue_weights: true, ai_workflows: true)
    end

    it 'creates a work item with a weight' do
      result = service.execute(
        request: request,
        params: { arguments: { project_id: project.id.to_s, title: 'Weighted', type_name: 'Issue', weight: 3 } }
      )

      expect(result[:isError]).to be(false)

      created = WorkItem.find(GlobalID.parse(result[:structuredContent]['id']).model_id.to_i)
      expect(created.weight).to eq(3)
    end

    context 'with clear_weight' do
      let_it_be_with_reload(:work_item) { create(:work_item, :issue, project: project, weight: 5) }

      it 'clears the weight' do
        result = service.execute(
          request: request,
          params: { arguments: { project_id: project.id.to_s, work_item_iid: work_item.iid, clear_weight: true } }
        )

        expect(result[:isError]).to be(false)
        expect(work_item.reload.weight).to be_nil
      end
    end

    context 'with readiness_score' do
      let_it_be_with_reload(:work_item) { create(:work_item, :issue, project: project) }

      context 'when workplan_score feature flag is enabled' do
        it 'sets the readiness_score on update' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                work_item_iid: work_item.iid,
                readiness_score: 80
              }
            }
          )

          expect(result[:isError]).to be(false)
          expect(work_item.reload.agent_plan.readiness_score).to eq(80)
        end

        it 'sets the readiness_score on create' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                title: 'Scored item',
                type_name: 'Issue',
                readiness_score: 50
              }
            }
          )

          expect(result[:isError]).to be(false)

          created = WorkItem.find(GlobalID.parse(result[:structuredContent]['id']).model_id.to_i)
          expect(created.agent_plan.readiness_score).to eq(50)
        end
      end

      context 'when workplan_score feature flag is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'returns an error and does not persist the readiness_score', :aggregate_failures do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                work_item_iid: work_item.iid,
                readiness_score: 80
              }
            }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('workplan_score')
          expect(work_item.reload.agent_plan).to be_nil
        end
      end
    end
  end

  describe '#execute with label names on a group-level work item' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:group_label) { create(:group_label, group: group, title: 'strategic') }
    let_it_be_with_reload(:epic_item) { create(:work_item, :epic, namespace: group) }

    before_all do
      group.add_developer(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    it 'resolves the names against the group', :aggregate_failures do
      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, add_labels: %w[strategic] } }
      )

      expect(result[:isError]).to be(false)
      expect(epic_item.reload.labels.map(&:title)).to eq(%w[strategic])
    end

    it 'sets a group milestone by title on the epic', :aggregate_failures do
      group_milestone = create(:milestone, group: group, title: 'Q4')

      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, milestone: 'Q4' } }
      )

      expect(result[:isError]).to be(false)
      expect(epic_item.reload.milestone).to eq(group_milestone)
    end

    it 'rejects an unknown name and names the group', :aggregate_failures do
      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, add_labels: %w[nope] } }
      )

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include("Labels not found in #{group.full_path}")
    end
  end
end
