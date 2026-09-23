# frozen_string_literal: true

module Ai
  module RiskClassification
    class TimeoutWorker
      include ApplicationWorker

      TIMEOUT_DURATION = 30.minutes

      data_consistency :delayed
      idempotent!
      defer_on_database_health_signal :gitlab_main, [:merge_requests_risk_assessments]
      feature_category :duo_code_review
      urgency :low

      def self.enqueue(merge_request_id)
        perform_in(TIMEOUT_DURATION, merge_request_id)
      end

      def perform(merge_request_id)
        merge_request = MergeRequest.find_by_id(merge_request_id)
        return unless merge_request

        assessment = merge_request.risk_assessment
        return unless assessment

        # Locked so a concurrent CalculateScoreWorker completing the row can't be
        # clobbered by a decision made against this worker's stale in-memory status.
        # Rescheduling itself happens after the lock releases: Sidekiq forbids
        # enqueueing a job from inside a transaction.
        reschedule_deadline = assessment.with_lock do
          next unless assessment.can_mark_failed?

          # Expiring on the row's own idle time rather than on the timer's age keeps a timer
          # scheduled for an earlier run from failing a fresh classification, and the deadline
          # is deferred rather than dropped so the run keeps a backstop either way.
          deadline = assessment.updated_at + TIMEOUT_DURATION
          next deadline if deadline.future?

          assessment.mark_failed

          Gitlab::AppLogger.warn(
            message: 'Risk classification timed out',
            merge_request_id: merge_request_id,
            project_id: merge_request.target_project_id
          )

          nil
        end

        self.class.perform_in(reschedule_deadline - Time.current, merge_request_id) if reschedule_deadline
      end
    end
  end
end
