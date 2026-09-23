# frozen_string_literal: true

module Types
  module Ai
    module FlowTrigger
      class EventTypeEnum < BaseEnum
        graphql_name 'AiFlowTriggerEventType'
        description 'Possible event types for flow triggers.'

        ::Ai::FlowTrigger::EVENT_TYPES.each do |event_type, id|
          # scheduled is experimental in case it gets renamed or redesigned.
          value event_type.upcase, description: "Flow trigger #{event_type} event.", value: id,
            experiment: event_type == :scheduled ? { milestone: '19.4' } : nil
        end
      end
    end
  end
end
