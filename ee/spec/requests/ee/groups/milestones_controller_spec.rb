# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::MilestonesController, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:public_group) { create(:group, :public) }

  let!(:public_project_with_private_issues_and_mrs) do
    create(:project, :public, :issues_private, :merge_requests_private, group: public_group)
  end

  describe 'GET #index' do
    let_it_be(:group) { create(:group, :private) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:group_milestone) { create(:milestone, group: group, title: 'group-only') }
    let_it_be(:project_milestone) { create(:milestone, project: project, title: 'project-one') }

    before_all do
      group.add_developer(user)
    end

    before do
      sign_in(user)
    end

    it 'includes project milestones by default' do
      get group_milestones_path(group, format: :json)

      expect(json_response.pluck('title')).to include('group-only', 'project-one')
    end

    it 'excludes project milestones when only_group_milestones is set' do
      get group_milestones_path(group, format: :json), params: { only_group_milestones: true }

      titles = json_response.pluck('title')
      expect(titles).to include('group-only')
      expect(titles).not_to include('project-one')
    end
  end

  describe 'GET #issues' do
    let(:milestone) { create(:milestone, group: public_group) }
    let!(:lifecycle) { create(:work_item_custom_lifecycle, namespace: public_group) }
    let!(:additional_status) { create(:work_item_custom_status, namespace: public_group) }
    let!(:additional_status_connection) do
      create(:work_item_custom_lifecycle_status, lifecycle: lifecycle, status: additional_status)
    end

    let!(:work_item) do
      create(:work_item, milestone: milestone, project: public_project_with_private_issues_and_mrs,
        custom_status_id: lifecycle.default_open_status.id)
    end

    def perform_request
      get issues_group_milestone_path(public_group, milestone, format: :json)
    end

    it 'avoids N+1 queries when loading work item statuses' do
      perform_request # warm up

      control_count = ActiveRecord::QueryRecorder.new { perform_request }

      create(:work_item, milestone: milestone, project: public_project_with_private_issues_and_mrs,
        custom_status_id: additional_status.id)

      expect { perform_request }.not_to exceed_query_limit(control_count)
    end
  end
end
