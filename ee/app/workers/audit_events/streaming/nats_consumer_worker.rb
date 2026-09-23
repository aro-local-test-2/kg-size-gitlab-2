# frozen_string_literal: true

module AuditEvents
  module Streaming
    # Scheduler for the NATS audit event streaming consumer.
    #
    # This worker does not drain. On each 1-minute tick it fans out one
    # NatsPartitionConsumerWorker per partition key, each of which drains its
    # partition in a loop for most of the minute. This gives near-continuous
    # draining on existing Sidekiq infrastructure without a long-running
    # process type, since sidekiq-cron granularity alone (one minute) is too
    # coarse for the delivery cadence.
    #
    # It also lease-guards stream provisioning as a self-healing safety net.
    class NatsConsumerWorker
      include ApplicationWorker
      include CronjobQueue # rubocop:disable Scalability/CronWorkerContext -- fans out instance-wide partition drainers; messages are not tied to a single context

      idempotent!
      # This scheduler takes no arguments, so every tick shares one idempotency
      # key: the default strategy would suppress subsequent ticks for the dedup
      # TTL if one stalls before executing. Each tick must run; concurrency is
      # bounded by the drainer's per-partition lease instead.
      deduplicate :none
      worker_has_external_dependencies!
      data_consistency :sticky
      feature_category :audit_events
      urgency :low
      defer_on_database_health_signal :gitlab_main

      def perform
        return if ::Gitlab::SilentMode.enabled?
        return unless ::Gitlab::Nats.enabled?
        return unless Feature.enabled?(:audit_event_streaming_nats_consumer, :instance) # -- instance-wide kill switch

        ensure_stream

        fan_out_partition_drainers
      end

      private

      def fan_out_partition_drainers
        args_list = ::AuditEvents::Streaming::NatsPartitioning.partition_keys.map { |key| [key] }

        # rubocop:disable Scalability/BulkPerformWithContext -- drainers are keyed by partition, not by a
        # specific project or namespace (a partition spans many groups), so there is no per-job context to
        # attach; this matches the instance-wide CronWorkerContext exemption on this scheduler.
        ::AuditEvents::Streaming::NatsPartitionConsumerWorker.bulk_perform_async(args_list)
        # rubocop:enable Scalability/BulkPerformWithContext
      end

      # Best-effort: a missing stream degrades gracefully (publish falls back
      # to Sidekiq) and the next tick retries, so failures are only logged.
      def ensure_stream
        ::AuditEvents::Streaming::NatsStreamProvisioner.ensure_once!
      rescue StandardError => e
        ::Gitlab::ErrorTracking.log_exception(e)
      end
    end
  end
end
