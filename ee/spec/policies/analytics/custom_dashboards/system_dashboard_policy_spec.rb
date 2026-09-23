# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::SystemDashboardPolicy, feature_category: :custom_dashboards_foundation do
  include PolicyHelpers

  let(:constraints) { nil }

  let(:system_dashboard) do
    config = { 'title' => 'Test', 'version' => '2', 'panels' => [] }
    config['constraints'] = constraints if constraints

    Analytics::CustomDashboards::SystemDashboard.new(slug: 'gitlab_duo', config: config)
  end

  subject(:policy) { described_class.new(user, system_dashboard) }

  describe 'rules' do
    context 'when user is authenticated' do
      let(:user) { build(:user) }

      it { expect_allowed(:read_system_dashboard) }
    end

    context 'when user is anonymous' do
      let(:user) { nil }

      it { expect_disallowed(:read_system_dashboard) }
    end

    context 'when the dashboard declares a constraint it does not meet' do
      let(:user) { build(:user) }
      let(:constraints) { { 'data' => ['clickhouse'] } }

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it { expect_disallowed(:read_system_dashboard) }
    end

    context 'when the dashboard declares a constraint it meets' do
      let(:user) { build(:user) }
      let(:constraints) { { 'data' => ['clickhouse'] } }

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      end

      it { expect_allowed(:read_system_dashboard) }
    end

    context 'when a feature flag constraint is enabled for one user only' do
      let_it_be(:enabled_user) { create(:user) }
      let_it_be(:other_user) { create(:user) }

      let(:constraints) { { 'feature_flag' => 'dap_impact_v1' } }

      before do
        stub_feature_flags(dap_impact_v1: enabled_user)
      end

      # Deliberately `Ability.allowed?` rather than the expect_allowed helpers: both
      # users have to go through one shared policy cache against one dashboard
      # instance, which is what a `scope: :subject` condition would leak across. The
      # helpers assert on `subject`, so they cannot express two users in one example.
      it 'resolves per user rather than caching on the dashboard', :aggregate_failures do
        expect(Ability.allowed?(enabled_user, :read_system_dashboard, system_dashboard)).to be(true)
        expect(Ability.allowed?(other_user, :read_system_dashboard, system_dashboard)).to be(false)
      end
    end
  end
end
