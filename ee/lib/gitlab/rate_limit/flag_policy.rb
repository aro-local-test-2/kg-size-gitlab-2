# frozen_string_literal: true

module Gitlab
  module RateLimit
    # The one place a rate-limit flag is read, so the GitLab.com guard and the
    # info-gates-enforce rule cannot be forgotten at a call site.
    module FlagPolicy
      # The names, for callers that need to enumerate rather than read them:
      # spec/support/rate_limiter_labkit_rack_shadow.rb stubs them all off.
      FLAGS = [
        :rate_limiter_plan_limits_free_info,
        :rate_limiter_plan_limits_free_enforce,
        :rate_limiter_plan_limits_premium_info,
        :rate_limiter_plan_limits_premium_enforce,
        :rate_limiter_plan_limits_ultimate_info,
        :rate_limiter_plan_limits_ultimate_enforce,
        :rate_limiter_unauthenticated_limits_info,
        :rate_limiter_unauthenticated_limits_enforce
      ].freeze

      class << self
        def gitlab_com?
          ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
        end

        # Its own flag, so the plan facts can be switched on and watched before any
        # throttle flag moves. Short lived: remove it once the facts are enabled.
        def plan_facts_enabled?
          gitlab_com? &&
            ::Feature.enabled?(:ratelimiting_include_plan_info, actor, type: :gitlab_com_derisk)
        end

        # One fact per flag, uncoupled, so a rule states its own gate rather than
        # reading a boolean this file already combined. The info-gates-enforce rule
        # lives in each rule's match now, which is why nothing here folds the two
        # together.
        #
        # Always the full set, so the facts a rule matches on are present whatever
        # the flags say. Reads are cheap after the first: Feature memoizes Flipper
        # into SafeRequestStore.
        def plan_flags
          ::Plan::TIERS.each_with_object({}) do |plan, facts|
            facts[:"plan_limits_#{plan}_info"] = plan_info_enabled?(plan)
            facts[:"plan_limits_#{plan}_enforce"] = gitlab_com? && enforce_flag_on?(plan)
          end
        end

        # The cheap gate PlanRules.active? asks for. An enforce flag counts on its
        # own here, unlike the info-gated predicates below.
        def any_flag_enabled?
          return false unless gitlab_com?

          ::Plan::TIERS.any? { |plan| info_flag_on?(plan) || enforce_flag_on?(plan) } ||
            unauthenticated_info_flag_on? || unauthenticated_enforce_flag_on?
        end

        def plan_info_enabled?(plan)
          gitlab_com? && info_flag_on?(plan)
        end

        def unauthenticated_info_enabled?
          gitlab_com? && unauthenticated_info_flag_on?
        end

        def unauthenticated_enforce_enabled?
          unauthenticated_info_enabled? && unauthenticated_enforce_flag_on?
        end

        private

        def actor
          ::Feature.current_request
        end

        # Literal flag names rather than "rate_limiter_plan_limits_#{plan}_info", so
        # every read is a static key (Gitlab/FeatureFlagKeyDynamic).
        def info_flag_on?(plan)
          case plan
          when ::Plan::FREE
            ::Feature.enabled?(:rate_limiter_plan_limits_free_info, actor, type: :gitlab_com_derisk)
          when ::Plan::PREMIUM
            ::Feature.enabled?(:rate_limiter_plan_limits_premium_info, actor, type: :gitlab_com_derisk)
          when ::Plan::ULTIMATE
            ::Feature.enabled?(:rate_limiter_plan_limits_ultimate_info, actor, type: :gitlab_com_derisk)
          else
            false
          end
        end

        def enforce_flag_on?(plan)
          case plan
          when ::Plan::FREE
            ::Feature.enabled?(:rate_limiter_plan_limits_free_enforce, actor, type: :gitlab_com_derisk)
          when ::Plan::PREMIUM
            ::Feature.enabled?(:rate_limiter_plan_limits_premium_enforce, actor, type: :gitlab_com_derisk)
          when ::Plan::ULTIMATE
            ::Feature.enabled?(:rate_limiter_plan_limits_ultimate_enforce, actor, type: :gitlab_com_derisk)
          else
            false
          end
        end

        def unauthenticated_info_flag_on?
          ::Feature.enabled?(:rate_limiter_unauthenticated_limits_info, actor, type: :gitlab_com_derisk)
        end

        def unauthenticated_enforce_flag_on?
          ::Feature.enabled?(:rate_limiter_unauthenticated_limits_enforce, actor, type: :gitlab_com_derisk)
        end
      end
    end
  end
end
