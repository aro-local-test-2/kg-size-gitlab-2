# frozen_string_literal: true

module EE
  module API
    module Entities
      module Namespace
        extend ActiveSupport::Concern

        prepended do
          can_update_limits = ->(namespace, opts) { ::Ability.allowed?(opts[:current_user], :update_subscription_limit, namespace) }
          can_admin_namespace = ->(namespace, opts) { ::Ability.allowed?(opts[:current_user], :admin_namespace, namespace) }
          has_gitlab_subscription = ->(namespace) { namespace.gitlab_subscription.present? }
          can_read_usage = ->(namespace, opts) do
            namespace.root? && ::Ability.allowed?(opts[:current_user], :admin_ci_minutes, namespace)
          end

          expose :shared_runners_minutes_limit, documentation: { type: 'Integer', example: 133 }, if: can_update_limits
          expose :ci_minutes_usage,
            using: ::API::Entities::Ci::Minutes::Usage,
            if: can_read_usage do |namespace, options|
            totals = options[:ci_minutes_totals]
            total = totals ? totals.fetch(namespace.id, 0).to_i : nil

            ::Ci::Minutes::Usage.new(namespace, total_minutes_used: total)
          end
          expose :extra_shared_runners_minutes_limit, documentation: { type: 'Integer', example: 133 }, if: can_update_limits
          expose :additional_purchased_storage_size, documentation: { type: 'Integer', example: 1000 }, if: can_update_limits
          expose :additional_purchased_storage_ends_on, documentation: { type: 'Date', example: '2022-06-18' }, if: can_update_limits
          expose :billable_members_count, documentation: { type: 'Integer', example: 2 } do |namespace, options|
            next unless can_read_billing?(namespace, options)

            namespace.billable_members_count(options[:requested_hosted_plan])
          end
          expose :seats_in_use, documentation: { type: 'Integer', example: 5 }, if: has_gitlab_subscription do |namespace, options|
            next unless can_read_billing?(namespace, options)

            namespace.gitlab_subscription.seats_in_use
          end
          expose :max_seats_used, documentation: { type: 'Integer', example: 100 }, if: has_gitlab_subscription do |namespace, options|
            next unless can_read_billing?(namespace, options)

            namespace.gitlab_subscription.max_seats_used
          end
          expose :max_seats_used_changed_at, documentation: { type: 'Date', example: '2022-06-18' }, if: has_gitlab_subscription do |namespace, options|
            next unless can_read_billing?(namespace, options)

            namespace.gitlab_subscription.max_seats_used_changed_at
          end
          expose :end_date, documentation: { type: 'Date', example: '2022-06-18' }, if: has_gitlab_subscription do |namespace, options|
            next unless can_read_billing?(namespace, options)

            namespace.gitlab_subscription.end_date
          end
          expose :plan, documentation: { type: 'String', example: 'default' }, if: can_admin_namespace do |namespace, _|
            namespace.actual_plan_name
          end
          expose :trial_ends_on, documentation: { type: 'Date', example: '2022-06-18' }, if: can_admin_namespace do |namespace, _|
            namespace.trial_ends_on
          end
          expose :trial, documentation: { type: 'Boolean' }, if: can_admin_namespace do |namespace, _|
            namespace.trial?
          end

          private

          def can_read_billing?(namespace, opts)
            ::Ability.allowed?(opts[:current_user], :read_billing, namespace)
          end
        end
      end
    end
  end
end
