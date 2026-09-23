# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::ResyncMergeRequestRulesWorker, feature_category: :security_policy_management do
  let_it_be_with_reload(:project) { create(:project, :repository) }
  let_it_be_with_reload(:merge_request) do
    create(:ee_merge_request, target_project: project, source_project: project)
  end

  let_it_be(:protected_branch) { create(:protected_branch, project: project, name: merge_request.target_branch) }
  let_it_be(:policy_rule) { create(:approval_policy_rule) }

  let_it_be(:project_rule) do
    create(:approval_project_rule, :scan_finding, project: project,
      approval_policy_rule: policy_rule, approvals_required: 2)
  end

  let_it_be(:project_link) do
    create(:approval_policy_rule_project_link, approval_policy_rule: policy_rule, project: project)
  end

  before do
    stub_licensed_features(security_orchestration_policies: true)
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(merge_request.id) }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [merge_request.id] }
    end

    it 'synchronizes the policy approval rules from the target project' do
      expect { perform }.to change { merge_request.approval_rules.report_approver.count }.by(1)

      expect(merge_request.approval_rules.report_approver.order(:id).first.approvals_required).to eq(0)
    end

    it 'schedules policy synchronization' do
      allow(MergeRequest).to receive(:find_by_id).with(merge_request.id).and_return(merge_request)
      expect(merge_request).to receive(:schedule_policy_synchronization)

      perform
    end

    context 'when the sync fails validation' do
      before do
        allow(MergeRequest).to receive(:find_by_id).with(merge_request.id).and_return(merge_request)
        allow_next_instance_of(MergeRequests::SyncReportApproverApprovalRules) do |service|
          allow(service).to receive(:execute).and_raise(ActiveRecord::RecordInvalid)
        end
      end

      it 'tracks the exception and still schedules policy synchronization' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(ActiveRecord::RecordInvalid), merge_request_id: merge_request.id)
        expect(merge_request).to receive(:schedule_policy_synchronization)

        expect { perform }.not_to raise_error
      end
    end

    context 'when the merge request is merged' do
      before do
        merge_request.mark_as_merged!
      end

      it 'does not synchronize approval rules' do
        expect { perform }.not_to change { merge_request.approval_rules.count }
      end
    end

    context 'when the feature is not licensed' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it 'does not synchronize approval rules' do
        expect { perform }.not_to change { merge_request.approval_rules.count }
      end
    end

    context 'when the merge request does not exist' do
      subject(:perform) { described_class.new.perform(non_existing_record_id) }

      it 'does not raise an error' do
        expect { perform }.not_to raise_error
      end
    end
  end
end
