# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Issue Sidebar', :js, :saas, feature_category: :team_planning do
  include MobileHelpers

  let_it_be(:group) { create(:group_with_plan, :public, plan: :premium_plan) }
  let_it_be(:project) { create(:project, :public, namespace: group) }
  let_it_be(:project_without_group) { create(:project, :public) }
  let_it_be(:user) { create(:user) }
  let_it_be(:label) { create(:label, project: project, title: 'bug') }
  let_it_be(:issue) { create(:labeled_issue, project: project, labels: [label]) }
  let_it_be(:issue_no_group) { create(:labeled_issue, project: project_without_group, labels: [label]) }

  before do
    sign_in(user)
  end

  context 'for accessibility' do
    it 'passes axe automated accessibility testing' do
      project.add_developer(user)

      visit_issue(project, issue)
      expect(page).to have_selector('section.work-item-overview-right-sidebar')

      expect(page).to be_axe_clean.within('section.work-item-overview-right-sidebar')
    end
  end

  # Changing and clearing the health status, and losing the edit button once the issue is
  # closed, are covered by
  # ee/spec/frontend/integration/work_items/details/health_status_spec.js. The context
  # below stays here because it turns on whether the licence exposes the widget at all,
  # which MSW mocks away.
  describe 'health status' do
    before do
      project.add_developer(user)
    end

    context 'when health status feature is not available' do
      it 'does not show health status on sidebar' do
        stub_licensed_features(issuable_health_status: false)
        visit_issue(project, issue)

        expect(page).not_to have_css('[data-testid="work-item-health-status"]')
      end
    end
  end

  # Selecting, clearing and searching iterations is covered by
  # ee/spec/frontend/integration/work_items/details/iteration_spec.js. The contexts
  # below stay here because they turn on whether the licence and namespace expose the
  # widget at all, which MSW mocks away.
  describe 'iterations' do
    context 'when a project does not have a group' do
      before do
        stub_licensed_features(iterations: true)

        project_without_group.add_developer(user)

        visit_issue(project_without_group, issue_no_group)
        find('section.work-item-overview-right-sidebar')
      end

      it 'cannot find the select-iteration edit button' do
        expect(page).not_to have_css('[data-testid="work-item-iteration"]')
      end
    end

    context 'when iteration feature is not available' do
      before do
        stub_licensed_features(iterations: false)

        project.add_developer(user)

        visit_issue(project, issue)
        find('section.work-item-overview-right-sidebar')
      end

      it 'cannot find the select-iteration edit button' do
        expect(page).not_to have_css('[data-testid="work-item-iteration"]')
      end
    end
  end

  context 'with escalation policy' do
    it 'is not available for default issue type' do
      expect(page).not_to have_selector('.block.escalation-policy')
    end
  end

  def visit_issue(project, issue)
    visit project_issue_path(project, issue)
  end
end
