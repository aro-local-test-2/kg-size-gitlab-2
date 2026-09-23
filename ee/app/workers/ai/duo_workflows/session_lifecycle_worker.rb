# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Skeleton worker, not yet subscribed to any event. Landed ahead of its
    # implementation so the Sidekiq fleet knows the class before anything
    # schedules it from a web/API path.
    #
    # rubocop:disable Scalability/IdempotentWorker -- EventStore::Subscriber includes idempotent
    class SessionLifecycleWorker
      include Gitlab::EventStore::Subscriber

      feature_category :duo_agent_platform

      data_consistency :sticky
      urgency :high

      concurrency_limit -> { 100 }

      sidekiq_options retry: 3

      defer_on_database_health_signal :gitlab_main_org, [:duo_workflows_workflows]

      def handle_event(event)
        # no-op, implemented in a follow-up MR
      end
    end
    # rubocop:enable Scalability/IdempotentWorker
  end
end
