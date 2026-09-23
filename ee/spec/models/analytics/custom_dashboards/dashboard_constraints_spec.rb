# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::DashboardConstraints, feature_category: :custom_dashboards_foundation do
  describe '.satisfied?' do
    subject(:satisfied) { described_class.satisfied?(dashboard, user) }

    let_it_be(:user) { create(:user) }

    let(:dashboard) do
      Analytics::CustomDashboards::SystemDashboard.new(slug: 'test', config: config)
    end

    context 'when the dashboard declares no constraints' do
      let(:config) { { 'title' => 'Test' } }

      it { is_expected.to be(true) }
    end

    describe 'data' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'data' => ['clickhouse'] } } }

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(enabled)
      end

      context 'when ClickHouse is enabled for analytics' do
        let(:enabled) { true }

        it { is_expected.to be(true) }
      end

      context 'when ClickHouse is not enabled for analytics' do
        let(:enabled) { false }

        it { is_expected.to be(false) }
      end

      context 'when the dashboard declares an unknown data source' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'data' => ['nope'] } } }
        let(:enabled) { true }

        it 'raises so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(KeyError)
        end
      end
    end

    describe 'license' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'license' => 'product_analytics' } } }

      context 'when the licence includes the feature' do
        before do
          stub_licensed_features(product_analytics: true)
        end

        it { is_expected.to be(true) }
      end

      context 'when the licence does not include the feature' do
        before do
          stub_licensed_features(product_analytics: false)
        end

        it { is_expected.to be(false) }
      end
    end

    describe 'feature_flag' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'feature_flag' => 'dap_impact_v1' } } }

      context 'when the flag is enabled for the user' do
        before do
          stub_feature_flags(dap_impact_v1: user)
        end

        it { is_expected.to be(true) }
      end

      context 'when the flag is disabled' do
        before do
          stub_feature_flags(dap_impact_v1: false)
        end

        it { is_expected.to be(false) }
      end

      context 'when the dashboard declares an unknown feature token' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'feature_flag' => 'nope' } } }

        it 'raises so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(KeyError)
        end
      end

      # The flag is user-actored, so two users can get different answers for the
      # same dashboard. This is what stops the policy condition being subject-scoped.
      context 'when the flag is enabled for another user only' do
        let_it_be(:other_user) { create(:user) }

        before do
          stub_feature_flags(dap_impact_v1: other_user)
        end

        it { is_expected.to be(false) }

        it 'is satisfied for the enabled user' do
          expect(described_class.satisfied?(dashboard, other_user)).to be(true)
        end
      end
    end

    describe 'several kinds at once' do
      let(:config) do
        {
          'title' => 'Test',
          'constraints' => { 'license' => 'product_analytics', 'data' => ['clickhouse'] }
        }
      end

      before do
        stub_licensed_features(product_analytics: true)
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(clickhouse)
      end

      context 'when every kind is satisfied' do
        let(:clickhouse) { true }

        it { is_expected.to be(true) }
      end

      context 'when one kind is not satisfied' do
        let(:clickhouse) { false }

        it { is_expected.to be(false) }
      end
    end
  end

  # The schema decides what a dashboard may declare, these hashes decide what each
  # token does. A token in one but not the other validates, loads, and then raises
  # KeyError mid-request, which takes out the whole dashboard list rather than one
  # dashboard.
  describe 'agreement with the JSON schema' do
    let(:schema_constraints) do
      schema = ::Gitlab::Json::SafeParser.parse(
        File.read(Rails.root.join(Analytics::CustomDashboards::SystemDashboardsLoader::SCHEMA_PATH))
      )

      schema.dig('definitions', 'AnalyticsDashboard', 'properties', 'constraints', 'properties')
    end

    it 'has a predicate for every data source the schema allows' do
      expect(described_class::DATA_CHECKS.keys).to match_array(schema_constraints.dig('data', 'items', 'enum'))
    end

    it 'has a predicate for every feature flag the schema allows' do
      expect(described_class::FEATURE_FLAG_CHECKS.keys).to match_array(schema_constraints.dig('feature_flag', 'enum'))
    end

    it 'only allows licence names that are real licensed features' do
      names = schema_constraints.dig('license', 'enum').map(&:to_sym)

      expect(::GitlabSubscriptions::Features::ALL_FEATURES).to include(*names)
    end
  end
end
