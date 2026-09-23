# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::GitlabCom::StatusWidgetPresenter, :saas, feature_category: :acquisition do
  include Rails.application.routes.url_helpers

  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }
  let(:trial_duration) { 60 }
  let(:gitlab_subscription) { build_stubbed(:gitlab_subscription) }

  let(:presenter) { described_class.new(group, user: user) }

  before do
    allow(group).to receive(:gitlab_subscription).and_return(gitlab_subscription)
  end

  describe '#eligible_for_widget?' do
    subject(:eligible_for_widget) { presenter.eligible_for_widget? }

    it { is_expected.to be(false) }

    context 'when a pending trial marker is active', :use_clean_rails_memory_store_caching, :with_trial_types do
      before do
        GitlabSubscriptions::Trials::PendingTrialMarker.set(group.id)
      end

      it { is_expected.to be(true) }

      context 'when the namespace already has a real active trial', :freeze_time do
        let(:gitlab_subscription) do
          build_stubbed(:gitlab_subscription, :ultimate_trial, :active_trial, namespace: group,
            start_date: Date.current, end_date: trial_duration.days.from_now)
        end

        it { is_expected.to be(true) }

        it 'uses the real trial data instead of the optimistic marker data' do
          days_remaining = presenter.attributes[:trial_widget_data_attrs][:days_remaining]

          expect(days_remaining).to eq(trial_duration)
        end
      end
    end

    context 'when trial is active' do
      let(:gitlab_subscription) do
        build_stubbed(:gitlab_subscription, :ultimate_trial, :active_trial, namespace: group,
          end_date: trial_duration.days.from_now)
      end

      it { is_expected.to be(true) }
    end

    context 'when trial is active and group is paid' do
      let(:gitlab_subscription) do
        build_stubbed(:gitlab_subscription, :ultimate_trial_paid_customer, namespace: group,
          end_date: trial_duration.days.from_now)
      end

      it { is_expected.to be(true) }
    end

    context 'when trial ended' do
      context 'with unpaid group' do
        let(:gitlab_subscription) { build_stubbed(:gitlab_subscription, :free, :expired_trial, namespace: group) }

        it { is_expected.to be(true) }

        context 'when widget is dismissed' do
          let(:user) do
            build_stubbed(:user, group_callouts: [
              build_stubbed(:group_callout, group: group, feature_name: described_class::EXPIRED_TRIAL_WIDGET)
            ])
          end

          it { is_expected.to be(false) }
        end

        context 'when trial ended more than 10 days ago' do
          let(:gitlab_subscription) do
            build_stubbed(:gitlab_subscription, :free, :expired_trial, namespace: group, trial_ends_on: 11.days.ago)
          end

          it { is_expected.to be(false) }
        end
      end

      context 'with paid group' do
        let(:gitlab_subscription) { build_stubbed(:gitlab_subscription, :premium, namespace: group) }

        it { is_expected.to be(false) }
      end
    end
  end

  describe '#attributes' do
    subject(:attributes) { presenter.attributes }

    let(:trial_widget_data_attrs) do
      {
        trial_widget_data_attrs: {
          trial_type: trial_type,
          trial_days_used: 1,
          days_remaining: trial_duration,
          percentage_complete: 1.67,
          group_id: group.id,
          trial_discover_page_path: group_discover_path(group),
          purchase_now_url: group_billings_path(group),
          feature_id: described_class::EXPIRED_TRIAL_WIDGET
        }
      }
    end

    let(:gitlab_subscription) do
      build_stubbed(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group,
        start_date: Date.current, end_date: trial_duration.days.from_now,
        trial_starts_on: Date.current)
    end

    let(:trial_type) { 'ultimate_with_dap' }

    it 'returns ultimate_with_dap type for bundled trials' do
      expect(attributes).to eq(trial_widget_data_attrs)
    end

    context 'when pending trial marker is active and no real trial',
      :use_clean_rails_memory_store_caching, :with_trial_types, :freeze_time do
      it 'returns trial widget data with dates derived from TrialDurationService', :aggregate_failures do
        allow(group).to receive(:gitlab_subscription).and_return(build_stubbed(:gitlab_subscription))
        GitlabSubscriptions::Trials::PendingTrialMarker.set(group.id)
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            message: 'Optimistic trial widget served from pending trial marker',
            namespace_id: group.id
          )
        )

        result = attributes[:trial_widget_data_attrs]

        expect(result[:trial_type]).to eq('ultimate_with_dap')
        expect(result[:trial_days_used]).to eq(1)
        expect(result[:days_remaining]).to eq(30)
        expect(result[:group_id]).to eq(group.id)
      end
    end
  end
end
