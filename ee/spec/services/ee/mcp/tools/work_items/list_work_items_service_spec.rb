# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::ListWorkItemsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:project) { create(:project, :public, group: group) }

  let(:service) { described_class.new(name: 'list_work_items') }
  let(:request) { instance_double(ActionDispatch::Request) }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe 'input schema' do
    it 'adds the EE-only filter properties on top of the CE contract' do
      schema = service.input_schema

      expect(schema[:properties]).to include(
        health_status_filter: {
          type: 'string',
          enum: %w[onTrack needsAttention atRisk],
          description: 'Filter by health status.'
        },
        status: {
          type: 'object',
          properties: {
            name: {
              type: 'string',
              description: 'Status name, for example "In progress".'
            }
          },
          required: %w[name],
          additionalProperties: false,
          description: 'Filter by custom status.'
        }
      )
      expect(schema[:properties]).to include(:state, :sort, :first, :after)
    end
  end

  describe '#execute with EE filters' do
    before do
      stub_licensed_features(issuable_health_status: true)
    end

    let_it_be(:on_track_work_item) do
      create(:work_item, project: project, title: 'On track issue', health_status: :on_track)
    end

    let_it_be(:at_risk_work_item) do
      create(:work_item, project: project, title: 'At risk issue', health_status: :at_risk)
    end

    let(:params) { { arguments: { project_id: project.id.to_s, health_status_filter: 'onTrack' } } }

    it 'filters by health status while keeping rows compact', :aggregate_failures do
      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)

      rows = result[:structuredContent]['work_items']
      expect(rows.pluck('title')).to contain_exactly('On track issue')
      expect(rows.first.keys).to match_array(%w[id iid title state webUrl reference createdAt updatedAt workItemType])
    end

    context 'with the status filter' do
      before do
        stub_licensed_features(issuable_health_status: true, work_item_status: true)
      end

      let_it_be(:in_progress_work_item) do
        create(:work_item, project: project, title: 'In progress issue').tap do |work_item|
          create(:work_item_current_status, work_item: work_item, system_defined_status_id: 2)
        end
      end

      let(:params) { { arguments: { project_id: project.id.to_s, status: { name: 'In progress' } } } }

      it 'filters by status name' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['work_items'].pluck('title')).to contain_exactly('In progress issue')
      end
    end
  end
end
