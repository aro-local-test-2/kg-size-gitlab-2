# frozen_string_literal: true

module EE
  module Gitlab
    module RackAttack
      module LabkitRateLimit
        # Adds the EE-only facts to ClassifiedRequest:
        #   - setting_incident_management_notification: the incident throttle's enable
        #     setting (its match is otherwise all CE facts: the alerts/notify path).
        #   - verified_geo_request: the geo-JWT skips (verified_geo_request? and
        #     geo_proxy_workhorse_request?), the parts of EE's should_be_skipped? that
        #     verify a JWT and so cannot be a path matcher. Lives here, not in CE,
        #     because those predicates are EE-only - referencing them from CE would
        #     raise under FOSS.
        #   - unauthenticated_limits_active / unauthenticated_enforced: the unauthenticated
        #     per-IP throttle carries no plan, so it has no plan fact to switch it off.
        #   - requester_plan: the plan of the authenticated requester, so a rule matching
        #     it counts by requester_type and requester_id.
        #   - target_namespace_plan / target_root_namespace_id: the plan of the namespace
        #     the request addresses, so a rule matching it counts by
        #     target_root_namespace_id.
        #     Both are gated only by plan_facts_enabled?. Which plans a rule acts on is
        #     the rule's own business, declared in its match through the
        #     plan_limits_<plan>_* facts below.
        #   - plan_limits_<plan>_{info,enforce}: one fact per flag, uncoupled, so a rule
        #     declares its own gate instead of reading a combined boolean. Always the
        #     full set, whatever the flags say.
        module ClassifiedRequest
          extend ::Gitlab::Utils::Override
          include ::Gitlab::Utils::StrongMemoize

          private

          # Strings and ids stay uncoerced, so they live with the identity facts.
          override :identity_facts
          def identity_facts
            return super unless flag_policy.plan_facts_enabled?

            super.merge(
              requester_plan: requester_plan,
              target_namespace_plan: target_namespace_plan,
              target_root_namespace_id: target_root_namespace_id
            )
          end

          # Extends the classification facts (not labkit_facts) so the strict-boolean
          # coercion in Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest#labkit_facts
          # applies to these facts too.
          override :classification_facts
          def classification_facts
            super.merge(
              setting_incident_management_notification:
                ::Gitlab::Throttle.settings.throttle_incident_management_notification_enabled,
              verified_geo_request: verified_geo_request? || geo_proxy_workhorse_request?,
              unauthenticated_limits_active: flag_policy.unauthenticated_info_enabled?,
              unauthenticated_enforced: flag_policy.unauthenticated_enforce_enabled?,
              **flag_policy.plan_flags
            )
          end

          def flag_policy
            ::Gitlab::RateLimit::FlagPolicy
          end

          # Every authenticated requester carries a plan. A deploy token resolves it
          # from the namespace it belongs to; a job token resolves it from the job's
          # user, which is already what requester holds. A runner token reaches none
          # of this: it sets runner_id and no requester, so the guard above returns.
          def requester_plan
            return unless requester[:id]

            if requester[:type] == 'deploy_token'
              ::Gitlab::RateLimit::TierResolver.namespace_tier_for(requester_root_namespace_id)
            else
              ::Gitlab::RateLimit::TierResolver.tier_for(requester[:type], requester[:id])
            end
          end
          strong_memoize_attr :requester_plan

          # The namespace the requester authenticated as, which is not necessarily the one
          # the request addresses: a deploy token belongs to one project or group, and a
          # job token can reach another namespace through the job-token allowlist. Only
          # requester_plan reads this.
          def requester_root_namespace_id
            return unless requester[:type] == 'deploy_token'

            token = authenticated_requester

            if token.project_id
              ::Gitlab::RateLimit::TargetNamespace.id_for_project(token.project_id)
            else
              ::Gitlab::RateLimit::TargetNamespace.id_for_group(token.group_id)
            end
          end
          strong_memoize_attr :requester_root_namespace_id

          # Always the path, for every requester type, so the fact describes what the
          # request addresses rather than what it authenticated as. Authenticated
          # requests only: the namespace rules require a requester, so an anonymous
          # request would pay for a lookup nothing can match on. The raw path goes to
          # TargetNamespace, which strips the relative URL root itself.
          def target_root_namespace_id
            return unless requester[:id]

            ::Gitlab::RateLimit::TargetNamespace.id_for_path(path)
          end
          strong_memoize_attr :target_root_namespace_id

          def target_namespace_plan
            return unless target_root_namespace_id

            ::Gitlab::RateLimit::TierResolver.namespace_tier_for(target_root_namespace_id)
          end
          strong_memoize_attr :target_namespace_plan
        end
      end
    end
  end
end
