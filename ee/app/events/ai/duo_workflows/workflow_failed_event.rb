# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class WorkflowFailedEvent < ::Gitlab::EventStore::CloudEvent
      event_category :duo_agent_platform
      event_type :workflow_failed

      class << self
        def build(workflow:, status_event:)
          build_cloud_event(
            source: "ai/duo_workflows/workflows/#{workflow.id}",
            subject: "ai/duo_workflows/workflows/#{workflow.id}",
            event_data: { workflow_id: workflow.id, status_event: status_event.to_s }
          )
        end
      end

      def data_schema
        {
          'type' => 'object',
          'required' => %w[workflow_id status_event],
          'properties' => {
            'workflow_id' => { 'type' => 'integer' },
            'status_event' => { 'type' => 'string', 'enum' => %w[drop stop] }
          },
          'additionalProperties' => false
        }
      end
    end
  end
end
