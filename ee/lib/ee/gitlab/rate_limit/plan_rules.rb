# frozen_string_literal: true

module EE
  module Gitlab
    module RateLimit
      module PlanRules
        extend ActiveSupport::Concern

        UNAUTHENTICATED_RULES = [
          ::Labkit::RateLimit::Rule.new(
            name: 'unauthenticated_traffic_per_ip', action: :limit,
            match: { requester_id: nil, runner_id: nil, git_http: false,
                     unauthenticated_limits_active: true, unauthenticated_enforced: true },
            characteristics: %i[ip], limit: 60, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'unauthenticated_traffic_per_ip_log', action: :log,
            match: { requester_id: nil, runner_id: nil, git_http: false,
                     unauthenticated_limits_active: true, unauthenticated_enforced: false },
            characteristics: %i[ip], limit: 60, period: 1.hour
          )
        ].freeze

        # Per user the limits are the published ones, so each budget is a :limit rule
        # and a :log twin split on the enforce flag. Per namespace is observe only:
        # a :log rule, no enforced twin, no enforce gate. Limits per
        # https://docs.gitlab.com/user/gitlab_com/rate_limits/#rate-limits-by-plan.
        #
        # Each rule states info-gates-enforce itself rather than reading a combined
        # fact, which is why both plan_limits_<plan>_info and _enforce appear here.
        PLAN_RULES = [
          # Free - per user, enforced
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_free_plan', action: :limit,
            match: { requester_plan: 'free', requester_id: /./,
                     plan_limits_free_info: true, plan_limits_free_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 5_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_free_plan_log', action: :log,
            match: { requester_plan: 'free', requester_id: /./,
                     plan_limits_free_info: true, plan_limits_free_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 5_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_free_plan', action: :limit,
            match: { requester_plan: 'free', requester_id: /./,
                     plan_limits_free_info: true, plan_limits_free_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 100, period: 1.minute
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_free_plan_log', action: :log,
            match: { requester_plan: 'free', requester_id: /./,
                     plan_limits_free_info: true, plan_limits_free_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 100, period: 1.minute
          ),

          # Free - per namespace, observe only
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_namespace_free_plan_log', action: :log,
            match: { target_namespace_plan: 'free', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_free_info: true },
            characteristics: %i[target_root_namespace_id], limit: 5_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_namespace_free_plan_log', action: :log,
            match: { target_namespace_plan: 'free', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_free_info: true },
            characteristics: %i[target_root_namespace_id], limit: 400, period: 1.minute
          ),

          # Premium - per user, enforced
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_premium_plan', action: :limit,
            match: { requester_plan: 'premium', requester_id: /./,
                     plan_limits_premium_info: true, plan_limits_premium_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 15_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_premium_plan_log', action: :log,
            match: { requester_plan: 'premium', requester_id: /./,
                     plan_limits_premium_info: true, plan_limits_premium_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 15_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_premium_plan', action: :limit,
            match: { requester_plan: 'premium', requester_id: /./,
                     plan_limits_premium_info: true, plan_limits_premium_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 1_250, period: 1.minute
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_premium_plan_log', action: :log,
            match: { requester_plan: 'premium', requester_id: /./,
                     plan_limits_premium_info: true, plan_limits_premium_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 1_250, period: 1.minute
          ),

          # Premium - per namespace, observe only
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_namespace_premium_plan_log', action: :log,
            match: { target_namespace_plan: 'premium', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_premium_info: true },
            characteristics: %i[target_root_namespace_id], limit: 60_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_namespace_premium_plan_log', action: :log,
            match: { target_namespace_plan: 'premium', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_premium_info: true },
            characteristics: %i[target_root_namespace_id], limit: 5_000, period: 1.minute
          ),

          # Ultimate - per user, enforced
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_ultimate_plan', action: :limit,
            match: { requester_plan: 'ultimate', requester_id: /./,
                     plan_limits_ultimate_info: true, plan_limits_ultimate_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 25_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_user_ultimate_plan_log', action: :log,
            match: { requester_plan: 'ultimate', requester_id: /./,
                     plan_limits_ultimate_info: true, plan_limits_ultimate_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 25_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_ultimate_plan', action: :limit,
            match: { requester_plan: 'ultimate', requester_id: /./,
                     plan_limits_ultimate_info: true, plan_limits_ultimate_enforce: true },
            characteristics: %i[requester_type requester_id], limit: 2_000, period: 1.minute
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_user_ultimate_plan_log', action: :log,
            match: { requester_plan: 'ultimate', requester_id: /./,
                     plan_limits_ultimate_info: true, plan_limits_ultimate_enforce: false },
            characteristics: %i[requester_type requester_id], limit: 2_000, period: 1.minute
          ),

          # Ultimate - per namespace, observe only
          ::Labkit::RateLimit::Rule.new(
            name: 'sustained_traffic_per_namespace_ultimate_plan_log', action: :log,
            match: { target_namespace_plan: 'ultimate', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_ultimate_info: true },
            characteristics: %i[target_root_namespace_id], limit: 100_000, period: 1.hour
          ),
          ::Labkit::RateLimit::Rule.new(
            name: 'burst_traffic_per_namespace_ultimate_plan_log', action: :log,
            match: { target_namespace_plan: 'ultimate', requester_id: /./,
                     target_root_namespace_id: /./, plan_limits_ultimate_info: true },
            characteristics: %i[target_root_namespace_id], limit: 10_000, period: 1.minute
          )
        ].freeze

        RULES = (UNAUTHENTICATED_RULES + PLAN_RULES).freeze

        class_methods do
          extend ::Gitlab::Utils::Override

          override :flags
          def flags
            ::Gitlab::RateLimit::FlagPolicy::FLAGS
          end

          override :active?
          def active?
            ::Gitlab::RateLimit::FlagPolicy.any_flag_enabled?
          end

          override :for_limiter
          def for_limiter(limiter_name)
            return [] unless limiter_name == ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::GENERAL
            return [] unless ::Gitlab::RateLimit::FlagPolicy.gitlab_com?

            RULES
          end
        end
      end
    end
  end
end
