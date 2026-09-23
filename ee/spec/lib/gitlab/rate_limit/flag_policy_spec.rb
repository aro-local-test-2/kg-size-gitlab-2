# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RateLimit::FlagPolicy, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  describe 'the plan flags' do
    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      where(:plan, :info_flag, :enforce_flag) do
        'free'     | :rate_limiter_plan_limits_free_info     | :rate_limiter_plan_limits_free_enforce
        'premium'  | :rate_limiter_plan_limits_premium_info  | :rate_limiter_plan_limits_premium_enforce
        'ultimate' | :rate_limiter_plan_limits_ultimate_info | :rate_limiter_plan_limits_ultimate_enforce
      end

      with_them do
        it 'reads the tier flags with the request actor and the derisk type', :aggregate_failures do
          allow(::Feature).to receive(:enabled?).and_return(true)

          described_class.plan_flags

          expect(::Feature).to have_received(:enabled?)
            .with(info_flag, ::Feature.current_request, type: :gitlab_com_derisk)
          expect(::Feature).to have_received(:enabled?)
            .with(enforce_flag, ::Feature.current_request, type: :gitlab_com_derisk)
        end

        # Uncoupled on purpose: a rule that wants info-gates-enforce says so in
        # its own match, so nothing here folds the two together.
        it 'reports each flag independently', :aggregate_failures do
          stub_feature_flags(info_flag => false, enforce_flag => true)

          flags = described_class.plan_flags

          expect(flags[:"plan_limits_#{plan}_info"]).to be(false)
          expect(flags[:"plan_limits_#{plan}_enforce"]).to be(true)
        end
      end

      it 'is false for an unknown or missing plan without reading a flag' do
        expect(::Feature).not_to receive(:enabled?)

        expect(described_class.plan_info_enabled?(nil)).to be(false)
      end

      # The enforce side of the same defence. A tier Plan ranks before this file
      # has a flag for it reports false rather than raising.
      it 'is false for a tier with no enforce flag yet' do
        stub_const('Plan::TIERS', %w[free premium ultimate bronze])

        expect(described_class.plan_flags[:plan_limits_bronze_enforce]).to be(false)
      end

      # Fails if a tier is added to Plan::TIERS with no branch here.
      it 'reads an info flag for every tier Plan ranks' do
        allow(::Feature).to receive(:enabled?).and_return(false)

        ::Plan::TIERS.each { |tier| described_class.plan_info_enabled?(tier) }

        expect(::Feature).to have_received(:enabled?).exactly(::Plan::TIERS.size).times
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(rate_limiter_plan_limits_free_info: true, rate_limiter_plan_limits_free_enforce: true)
      end

      it 'is false with the flags on, without reading one', :aggregate_failures do
        expect(::Feature).not_to receive(:enabled?)

        expect(described_class.plan_info_enabled?('free')).to be(false)
        expect(described_class.plan_flags.values).to all(be(false))
      end
    end
  end

  describe 'the unauthenticated flags' do
    # Row 3: enforce alone does nothing, so info is the single off switch.
    where(:info, :enforce, :info_enabled, :enforce_enabled) do
      false | false | false | false
      true  | false | true  | false
      false | true  | false | false
      true  | true  | true  | true
    end

    with_them do
      it 'follows the flag state table on GitLab.com', :aggregate_failures do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(
          rate_limiter_unauthenticated_limits_info: info,
          rate_limiter_unauthenticated_limits_enforce: enforce
        )

        expect(described_class.unauthenticated_info_enabled?).to be(info_enabled)
        expect(described_class.unauthenticated_enforce_enabled?).to be(enforce_enabled)
      end
    end

    it 'is false off GitLab.com with both flags on', :aggregate_failures do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(
        rate_limiter_unauthenticated_limits_info: true,
        rate_limiter_unauthenticated_limits_enforce: true
      )

      expect(described_class.unauthenticated_info_enabled?).to be(false)
      expect(described_class.unauthenticated_enforce_enabled?).to be(false)
    end
  end

  # Its own flag rather than the throttle flags, so the facts can be switched on
  # and watched before any throttle moves.
  describe '.plan_facts_enabled?' do
    it 'is true on GitLab.com' do
      stub_saas_features(gitlab_com_subscriptions: true)

      expect(described_class.plan_facts_enabled?).to be(true)
    end

    it 'is false when the flag is off' do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(ratelimiting_include_plan_info: false)

      expect(described_class.plan_facts_enabled?).to be(false)
    end

    it 'is false off GitLab.com' do
      stub_saas_features(gitlab_com_subscriptions: false)

      expect(described_class.plan_facts_enabled?).to be(false)
    end

    it 'reads no flag off GitLab.com' do
      stub_saas_features(gitlab_com_subscriptions: false)

      expect(::Feature).not_to receive(:enabled?)

      described_class.plan_facts_enabled?
    end

    it 'reads the flag with the request actor and the derisk type' do
      stub_saas_features(gitlab_com_subscriptions: true)
      allow(::Feature).to receive(:enabled?).and_return(true)

      described_class.plan_facts_enabled?

      expect(::Feature).to have_received(:enabled?)
        .with(:ratelimiting_include_plan_info, ::Feature.current_request, type: :gitlab_com_derisk)
    end

    it 'is independent of the throttle flags' do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(described_class::FLAGS.index_with(false))

      expect(described_class.plan_facts_enabled?).to be(true)
    end
  end
end
