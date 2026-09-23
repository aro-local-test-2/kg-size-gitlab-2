# frozen_string_literal: true

module Ai
  module FlowTriggers
    class CreateService < BaseService
      def initialize(project:, current_user:, authorization_context: nil)
        unless authorization_context.nil? ||
            authorization_context.is_a?(::Ai::Catalog::Flows::InheritedProjectAuthorization)
          raise ArgumentError, 'Invalid inherited foundational-flow authorization context'
        end

        @project = project
        @current_user = current_user
        @authorization_context = authorization_context
      end

      def execute(params)
        return disallow_new_external_agent_error unless allow_external_agent_trigger?(params)

        config_error = custom_flow_config_error(ai_catalog_item_consumer(params[:ai_catalog_item_consumer_id]))
        return config_error if config_error

        result = super do |params|
          project.ai_flow_triggers.create(params)
        end

        if result.success?
          audit_flow_trigger('flow_trigger_created', result.payload)
          # Schedule config arrives inside the trigger's filter JSON, but execution
          # is driven by Ai::FlowSchedule rows (the dispatcher only scans next_run_at),
          # so the rows must be materialized from the filter or the schedule never fires.
          sync_result = ::Ai::FlowSchedules::SyncFromTriggerService.new(trigger: result.payload).execute

          if sync_result.error?
            log_error("Failed to sync flow schedule for flow trigger #{result.payload.id}: #{sync_result.message}")
          end
        end

        result
      end

      def allow_external_agent_trigger?(params)
        return true if new_external_agents_allowed?

        params[:config_path].blank?
      end
    end
  end
end
