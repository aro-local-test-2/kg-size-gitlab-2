# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServiceDesk::CustomTemplates, feature_category: :service_desk do
  let(:cutoff) { described_class::RESTRICTED_FROM_DATE }

  # The comparison in #enabled? resolves the cutoff to 00:00:00 UTC, because a
  # bare Date coerces through #to_datetime and carries no offset. These are
  # explicit UTC instants rather than Dates so the boundary does not move with
  # Time.zone: writing a Date into a timestamp column casts it through the
  # current zone, which would put Date.new(2026, 9, 10) before the cutoff in a
  # positive-offset zone.
  let(:cutoff_instant) { cutoff.to_datetime.utc }
  let(:after_cutoff) { cutoff_instant + 1.day }
  let(:before_cutoff) { cutoff_instant - 1.day }

  subject(:enabled) { described_class.new(project).enabled? }

  def group_project(plan:, created_at:)
    group = create(:group_with_plan, plan: plan, created_at: created_at)
    create(:project, group: group)
  end

  context 'when on GitLab.com', :saas do
    context 'with a free root namespace created after the cutoff' do
      let(:project) { group_project(plan: :free_plan, created_at: after_cutoff) }

      it { is_expected.to be(false) }

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(service_desk_restrict_custom_templates: false)
        end

        it { is_expected.to be(true) }
      end
    end

    context 'with a root namespace created before the cutoff' do
      let(:project) { group_project(plan: :free_plan, created_at: before_cutoff) }

      it 'grandfathers the namespace' do
        expect(enabled).to be(true)
      end
    end

    context 'with a root namespace created exactly on the cutoff' do
      let(:project) { group_project(plan: :free_plan, created_at: cutoff_instant) }

      it 'restricts the namespace, the cutoff is inclusive' do
        expect(enabled).to be(false)
      end
    end

    context 'with a root namespace created one second before the cutoff' do
      let(:project) { group_project(plan: :free_plan, created_at: cutoff_instant - 1.second) }

      it 'grandfathers the namespace, the boundary is 00:00:00 UTC' do
        expect(enabled).to be(true)
      end
    end

    context 'with paid plans created after the cutoff' do
      where(:plan) { [:premium_plan, :ultimate_plan, :opensource_plan] }

      with_them do
        let(:project) { group_project(plan: plan, created_at: after_cutoff) }

        it { is_expected.to be(true) }
      end
    end

    context 'with trial plans created after the cutoff' do
      where(:plan) { [:premium_trial_plan, :ultimate_trial_plan] }

      with_them do
        let(:project) { group_project(plan: plan, created_at: after_cutoff) }

        it 'restricts trials alongside free' do
          expect(enabled).to be(false)
        end
      end
    end

    # The boundary is paid vs free rather than group vs personal. Personal
    # namespaces resolve to the free plan and cannot hold a subscription on
    # GitLab.com, so they stay restricted with no upgrade path.
    context 'with a personal namespace created after the cutoff' do
      let(:project) do
        create(:project, namespace: create(:user_namespace, created_at: after_cutoff))
      end

      it { is_expected.to be(false) }
    end

    context 'with a personal namespace created before the cutoff' do
      let(:project) do
        create(:project, namespace: create(:user_namespace, created_at: before_cutoff))
      end

      it { is_expected.to be(true) }
    end
  end

  context 'when on GitLab Self-Managed' do
    # No :saas, so plans do not apply and group_with_plan cannot be used.
    let(:project) { create(:project, group: create(:group, created_at: after_cutoff)) }

    it 'never restricts custom templates' do
      expect(enabled).to be(true)
    end
  end
end
