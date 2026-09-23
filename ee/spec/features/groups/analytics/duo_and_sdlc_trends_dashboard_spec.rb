# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group > Analytics dashboards > GitLab Duo and SDLC trends', :js,
  feature_category: :custom_dashboards_foundation do
  include ValueStreamsDashboardHelpers

  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be(:group) { create(:group, name: 'duo trends group', reporters: user) }

  let(:container) { group }
  let(:dashboards_path) { group_analytics_dashboards_path(group) }
  let(:base_licensed_features) { { group_level_analytics_dashboard: true } }

  before do
    # These expectations are written against the legacy dashboards app.
    stub_feature_flags(consolidate_analytics_dashboards: false, explore_analytics_dashboards: false)
    stub_licensed_features(**base_licensed_features, ai_analytics: true)
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    sign_in(user)
  end

  it_behaves_like 'a rendered Duo and SDLC trends dashboard'
end
