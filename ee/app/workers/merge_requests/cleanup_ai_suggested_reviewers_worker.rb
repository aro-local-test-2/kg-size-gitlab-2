# frozen_string_literal: true

module MergeRequests
  class CleanupAiSuggestedReviewersWorker
    include Gitlab::EventStore::Subscriber

    feature_category :code_review_workflow
    data_consistency :sticky
    idempotent!

    def self.dispatch?(event)
      AiSuggestedReviewer.for_merge_request(event.data[:merge_request_id]).exists?
    end

    def handle_event(event)
      AiSuggestedReviewer.for_merge_request(event.data[:merge_request_id]).delete_all
    end
  end
end
