# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project > Settings > Access tokens upgrade card', :js, :saas, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  before_all do
    group.add_owner(user)
  end

  before do
    stub_ee_application_setting(should_check_namespace_plan: true)
    allow_next_instance_of(::GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
      allow(service).to receive(:execute).and_return([])
    end
    sign_in(user)
  end

  it 'shows the upgrade card with tracked CTAs instead of the read-only subheader' do
    visit project_settings_access_tokens_path(project)

    expect(page).to have_content(s_('AccessTokens|Try project access tokens with Premium'))
    expect(page).to have_css("[data-testid='project-access-token-upgrade-card']")
    expect(page).to have_link(s_('AccessTokens|Upgrade to Premium'))
    expect(page).to have_link(s_('AccessTokens|Explore plans'))
    expect(page).to have_content(s_('AccessTokens|You can still manage existing tokens.'))
    expect(page).to have_css("a[data-event-tracking='click_upgrade_to_premium_on_project_access_tokens']")
    expect(page).to have_css("a[data-event-tracking='click_explore_plans_on_project_access_tokens']")
    expect(page).not_to have_content(_('Project access token creation is disabled in this group.'))
  end

  context 'when the instance is not GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it 'shows the existing read-only subheader' do
      visit project_settings_access_tokens_path(project)

      expect(page).to have_content(_('Project access token creation is disabled in this group.'))
      expect(page).not_to have_content(s_('AccessTokens|Try project access tokens with Premium'))
    end
  end
end
