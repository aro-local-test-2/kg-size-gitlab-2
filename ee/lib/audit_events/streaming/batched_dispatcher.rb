# frozen_string_literal: true

module AuditEvents
  module Streaming
    # Dispatches a batch of audit events for one top-level group to that
    # group's active external streaming destinations as batched payloads.
    #
    # This is where the pgbouncer reduction comes from: destination config is
    # looked up once per (group x batch) and payloads come from the NATS
    # message body, not a per-event Postgres fetch. A batch may mix event
    # types and namespaces, so events are still filtered per destination
    # (event-type and namespace filters) before the survivors are bundled
    # into one request.
    class BatchedDispatcher
      include ::Gitlab::Utils::StrongMemoize

      MAX_DESTINATIONS = ::AuditEvents::ExternallyStreamable::MAXIMUM_DESTINATIONS_PER_ENTITY

      # @param group_id [Integer, nil] top-level group ID; nil for
      #   instance-scoped events (only instance destinations apply)
      # @param payloads [Array<Hash>] parsed NATS message payloads for this
      #   group (schema v1 envelope: id, event_name, namespace_ancestor_ids,
      #   project_namespace, event, ...)
      def initialize(group_id, payloads)
        @group_id = group_id
        @payloads = payloads
      end

      # Dispatches to every eligible destination and reports the aggregate
      # outcome, so the caller acks only on full delivery and classifies the
      # error-budget signal correctly.
      #
      # A failure caused solely by a destination-side / user-config error
      # (ErrorClassifier.log_only?, e.g. Errno::ECONNRESET)
      # is reported as :destination_error rather than :failed: it is not a
      # GitLab-side fault, so it should not burn the dispatch error budget. It
      # still leaves the batch unacked so JetStream redelivers (at-least-once;
      # deduped downstream by event id), same as any other failure.
      #
      # @return [Symbol] :delivered when every destination succeeded (or there
      #   was nothing to send); :destination_error when the only failures were
      #   destination-side; :failed when any GitLab-side error occurred.
      def execute
        return :delivered if destinations.empty?

        # Sequential dispatch (parallelism comes from concurrent partition
        # drainers, not threads here). map, not short-circuit, so a failing
        # destination does not stop the rest.
        outcomes = destinations.map { |destination| dispatch_to_destination(destination) }

        return :failed if outcomes.include?(:failed)
        return :destination_error if outcomes.include?(:destination_error)

        :delivered
      end

      private

      attr_reader :group_id, :payloads

      def destinations
        eligible = ::AuditEvents::Streaming::CircuitBreaker.reject_open(all_destinations)
        eligible.select(&:active?)
      end
      strong_memoize_attr :destinations

      def all_destinations
        (group_destinations + instance_destinations)
      end

      def group_destinations
        group = ::Group.find_by_id(group_id)
        return [] unless group
        return [] unless group.licensed_feature_available?(:external_audit_events)

        group.external_audit_event_streaming_destinations.active.preload_filters.limit(MAX_DESTINATIONS).to_a
      end

      def instance_destinations
        return [] unless ::License.feature_available?(:external_audit_events)

        ::AuditEvents::Instance::ExternalStreamingDestination.active.preload_filters.limit(MAX_DESTINATIONS).to_a
      end

      # @return [Symbol] :ok when delivered (or nothing was eligible);
      #   :destination_error when the failure was a destination-side /
      #   user-config error (not GitLab's fault); :failed otherwise.
      def dispatch_to_destination(destination)
        allowed = payloads.select { |payload| allowed_to_stream?(destination, payload) }
        return :ok if allowed.empty?

        streamer = batch_streamer_for(destination)
        streamer.stream_batch(allowed.map { |payload| event_body(payload) })

        ::AuditEvents::Streaming::CircuitBreaker.record_success(destination)
        :ok
      rescue StandardError => e
        handle_dispatch_error(e, destination)

        ::AuditEvents::Streaming::ErrorClassifier.log_only?(e, destination.category) ? :destination_error : :failed
      end

      def batch_streamer_for(destination)
        streamer_cls = ::AuditEvents::Streaming::ErrorClassifier::STREAMER_DESTINATIONS[destination.category]
        raise ArgumentError, "Streamer class for category not found: #{destination.category}" unless streamer_cls

        streamer_cls.for_batch(destination)
      end

      # Filters need an event object (entity, streamable_namespace),
      # reconstructed from the in-message payload rather than fetched from
      # Postgres.
      #
      # A raise here is isolated to the offending payload (tracked and
      # excluded) so one bad event does not drop the rest of the batch for
      # this destination.
      def allowed_to_stream?(destination, payload)
        event = reconstructed_event(payload)
        return false unless event

        destination.allowed_to_stream?(payload['event_name'], event)
      rescue StandardError => e
        ::Gitlab::ErrorTracking.track_exception(e, destination_id: destination.id, event_id: payload['id'])
        false
      end

      # Memoized per payload id: dispatch runs allowed_to_stream? once per
      # destination, so without this the event JSON is re-parsed up to
      # MAX_DESTINATIONS times per batch. Uses key? so a nil result (fetch
      # failure) is cached too, rather than re-fetched per destination.
      def reconstructed_event(payload)
        return reconstructed_events[payload['id']] if reconstructed_events.key?(payload['id'])

        reconstructed_events[payload['id']] = ::AuditEvents::Processor.fetch(
          audit_event_json: ::Gitlab::Json.generate(payload['event'])
        )
      end

      def reconstructed_events
        @reconstructed_events ||= {}
      end

      # Matches the single-event body contract: serialized event plus the
      # stable dedup id and event type.
      def event_body(payload)
        body = payload['event'].dup
        body['id'] = payload['id']
        body['event_type'] = payload['event_name']
        body
      end

      def handle_dispatch_error(error, destination)
        context = {
          destination_id: destination.id,
          destination_name: destination.name,
          destination_category: destination.category
        }

        if ::AuditEvents::Streaming::ErrorClassifier.log_only?(error, destination.category)
          ::Gitlab::ErrorTracking.log_exception(error, context)
          ::AuditEvents::Streaming::CircuitBreaker.record_failure(destination)
        else
          ::Gitlab::ErrorTracking.track_exception(error, context)
        end
      end
    end
  end
end
