# frozen_string_literal: true

module Ai
  module Catalog
    module Flows
      class ExecuteWorkItemStatusChangedWorkflowTriggersWorker
        include Ai::CloudEventsFlowTriggerWorker

        concurrency_limit -> { 100 }
        idempotent!

        class << self
          def cloud_event_class
            ::WorkItems::StatusChangedEvent
          end

          def event_type
            :work_item
          end

          def action
            'status_changed'
          end
        end

        private

        # Lets `status.name` filter rules match the status the work item moved to.
        def filter_data_extras(cloud_event)
          { 'status' => { 'name' => cloud_event.event_data.dig(:status, :name) } }
        end

        def find_resource_and_container(cloud_event)
          work_item = WorkItem.find_by_id(cloud_event.event_data[:work_item_id])

          unless work_item
            logger.info(structured_payload(message: 'Work item not found.',
              work_item_id: cloud_event.event_data[:work_item_id]))
            return
          end

          project = work_item.project

          unless project
            logger.info(structured_payload(message: 'Work item has no project, skipping.',
              work_item_id: work_item.id))
            return
          end

          [work_item, project]
        end
      end
    end
  end
end
