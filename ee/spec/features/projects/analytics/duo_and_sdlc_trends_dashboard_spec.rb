# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project > Analytics dashboards > GitLab Duo and SDLC trends', :js,
  feature_category: :custom_dashboards_foundation do
  include ValueStreamsDashboardHelpers

  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be(:group) { create(:group, name: 'duo trends group') }
  let_it_be(:project) do
    create(:project, name: 'duo trends project', namespace: group, reporters: user)
  end

  let(:container) { project }
  let(:dashboards_path) { project_analytics_dashboards_path(project) }
  let(:base_licensed_features) { { project_level_analytics_dashboard: true } }

  before do
    # These expectations are written against the legacy dashboards app.
    stub_feature_flags(consolidate_analytics_dashboards: false, explore_analytics_dashboards: false)
    stub_licensed_features(**base_licensed_features, ai_analytics: true)
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    sign_in(user)
  end

  it_behaves_like 'a rendered Duo and SDLC trends dashboard'
end
