# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/analytics/dashboards/index',
  :aggregate_failures, feature_category: :value_stream_management do
  let_it_be(:group) { build(:group) }
  let_it_be(:project) { build(:project, :public, group: group) }

  before do
    stub_licensed_features(project_level_analytics_dashboard: true)

    assign(:project, project)
  end

  it 'renders the explore analytics dashboards app' do
    render

    expect(rendered).to have_selector('#js-explore-analytics-dashboards')
    expect(rendered).to have_css("[data-namespace-full-path='#{project.full_path}']")
    expect(rendered).to have_css(
      "[data-explore-analytics-dashboards-path='#{project_analytics_dashboards_path(project)}']")
    expect(view.content_for(:page_specific_styles)).to include('explore_analytics_dashboards')
  end

  context 'when consolidate_analytics_dashboards is disabled' do
    before do
      stub_feature_flags(consolidate_analytics_dashboards: false)
    end

    it 'renders the dashboards list app' do
      render

      expect(rendered).to have_selector('#js-analytics-dashboards-list-app')
      expect(rendered).to have_css("[data-namespace-full-path='#{project.full_path}']")
      expect(view.content_for(:page_specific_styles)).to be_nil
    end
  end
end
