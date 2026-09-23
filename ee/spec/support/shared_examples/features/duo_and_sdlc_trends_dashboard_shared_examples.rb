# frozen_string_literal: true

RSpec.shared_examples 'a rendered Duo and SDLC trends dashboard' do
  let(:dashboard) { ::Analytics::Dashboards::Dashboard.ai_impact_dashboard(container, nil, user) }

  let(:dashboard_title) do
    ::Analytics::Dashboards::Dashboard
      .load_yaml_dashboard_config('dashboard', 'ee/lib/gitlab/analytics/ai_impact_dashboard')['title']
  end

  let(:panel_testids) do
    dashboard.panels.map { |panel| "panel-#{panel.visualization.slug.tr('_', '-')}" }
  end

  it 'lists the dashboard as created by GitLab' do
    visit dashboards_path

    expect(find(dashboard_list_item_testid, text: dashboard.title))
      .to have_selector(dashboard_by_gitlab_testid)
  end

  context 'when the dashboard is opened' do
    before do
      visit dashboards_path
      click_link dashboard.title
    end

    it 'routes by slug and renders a panel per config entry', :aggregate_failures do
      expect(page).to have_current_path(
        "#{dashboards_path}/#{::Analytics::Dashboards::Dashboard::AI_IMPACT_DASHBOARD_NAME}",
        ignore_query: true
      )

      expect(page).to have_content dashboard.title

      expect(panel_testids).not_to be_empty

      panel_testids.each do |testid|
        expect(page).to have_testid(testid)
      end
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'does not offer the dashboard' do
      visit dashboards_path

      expect(page).to have_selector(dashboard_list_item_testid)
      expect(page).to have_no_content dashboard_title
    end
  end

  context 'when the ai_analytics licence is unavailable' do
    before do
      stub_licensed_features(**base_licensed_features, ai_analytics: false)
    end

    it 'does not offer the dashboard' do
      visit dashboards_path

      expect(page).to have_no_content dashboard_title
    end
  end
end
