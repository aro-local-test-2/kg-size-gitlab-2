# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::DashboardsLoaderService, feature_category: :custom_dashboards_foundation do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:org_user) { create(:organization_user, organization: organization, user: user) }
  let_it_be(:db_dashboard) do
    create(:dashboard, organization: organization, namespace: nil, name: 'Sales Dashboard')
  end

  let(:params) { {} }
  let(:system_dashboard) do
    Analytics::CustomDashboards::SystemDashboard.new(
      slug: 'duo_and_sdlc_trends',
      config: { 'title' => 'GitLab Duo and SDLC trends' }
    )
  end

  before do
    allow(Analytics::CustomDashboards::SystemDashboardsLoader).to receive(:all).and_return([system_dashboard])
  end

  describe '#execute' do
    subject(:result) do
      described_class.new(user, organization: organization, params: params).execute
    end

    it { is_expected.to include(db_dashboard, system_dashboard) }

    it 'returns system dashboards before db dashboards' do
      expect(result.first).to eq(system_dashboard)
      expect(result.last).to eq(db_dashboard)
    end

    context 'when a system dashboard declares a constraint' do
      let(:system_dashboard) do
        Analytics::CustomDashboards::SystemDashboard.new(
          slug: 'duo_and_sdlc_trends',
          config: {
            'title' => 'GitLab Duo and SDLC trends',
            'constraints' => { 'data' => ['clickhouse'] }
          }
        )
      end

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(clickhouse_enabled)
      end

      context 'when the constraint is met' do
        let(:clickhouse_enabled) { true }

        it { is_expected.to include(system_dashboard) }
      end

      context 'when the constraint is not met' do
        let(:clickhouse_enabled) { false }

        it 'leaves the dashboard out' do
          expect(result).to contain_exactly(db_dashboard)
        end
      end
    end

    context 'when user is not an organization member' do
      let(:non_member) { create(:user) }
      let(:user) { non_member }

      it { is_expected.to be_empty }
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(custom_dashboard_storage: false)
      end

      it 'returns only built-in dashboards' do
        expect(result).to contain_exactly(system_dashboard)
      end

      context 'with gitlab scope filter' do
        let(:params) { { scope: :gitlab } }

        it { is_expected.to contain_exactly(system_dashboard) }
      end

      context 'with user scope filter' do
        let(:params) { { scope: :user } }

        it { is_expected.to be_empty }
      end

      context 'when user is not an organization member' do
        let(:user) { create(:user) }

        it { is_expected.to be_empty }
      end
    end

    context 'with search filter' do
      let(:params) { { search: search_term } }

      context 'when search matches db dashboard only' do
        let(:search_term) { 'Sales' }

        it { is_expected.to include(db_dashboard) }

        it { is_expected.not_to include(system_dashboard) }
      end

      context 'when search matches system dashboard only' do
        let(:search_term) { 'GitLab' }

        it { is_expected.to include(system_dashboard) }

        it { is_expected.not_to include(db_dashboard) }
      end

      context 'when search matches both' do
        let(:search_term) { 'Dashboard' }

        let(:system_dashboard) do
          Analytics::CustomDashboards::SystemDashboard.new(
            slug: 'sales_dashboard',
            config: { 'title' => 'Sales Dashboard' }
          )
        end

        it { is_expected.to include(db_dashboard, system_dashboard) }
      end

      context 'when search matches nothing' do
        let(:search_term) { 'Nonexistent' }

        it { is_expected.to be_empty }
      end

      context 'when search is case insensitive for system dashboards' do
        let(:search_term) { 'gitlab' }

        it { is_expected.to include(system_dashboard) }
      end
    end

    context 'when there are no system dashboards' do
      before do
        allow(Analytics::CustomDashboards::SystemDashboardsLoader).to receive(:all).and_return([])
      end

      it { is_expected.to contain_exactly(db_dashboard) }
    end

    context 'when there are no db dashboards' do
      let(:organization) { create(:organization) }

      before do
        Organizations::OrganizationUser.find_or_create_by!(organization: organization, user: user)
      end

      it { is_expected.to contain_exactly(system_dashboard) }
    end

    context 'when organization has more than MAX_DB_DASHBOARDS dashboards' do
      before do
        stub_const('Analytics::CustomDashboards::DashboardsLoaderService::MAX_DB_DASHBOARDS', 2)
        create_list(:dashboard, 3, organization: organization, namespace: nil)
      end

      it 'limits db dashboards to MAX_DB_DASHBOARDS' do
        db_results = result.select { |d| d.is_a?(Analytics::CustomDashboards::Dashboard) }
        expect(db_results.size).to eq(2)
      end
    end

    context 'with gitlab scope filter' do
      let(:params) { { scope: :gitlab } }

      it { is_expected.to contain_exactly(system_dashboard) }

      it { is_expected.not_to include(db_dashboard) }

      context 'with search filter matching system dashboard' do
        let(:params) { { scope: :gitlab, search: 'GitLab' } }

        it { is_expected.to include(system_dashboard) }

        it { is_expected.not_to include(db_dashboard) }
      end

      context 'when search does not match any system dashboard' do
        let(:params) { { scope: :gitlab, search: 'Nonexistent' } }

        it { is_expected.to be_empty }
      end
    end

    context 'with user scope filter' do
      let(:params) { { scope: :user } }

      it { is_expected.to include(db_dashboard) }

      it { is_expected.not_to include(system_dashboard) }
    end
  end
end
