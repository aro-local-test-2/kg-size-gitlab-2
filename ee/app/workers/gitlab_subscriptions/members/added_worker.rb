# frozen_string_literal: true

module GitlabSubscriptions
  module Members
    class AddedWorker
      include Gitlab::EventStore::Subscriber

      feature_category :seat_cost_management
      data_consistency :sticky
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
