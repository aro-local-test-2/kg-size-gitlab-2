# frozen_string_literal: true

module Ai
  module RiskClassification
    class CalculateScoreWorker
      include ApplicationWorker

      data_consistency :delayed
      idempotent!
      defer_on_database_health_signal :gitlab_main, [:merge_requests_risk_assessments]
      feature_category :duo_code_review
      urgency :low

      def perform(merge_request_id, diff_sha, classification, workflow_id)
        merge_request = MergeRequest.find_by_id(merge_request_id)
        return unless merge_request

        assessment = merge_request.risk_assessment
        return unless assessment

        classification = (classification || {}).deep_stringify_keys
        result = score(merge_request, classification)

        # Locked so a concurrent TimeoutWorker can't read a stale, still-queued
        # in-memory status after this transaction commits and clobber the result.
        assessment.with_lock do
          # Only a queued assessment is waiting on a score. Writing to one that has since
          # failed or completed would leave a row that reads as fully scored while its
          # status says otherwise.
          unless assessment.queued?
            log_warning('Risk classification score arrived for an assessment that is not queued', assessment)
            next
          end

          assessment.update!(attributes_from(result, classification, diff_sha, workflow_id))
          assessment.finish
        end
      end

      private

      def log_warning(message, assessment)
        Gitlab::AppLogger.warn(
          message: message,
          merge_request_id: assessment.merge_request_id,
          status: assessment.status_name
        )
      end

      def score(merge_request, classification)
        signals = ::Gitlab::Duo::RiskClassification::SignalsExtractor.new(merge_request).execute
        scoring_function = ::Gitlab::Duo::RiskClassification::ScoringFunction.current

        scoring_function.new(
          claims: classification['claims'],
          signals: signals.signals,
          mitigations: signals.mitigations,
          missing: signals.missing
        ).execute
      end

      def attributes_from(result, classification, diff_sha, workflow_id)
        {
          diff_sha: diff_sha,
          duo_workflow_id: workflow_id,
          classification: classification,
          score: result.score,
          confidence: result.confidence,
          signal_breakdown: result.signal_breakdown,
          missing_signals: result.missing_signals,
          domain_tags: domain_tags_from(result),
          scoring_function_version: result.version,
          rationale: classification['summary'],
          assessed_at: Time.current
        }
      end

      def domain_tags_from(result)
        domain_names = ::Gitlab::Duo::RiskClassification::Domain.all.map(&:name)

        result.signal_breakdown.filter_map do |contribution|
          signal = contribution['signal']
          signal if domain_names.include?(signal) && contribution['contribution'].to_f > 0
        end
      end
    end
  end
end
