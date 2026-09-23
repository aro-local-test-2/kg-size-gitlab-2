# frozen_string_literal: true

module Ai
  module FlowTriggers
    class UpdateService < BaseService
      def initialize(project:, current_user:, trigger:)
        @project = project
        @current_user = current_user
        @trigger = trigger
      end

      def execute(params)
        return disallow_new_external_agent_error if disallow_config_path_change?(params)

        config_error = custom_flow_config_error_for_update(params)
        return config_error if config_error

        result = super do |params|
          @trigger.update(params)
          @trigger
        end

        if result.success?
          audit_flow_trigger('flow_trigger_updated', result.payload)
          # Re-materialize Ai::FlowSchedule rows when schedule config in the
          # filter changed, or remove them when the scheduled event type was dropped.
          sync_result = ::Ai::FlowSchedules::SyncFromTriggerService.new(trigger: result.payload).execute

          if sync_result.error?
            log_error("Failed to sync flow schedule for flow trigger #{result.payload.id}: #{sync_result.message}")
          end
        end

        result
      end

      private

      # Prevent an AI Catalog trigger from becoming a "manual" External Agent trigger
      # unless the user is allowed to create new External Agents.
      # See https://gitlab.com/gitlab-org/gitlab/-/issues/583687.
      def disallow_config_path_change?(params)
        @trigger.ai_catalog_item_consumer_id.present? && params[:config_path].present? && !new_external_agents_allowed?
      end

      # Validates the custom flow config only when the update adds event types to, or repoints the
      # trigger at, a custom flow. Returns a ServiceResponse.error to reject the update, otherwise nil.
      def custom_flow_config_error_for_update(params)
        consumer = target_ai_catalog_item_consumer(params)

        return unless consumer
        return unless adding_event_types?(params) || consumer != @trigger.ai_catalog_item_consumer

        custom_flow_config_error(consumer)
      end

      # The consumer the trigger will point at after the update: the incoming one when
      # ai_catalog_item_consumer_id is supplied, otherwise the trigger's current consumer.
      def target_ai_catalog_item_consumer(params)
        if params.key?(:ai_catalog_item_consumer_id)
          ai_catalog_item_consumer(params[:ai_catalog_item_consumer_id])
        else
          @trigger&.ai_catalog_item_consumer
        end
      end

      def adding_event_types?(params)
        return false unless params.key?(:event_types)

        (Array(params[:event_types]) - Array(@trigger.event_types)).present?
      end
    end
  end
end
