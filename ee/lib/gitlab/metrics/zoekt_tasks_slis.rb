# frozen_string_literal: true

module Gitlab
  module Metrics
    module ZoektTasksSlis
      include Gitlab::Metrics::SliConfig

      puma_enabled!
      sidekiq_enabled!

      APDEX_THRESHOLD_S = 7200 # 2 hours

      # An exact 60 edge is required: a quantile interpolated across a bucket
      # straddling 60s cannot settle whether a 60s objective was met.
      DURATION_BUCKETS = [1, 5, 10, 30, 60, 120, 300, 600, 1800, 3600, 7200, 21600].freeze

      class << self
        def initialize_slis!
          Gitlab::Metrics::Sli::Apdex.initialize_sli(:search_zoekt_tasks, [])
          Gitlab::Metrics::Sli::ErrorRate.initialize_sli(:search_zoekt_tasks, [])
        end

        def increment_request_count(zoekt_node_id:, task_type:, count: 1)
          labels = { zoekt_node: zoekt_node_id.to_s, task_type: task_type.to_s }
          request_counter.increment(labels, count)
        end

        def increment_error_count(zoekt_node_id:, task_type:)
          labels = { zoekt_node: zoekt_node_id.to_s, task_type: task_type.to_s }
          Gitlab::Metrics::Sli::ErrorRate[:search_zoekt_tasks].increment(
            labels: labels,
            error: true
          )
        end

        def increment_apdex(zoekt_node_id:, task_type:, duration:)
          labels = { zoekt_node: zoekt_node_id.to_s, task_type: task_type.to_s }
          success = duration <= APDEX_THRESHOLD_S

          Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks].increment(
            labels: labels,
            success: success
          )

          duration_histogram.observe(labels, duration)

          Gitlab::AppJsonLogger.info(
            message: "Zoekt task Apdex SLI",
            ::Labkit::Fields::DURATION_S => duration,
            target_s: APDEX_THRESHOLD_S,
            success: success,
            zoekt_node: labels[:zoekt_node],
            task_type: labels[:task_type]
          )
        end

        private

        def request_counter
          @request_counter ||= Gitlab::Metrics.counter(
            :gitlab_sli_search_zoekt_tasks_requests_total,
            'Total number of Zoekt tasks added to the queue'
          )
        end

        # Not memoized: the registration example can only assert the buckets
        # if every call re-enters Gitlab::Metrics.histogram, and
        # Labkit::Metrics::Registry#safe_register already memoizes under a
        # mutex. Matches audit_event_streaming_slis.rb.
        def duration_histogram
          Gitlab::Metrics.histogram(
            :gitlab_search_zoekt_task_duration_seconds,
            "Seconds between a Zoekt task's scheduled time and its completion",
            {},
            DURATION_BUCKETS
          )
        end
      end
    end
  end
end
