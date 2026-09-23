# frozen_string_literal: true

module Gitlab
  module Metrics
    # Metrics for the NATS audit event streaming pipeline (gitlab-org/gitlab#604455).
    #
    # Signals:
    #   - publish degradation (plain counters): how often a publish fell back
    #     to the Sidekiq path. This is deliberately NOT an error-rate SLI: a
    #     fallback still delivers the audit event through Sidekiq, so counting
    #     it as an error would drain the Compliance error budget during shadow
    #     mode and any window where NATS is off or degraded, even though no
    #     event was lost. Track it as a degradation ratio (fallbacks/attempts)
    #     instead. Fires from the request path (Puma) and audit worker (Sidekiq).
    #   - dispatch error rate (SLI): batch deliveries to external destinations
    #     that failed vs. succeeded. A failure here is a genuine delivery
    #     failure, so it is a real error budget signal. Fires from the consumer
    #     worker (Sidekiq).
    #   - dispatch lag apdex (SLI) + raw histogram: publish-to-dispatch latency
    #     scored against a target, plus a histogram for quantiles (p50/p95/p99)
    #     that an apdex ratio cannot express. Fires from the consumer worker.
    #
    # initialize_slis! pre-creates every metric's label set at boot, so rate()
    # alerts and dashboard panels read zero on a healthy fleet instead of "no
    # data" until the first event. The dispatch SLI feeds the runbooks metrics
    # catalog / error budgets once a catalog entry is added. The publish
    # counters are plain metrics (not gitlab_sli_*), so they are outside the
    # error-budget machinery by design.
    module AuditEventStreamingSlis
      include Gitlab::Metrics::SliConfig

      # Publish fires from the request path (Puma) and the audit worker
      # (Sidekiq), so both runtimes pre-initialize the publish counters;
      # dispatch and lag fire from the consumer worker (Sidekiq).
      puma_enabled!
      sidekiq_enabled!

      DISPATCH_SLI = :audit_event_streaming_nats_dispatch

      # Plain counters (deliberately no gitlab_sli_ prefix, which is reserved
      # for the SLI framework's total/error series): a fallback still delivers
      # via Sidekiq, so it is a degradation ratio, not an error-budget signal.
      PUBLISH_COUNTER = :gitlab_audit_event_streaming_nats_publish_total
      FALLBACK_COUNTER = :gitlab_audit_event_streaming_nats_publish_fallback_total
      # Consumer-side unreachability, which fallbacks (producer-side) do not
      # cover when only the Sidekiq fleet is partitioned off from NATS.
      CONSUMER_UNREACHABLE_COUNTER = :gitlab_audit_event_streaming_nats_consumer_unreachable_total
      # Dispatches that failed only because of a destination-side error, tracked
      # as degradation rather than a dispatch SLI error (see record_dispatch_destination_error).
      DISPATCH_DESTINATION_ERROR_COUNTER = :gitlab_audit_event_streaming_nats_dispatch_destination_error_total
      LAG_HISTOGRAM = :gitlab_audit_event_streaming_nats_consumer_lag_seconds
      # Wall time the synchronous publish blocks the calling Puma/Sidekiq
      # thread, so we can see caller latency, not just the fallback count.
      PUBLISH_DURATION_HISTOGRAM = :gitlab_audit_event_streaming_nats_publish_duration_seconds

      # Buckets in seconds. Delivery latency is second-scale (the scheduler
      # cron floor is one minute), so buckets span sub-second to a few minutes.
      LAG_BUCKETS = [0.5, 1, 5, 15, 30, 60, 120, 300].freeze
      # Healthy publishes are sub-second; the tail is bounded by the publish
      # timeout plus connect retries.
      PUBLISH_DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5].freeze

      # Apdex target: a dispatch is "satisfactory" when publish-to-dispatch
      # lag is at or below this. Set to the scheduler cron floor (one minute).
      LAG_APDEX_TARGET_SECONDS = 60

      LABELS = { feature_category: :audit_events }.freeze

      # Bounded set of reasons a publish fell back to Sidekiq, kept small so the
      # fallback counter's cardinality stays fixed (never the raw exception
      # message or class). See EnqueueService for how each is classified.
      FALLBACK_REASONS = %i[timeout connection_lost server_error unexpected].freeze

      class << self
        def initialize_slis!
          Gitlab::Metrics::Sli::ErrorRate.initialize_sli(DISPATCH_SLI, [LABELS])
          Gitlab::Metrics::Sli::Apdex.initialize_sli(DISPATCH_SLI, [LABELS])

          # Pre-create the plain counters at zero so their series exist before
          # the first publish (the SLI framework does this automatically for
          # the dispatch SLI; plain counters need an explicit zero increment).
          publish_counter.increment(LABELS, 0)
          consumer_unreachable_counter.increment(LABELS, 0)
          dispatch_destination_error_counter.increment(LABELS, 0)
          # One fallback series per reason so every reason reads zero on a
          # healthy fleet instead of "no data" until the first fallback.
          FALLBACK_REASONS.each { |reason| fallback_counter.increment(LABELS.merge(reason: reason), 0) }
        end

        # Records one publish attempt, and (when it fell back) one fallback
        # labelled with why. The fallback/attempt ratio is a degradation
        # signal, not an error.
        #
        # @param fallback [Boolean] whether the publish fell back to Sidekiq
        #   (NATS publish was not acknowledged).
        # @param reason [Symbol, nil] one of FALLBACK_REASONS; used when
        #   fallback is true (defaults to :unexpected).
        # @return [void]
        def record_publish(fallback:, reason: nil)
          publish_counter.increment(LABELS)
          return unless fallback

          reason = :unexpected unless FALLBACK_REASONS.include?(reason)
          fallback_counter.increment(LABELS.merge(reason: reason))
        end

        # @param seconds [Float] wall time the synchronous publish blocked the
        #   calling thread (recorded whether it succeeded or fell back).
        # @return [void]
        def record_publish_duration(seconds)
          return unless seconds && seconds >= 0

          publish_duration_histogram.observe(LABELS, seconds)
        end

        # @return [void]
        def record_consumer_unreachable
          consumer_unreachable_counter.increment(LABELS)
        end

        # @param result [:success, :failure] outcome of dispatching one group's
        #   batch. Per-group and per-partition detail belongs in structured logs
        #   (the consumer worker logs it); the SLI is a plain success ratio.
        # @return [void]
        def record_dispatch(result:)
          Gitlab::Metrics::Sli::ErrorRate[DISPATCH_SLI].increment(
            labels: LABELS,
            error: result == :failure
          )
        end

        # A dispatch that failed only because of a destination-side error.
        # Recorded separately from the dispatch SLI (degradation, not an error
        # budget signal); the batch is still redelivered.
        # @return [void]
        def record_dispatch_destination_error
          dispatch_destination_error_counter.increment(LABELS)
        end

        # @param seconds [Float] time between publish and dispatch (consumer lag)
        # @return [void]
        def observe_lag(seconds)
          return unless seconds

          if seconds < 0
            # Clock skew between the publishing and consuming hosts (NTP drift)
            # can produce a negative lag. Drop it from the metrics but leave a
            # breadcrumb rather than hiding it entirely.
            Gitlab::AppJsonLogger.debug(
              ::Labkit::Fields::CLASS_NAME => name,
              message: 'Dropping negative audit event streaming lag',
              lag_seconds: seconds
            )
            return
          end

          lag_histogram.observe(LABELS, seconds)
          dispatch_lag_apdex.increment(labels: LABELS, success: seconds <= LAG_APDEX_TARGET_SECONDS)
        end

        def dispatch_error_rate
          Gitlab::Metrics::Sli::ErrorRate[DISPATCH_SLI]
        end

        def dispatch_lag_apdex
          Gitlab::Metrics::Sli::Apdex[DISPATCH_SLI]
        end

        def publish_counter
          Gitlab::Metrics.counter(PUBLISH_COUNTER, 'Total number of audit event publish attempts through NATS')
        end

        def fallback_counter
          Gitlab::Metrics.counter(
            FALLBACK_COUNTER,
            'Total number of audit event publishes that fell back from NATS to Sidekiq'
          )
        end

        def consumer_unreachable_counter
          Gitlab::Metrics.counter(
            CONSUMER_UNREACHABLE_COUNTER,
            'Total number of audit event consumer drains aborted because NATS was unreachable'
          )
        end

        def dispatch_destination_error_counter
          Gitlab::Metrics.counter(
            DISPATCH_DESTINATION_ERROR_COUNTER,
            'Total number of audit event batch dispatches that failed due to a destination-side error'
          )
        end

        def publish_duration_histogram
          Gitlab::Metrics.histogram(
            PUBLISH_DURATION_HISTOGRAM,
            'Audit event streaming NATS synchronous publish duration in seconds',
            {},
            PUBLISH_DURATION_BUCKETS
          )
        end

        def lag_histogram
          Gitlab::Metrics.histogram(
            LAG_HISTOGRAM,
            'Audit event streaming NATS consumer lag (publish to dispatch) in seconds',
            {},
            LAG_BUCKETS
          )
        end
      end
    end
  end
end
