# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProductAnalyticsHelpers, feature_category: :product_analytics do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }

  describe '#product_analytics_enabled?' do
    subject { project.product_analytics_enabled? }

    where(:instance_enabled, :feature_flag_enabled, :licensed, :toggle, :outcome) do
      false | false | false | false | false
      true  | false | false | false | false
      false | true  | false | false | false
      false | false | true  | false | false
      false | false | false | true  | false
      false | true  | true  | true  | false
      true  | true  | true  | true  | true
    end

    with_them do
      before do
        allow(::Gitlab::CurrentSettings).to receive(:product_analytics_enabled?).and_return(instance_enabled)
        allow(project.group.root_ancestor.namespace_settings).to receive(:experiment_settings_allowed?).and_return(true)
        stub_licensed_features(product_analytics: licensed)
        stub_feature_flags(product_analytics_features: feature_flag_enabled)
      end

      it { is_expected.to eq(outcome) }
    end
  end

  describe '#ai_impact_dashboard_available_for?' do
    subject { group.ai_impact_dashboard_available_for?(user) }

    where(:enabled, :outcome) do
      false | false
      true | true
    end

    with_them do
      before do
        allow(Ability).to receive(:allowed?)
                      .with(user, :read_enterprise_ai_analytics, anything)
                      .and_return(true)
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(enabled)
      end

      it { is_expected.to eq(outcome) }
    end
  end

  describe '#merge_request_analytics_enabled?' do
    subject { project.merge_request_analytics_enabled?(user) }

    where(:enabled, :outcome) do
      false | false
      true  | true
    end

    with_them do
      before do
        allow(Ability).to receive(:allowed?)
                      .with(user, :read_project_merge_request_analytics, anything)
                      .and_return(enabled)
      end

      it { is_expected.to eq(outcome) }
    end
  end

  describe '#product_analytics_dashboards' do
    context 'with configuration project' do
      let_it_be(:config_project) { create(:project, :with_product_analytics_dashboard, group: group) }

      before do
        stub_licensed_features(product_analytics: true)
        stub_feature_flags(product_analytics_features: true)
        project.update!(analytics_dashboards_configuration_project: config_project)
      end

      it 'includes configuration project dashboards' do
        expect(project.product_analytics_dashboards(user)).not_to be_empty
      end
    end

    describe '#contributions_dashboard_available?' do
      subject { entity.contributions_dashboard_available? }

      context 'when entity is a group' do
        let(:entity) { group }

        it { is_expected.to be_truthy }

        context 'when contributions_analytics_dashboard feature is disabled' do
          before do
            stub_feature_flags(contributions_analytics_dashboard: false)
          end

          it { is_expected.to be_falsey }
        end
      end

      context 'when entity is not a group' do
        let(:entity) { project }

        before do
          stub_feature_flags(contributions_analytics_dashboard: true)
        end

        it { is_expected.to be_falsey }
      end
    end
  end

  describe '#product_analytics_dashboard' do
    context 'when product analytics is disabled' do
      before do
        stub_licensed_features(product_analytics: false)
      end

      it 'returns nil' do
        expect(project.product_analytics_dashboard('test', user)).to be_nil
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_licensed_features(product_analytics: true)
        stub_feature_flags(product_analytics_features: false)
      end

      it 'returns nil' do
        expect(project.product_analytics_dashboard('test', user)).to be_nil
      end
    end

    context 'when product analytics is available' do
      before do
        stub_licensed_features(product_analytics: true)
        stub_feature_flags(product_analytics_features: true)
      end

      context 'when the project has defined a configuration project' do
        let_it_be(:configuration_project) { create(:project, :with_product_analytics_dashboard, group: group) }

        before do
          project.update!(analytics_dashboards_configuration_project: configuration_project)
        end

        context 'when the requested dashboard exists' do
          let(:slug) { 'dashboard_example_1' }

          it 'returns the dashboard with the given slug' do
            expect(project.product_analytics_dashboard(slug, user).container).to eq(project)
            expect(project.product_analytics_dashboard(slug, user).config_project).to eq(configuration_project)
          end
        end

        context 'when the requested dashboard does not exist' do
          let(:slug) { 'Dashboard Example 1800' }

          it 'returns nil' do
            expect(project.product_analytics_dashboard(slug, user)).to be_nil
          end
        end
      end
    end
  end
end
