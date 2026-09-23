# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class FetchNamespaceSessionCreditsWorker
      include ApplicationWorker
      # Registers migration pause control and the suspend_click_house_data_ingestion
      # kill switch, and declares external dependencies (ClickHouse plus the
      # CustomersDot HTTPS call, which offers no SLO).
      include ClickHouseWorker

      # Failed batches are never rescanned (the cron cursor has moved past them), so
      # Sidekiq's retry ladder is the recovery path for CustomersDot outages. RetryError
      # skips Sentry; the client already reports the underlying error there.
      FetchError = Class.new(::Gitlab::SidekiqMiddleware::RetryError)

      # Retrying cannot conjure a billable license or make CustomersDot expose a
      # field it has not deployed yet.
      PERMANENT_FAILURE_REASONS = [:no_billable_license, :undefined_field].freeze

      data_consistency :delayed
      idempotent!
      deduplicate :until_executed
      feature_category :duo_agent_platform
      # :throttled, not :low: concurrency_limit buffering counts toward :low's 60s
      # queueing SLO by design; :throttled has no queueing target.
      urgency :throttled
      tags :clickhouse
      loggable_arguments 0, 1
      defer_on_database_health_signal :gitlab_main_org, [:duo_workflows_workflows]

      # Bounds outbound pressure on CustomersDot: each job is an uncached ClickHouse
      # scan on their side. 50 in flight saturated CustomersDot in INC-13873.
      concurrency_limit -> { 5 }

      # Every retry re-queries CustomersDot, so every error waits out the back-off (and any
      # escalation) instead of Sidekiq's seconds-long default, jittered across a window so
      # the batches held during a latch do not all fire the moment it lifts.
      sidekiq_retry_in do |count|
        floor = [SessionCredits::Backoff.retry_floor.to_i, SessionCredits::Backoff::BACKOFF_DURATION.to_i].max
        [floor, (count**4) + 15].max + rand(SessionCredits::Backoff::BACKOFF_DURATION.to_i)
      end

      sidekiq_retries_exhausted do |job|
        ::Gitlab::AppLogger.error(
          Labkit::Fields::CLASS_NAME => name,
          Labkit::Fields::LOG_MESSAGE => 'Dropping session credits batch after exhausting retries',
          Labkit::Fields::GL_ROOT_NAMESPACE_ID => job['args']&.first,
          :workflow_ids => job['args']&.second
        )
      end

      # Both gates re-checked here: jobs buffered by concurrency_limit can drain long
      # after a toggle, and the derisk flag is the incident kill switch.
      def perform(namespace_id, workflow_ids)
        return unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?
        return unless ingestion_enabled_for?(namespace_id)
        # Queued batches wait out a degradation latch instead of each probing CustomersDot.
        raise FetchError, 'Backing off from CustomersDot' if SessionCredits::Backoff.retry_floor

        response = SessionCredits::IngestService.new(
          namespace_id: namespace_id,
          workflow_ids: workflow_ids
        ).execute

        return unless response.error?
        return if PERMANENT_FAILURE_REASONS.include?(response.reason)

        raise FetchError, response.message
      end

      private

      # A group gate or the global toggle both satisfy the group actor check.
      # Self-managed batches carry no namespace, so only the instance toggle applies.
      def ingestion_enabled_for?(namespace_id)
        return Feature.enabled?(:duo_workflow_session_credits_ingestion, :instance) unless namespace_id

        Feature.enabled?(:duo_workflow_session_credits_ingestion, ::Group.actor_from_id(namespace_id))
      end
    end
  end
end
