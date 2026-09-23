# frozen_string_literal: true

module GitlabSubscriptions
  module Members
    class DestroyedWorker
      include Gitlab::EventStore::Subscriber

      data_consistency :delayed
      feature_category :seat_cost_management
      urgency :low
      idempotent!
      deduplicate :until_executed

      # No-op: seat data syncing is replaced by a single backfill at
      # activation time. Kept for one release to drain queued jobs.
      # See https://gitlab.com/gitlab-org/gitlab/-/work_items/606016
      def handle_event(event); end
    end
  end
end
