# frozen_string_literal: true

module Security
  module SecurityOrchestrationPolicies
    class EventPublisher
      def initialize(
        db_policies:, created_policies:, policies_changes:, deleted_policies:,
        force_resync: false, triggered_by_assign: false
      )
        @db_policies = db_policies
        @created_policies = created_policies
        @policies_changes = policies_changes
        @deleted_policies = deleted_policies
        @force_resync = force_resync
        @triggered_by_assign = triggered_by_assign
      end

      def publish
        if force_resync
          ::Gitlab::EventStore.publish_group(
            db_policies.map do |policy|
              Security::PolicyResyncEvent.new(data: { security_policy_id: policy.id })
            end
          )
        else
          # On triggered_by_assign, only created_policies can exist, so it's not required to pass
          # triggered_by_assign flag in other events
          ::Gitlab::EventStore.publish_group(
            created_policies.map { |policy| Security::PolicyCreatedEvent.new(data: created_event_data(policy)) }
          )

          ::Gitlab::EventStore.publish_group(
            policies_changes.map do |policy_changes|
              Security::PolicyUpdatedEvent.new(data: policy_changes.event_payload)
            end
          )
        end

        ::Gitlab::EventStore.publish_group(
          deleted_policies.map { |policy| Security::PolicyDeletedEvent.new(data: { security_policy_id: policy.id }) }
        )
      end

      private

      attr_accessor :created_policies, :policies_changes, :deleted_policies, :db_policies, :force_resync,
        :triggered_by_assign

      def created_event_data(policy)
        data = { security_policy_id: policy.id }
        data[:triggered_by_assign] = true if triggered_by_assign

        data
      end
    end
  end
end
