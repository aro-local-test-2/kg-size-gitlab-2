# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Validates the plain-hash event a run starts or continues with; the hash
    # crosses Sidekiq as JSON, so this stays a wrapper, not a value object. The
    # types key off the session's awaiting-state rather than its status list, so
    # a new awaiting-state extends the session model, not this class.
    class RunEvent
      INPUT_KEYS = %w[text type].freeze
      APPROVAL_KEYS = %w[approved message type].freeze
      APPROVAL_REQUIRED_KEYS = %w[approved type].freeze

      def initialize(event)
        @event = event.stringify_keys if event.is_a?(Hash)
      end

      def valid_for?(workflow)
        return false unless event

        (input? && (workflow.created? || workflow.input_required?)) ||
          (approval? && workflow.awaiting_approval?)
      end

      # `text` is not always prose: code_review/v1 passes an MR iid that gets
      # unpacked downstream. The type name stays neutral so that stays visible.
      def input?
        event_type == 'input' && event.keys.sort == INPUT_KEYS && event['text'].is_a?(String) &&
          event['text'].present?
      end

      # Tool and plan approval carry the identical payload, hence one type.
      def approval?
        event_type == 'approval' && (event.keys - APPROVAL_KEYS).empty? &&
          (APPROVAL_REQUIRED_KEYS - event.keys).empty? &&
          [true, false].include?(event['approved']) && (event['message'].nil? || event['message'].is_a?(String))
      end

      def text
        event['text']
      end

      def approved?
        event['approved']
      end

      def message
        event['message']
      end

      # String keys: this hash crosses the Sidekiq boundary and lands in the
      # Workhorse request body as JSON either way.
      def workhorse_approval
        return { 'approval' => {} } if approved?

        { 'rejection' => { 'message' => message } }
      end

      private

      attr_reader :event

      def event_type
        event['type'].to_s
      end
    end
  end
end
