# frozen_string_literal: true

module Security
  module ScanResultPolicies
    class UnblockPendingMergeRequestViolationsWorker
      include ApplicationWorker
      include Gitlab::Utils::StrongMemoize
      include ::Security::ScanResultPolicies::PolicyLogger

      idempotent!
      data_consistency :sticky
      deduplicate :until_executing, including_scheduled: true
      feature_category :security_policy_management

      def perform(pipeline_id)
        pipeline = ::Ci::Pipeline.find_by_id(pipeline_id) || return

        pipeline.opened_merge_requests_with_head_sha.each do |merge_request|
          # Check the target project: for fork merge requests the pipeline's
          # project is the fork, which does not enforce the policies.
          next unless policy_available?(merge_request.project)

          skip_policy_evaluation(merge_request)
        end
      end

      private

      # Memoized per project: an unlicensed project falls through to the dependency
      # firewall check, which is the most expensive branch and would otherwise repeat
      # for every merge request sharing a target.
      def policy_available?(project)
        strong_memoize_with(:policy_available, project.id) do
          ::Security::PolicyAvailability.any_available?(project)
        end
      end

      def skip_policy_evaluation(merge_request)
        violations = merge_request.running_scan_result_policy_violations
        return if violations.blank?

        approval_rules = merge_request.approval_rules.report_approver
                                      .for_approval_policy_rules(violations.map(&:approval_policy_rule_id))
        return if approval_rules.blank?

        evaluation = Security::SecurityOrchestrationPolicies::PolicyRuleEvaluationService.new(merge_request)
        approval_rules.each { |rule| evaluation.skip!(rule) }
        evaluation.save
        log_policy_evaluation('unblock_pending_violations',
          'Policy evaluation timed out, skipping and requiring approvals',
          project: merge_request.project, merge_request_id: merge_request.id, approval_rules: approval_rules)
      end
    end
  end
end
