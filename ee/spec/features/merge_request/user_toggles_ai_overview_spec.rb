# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request AI overview', :js, feature_category: :code_review_workflow do
  let(:user) { create(:user, :with_namespace) }
  let(:group) { create(:group) }
  let(:project) { create(:project, :repository, group: group) }
  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  before do
    project.add_maintainer(user)
    sign_in(user)
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(mr_ai_overview: false)
    end

    it 'offers no toggle' do
      visit project_merge_request_path(project, merge_request)

      click_button 'Merge request actions'

      expect(page).not_to have_button 'Try the new overview'
    end
  end

  context 'when the feature flag is enabled for the current user' do
    before do
      stub_feature_flags(mr_ai_overview: user)
    end

    it 'opts in from the overflow menu and replaces the Overview tab' do
      visit project_merge_request_path(project, merge_request)

      expect(page).to have_selector('.merge-request-overview')

      click_button 'Merge request actions'
      click_button 'Try the new overview'

      expect(page).to have_selector('.ai-overview-body')
      expect(page).not_to have_selector('.merge-request-overview')
    end

    context 'when the user has opted in' do
      before do
        set_cookie('mr_ai_overview_enabled', 'true')
      end

      it 'renders the merge readiness rows' do
        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="readiness-row"]', count: 4)
      end

      it 'gives a merge check without a row of its own a row while it blocks' do
        merge_request.update!(title: "Draft: #{merge_request.title}")

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="readiness-row"]', count: 5)
        expect(page).to have_content('Merge request must not be draft.')
      end

      it 'says a merged merge request is merged, rather than scoring it for readiness' do
        merge_request.mark_as_merged!

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_content('This merge request has been merged.')
        expect(page).not_to have_selector('[data-testid="readiness-row"]')
      end

      it 'leaves the other tabs working' do
        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('.ai-overview-body')

        click_link 'Changes'

        expect(page).to have_selector('diff-file')
      end

      it 'still boots the sidebar bundle, which owns controls outside the sidebar' do
        visit project_merge_request_path(project, merge_request)

        click_button 'Merge request actions'

        # The unmounted placeholder reads "Lock merge request"; the mounted form reads "Lock discussion".
        expect(page).to have_button 'Lock discussion'
      end

      it 'mounts once when arriving on another tab and switching back' do
        visit commits_project_merge_request_path(project, merge_request)

        within('.merge-request-tabs') { click_link 'Overview' }

        expect(page).to have_selector('.ai-overview-body', count: 1)
      end

      it 'opts back out from the overflow menu' do
        visit project_merge_request_path(project, merge_request)

        click_button 'Merge request actions'
        click_button 'Switch to the classic overview'

        expect(page).to have_selector('.merge-request-overview')
        expect(page).not_to have_selector('.ai-overview-body')
      end
    end
  end
end
