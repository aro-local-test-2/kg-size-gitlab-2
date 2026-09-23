# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::UpdateResultsService, feature_category: :duo_code_review do
  # Reloaded per example: the service builds the risk_assessment association on
  # this object, and that cache outlives the rolled-back row it points at.
  let_it_be_with_reload(:merge_request) { create(:merge_request) }
  let_it_be(:workflow) do
    create(
      :duo_workflows_workflow,
      project: merge_request.target_project,
      user: merge_request.author,
      merge_request: merge_request,
      workflow_definition: 'risk_classification/v1'
    )
  end

  let_it_be(:diff_sha) { merge_request.diff_head_sha }

  let_it_be(:earlier_diff) do
    create(:merge_request_diff, merge_request: merge_request)
  end

  let_it_be(:later_diff) do
    create(:merge_request_diff, merge_request: merge_request)
  end

  let_it_be(:earlier_diff_sha) { earlier_diff.head_commit_sha }
  let_it_be(:later_diff_sha) { later_diff.head_commit_sha }

  let(:classification) do
    {
      'claims' => { 'authorization' => { 'value' => 'true', 'evidence' => 'app/policies/project_policy.rb:44' } },
      'summary' => 'Adds a session token refresh path.'
    }
  end

  subject(:service) do
    described_class.new(
      merge_request: merge_request,
      classification: classification,
      diff_sha: diff_sha,
      workflow_id: workflow.id
    )
  end

  describe '#execute' do
    it 'creates a queued risk assessment and hands the results to the scoring job' do
      expect_next_instance_of(MergeRequests::RiskAssessment) do |assessment|
        expect(assessment).to receive(:enqueue_risk_score_calculation)
          .with(diff_sha, classification, workflow.id)
      end

      result = service.execute

      expect(result).to be_success

      assessment = result.payload[:assessment]
      expect(assessment).to be_persisted
      expect(assessment).to be_queued
      expect(assessment.diff_sha).to eq(diff_sha)
    end

    context 'when diff_sha does not match any known revision of the merge request' do
      let(:diff_sha) { Digest::SHA1.hexdigest(SecureRandom.hex) } # rubocop:disable Fips/SHA1 -- test data

      it 'returns an error without creating an assessment' do
        expect { service.execute }.not_to change { MergeRequests::RiskAssessment.count }

        result = service.execute

        expect(result).to be_error
        expect(result.message).to include(diff_sha)
      end
    end

    context 'when the write is refused' do
      it 'does not hand off the session' do
        other_workflow = create(:duo_workflows_workflow, project: merge_request.target_project,
          user: merge_request.author)
        create(:merge_requests_risk_assessment, merge_request: merge_request,
          diff_sha: later_diff_sha, duo_workflow_id: other_workflow.id)

        older = described_class.new(merge_request: merge_request, classification: classification,
          diff_sha: earlier_diff_sha, workflow_id: workflow.id)

        expect(older.execute).to be_error
        expect(merge_request.reload.risk_assessment.duo_workflow_id).to eq(other_workflow.id)
      end
    end

    context 'when the session does not belong to this merge request' do
      let(:other_merge_request) { create(:merge_request) }
      let(:foreign_workflow) do
        create(:duo_workflows_workflow, project: other_merge_request.target_project,
          user: other_merge_request.author, merge_request: other_merge_request)
      end

      subject(:service) do
        described_class.new(merge_request: merge_request, classification: classification, diff_sha: diff_sha,
          workflow_id: foreign_workflow.id)
      end

      it 'refuses the submission and records nothing' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to include(foreign_workflow.id.to_s)
        expect(merge_request.reload.risk_assessment).to be_nil
      end
    end

    context 'when the session belongs to this merge request but is not a risk classification session' do
      let(:other_flow_workflow) do
        create(
          :duo_workflows_workflow,
          project: merge_request.target_project,
          user: merge_request.author,
          merge_request: merge_request,
          workflow_definition: 'software_development/v1'
        )
      end

      subject(:service) do
        described_class.new(merge_request: merge_request, classification: classification, diff_sha: diff_sha,
          workflow_id: other_flow_workflow.id)
      end

      it 'refuses the submission and records nothing' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to include(other_flow_workflow.id.to_s)
        expect(merge_request.reload.risk_assessment).to be_nil
      end
    end

    context 'when the session does not exist at all' do
      subject(:service) do
        described_class.new(merge_request: merge_request, classification: classification, diff_sha: diff_sha,
          workflow_id: non_existing_record_id)
      end

      it 'refuses the submission rather than failing on the foreign key' do
        expect(service.execute).to be_error
        expect(merge_request.reload.risk_assessment).to be_nil
      end
    end

    context 'when the merge request already has a risk assessment' do
      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :pending, merge_request: merge_request, diff_sha: diff_sha)
      end

      it 'updates the existing assessment instead of creating a new one' do
        expect { service.execute }.not_to change { MergeRequests::RiskAssessment.count }

        expect(existing_assessment.reload).to be_queued
      end
    end

    context 'when the incoming diff_sha is a later revision than the existing assessment' do
      let_it_be(:diff_sha) { later_diff_sha }

      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :complete, merge_request: merge_request,
          diff_sha: earlier_diff_sha, score: 42, confidence: 80, rationale: 'Touches auth code.',
          signal_breakdown: [{ 'type' => 'auth_change' }], assessed_at: 1.hour.ago,
          scoring_function_version: 'v1')
      end

      it 'queues it for rescoring, even though the existing one was complete' do
        result = service.execute

        expect(result).to be_success
        expect(existing_assessment.reload).to be_queued
      end

      it 'leaves the previous scoring envelope for the job to reset' do
        service.execute

        existing_assessment.reload
        expect(existing_assessment.score).to eq(42)
        expect(existing_assessment.classification).to eq({})
      end
    end

    context 'when the incoming diff_sha is an earlier revision than the existing assessment' do
      let(:diff_sha) { earlier_diff_sha }

      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :pending, merge_request: merge_request, diff_sha: later_diff_sha)
      end

      it 'rejects the submission as stale, even though the existing one is only pending' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to include(diff_sha, later_diff_sha)
        expect(existing_assessment.reload).to be_pending
      end
    end

    context 'when the incoming diff_sha matches the existing assessment (retried submission)' do
      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :complete, merge_request: merge_request, diff_sha: diff_sha)
      end

      it 'allows the resubmission' do
        result = service.execute

        expect(result).to be_success
        expect(existing_assessment.reload).to be_queued
      end
    end

    context "when the existing assessment's diff_sha no longer matches a known revision" do
      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :complete, merge_request: merge_request,
          diff_sha: Digest::SHA1.hexdigest(SecureRandom.hex)) # rubocop:disable Fips/SHA1 -- simulates a pruned diff
      end

      it 'fails open and allows the write, since staleness cannot be proven' do
        result = service.execute

        expect(result).to be_success
        expect(existing_assessment.reload).to be_queued
      end
    end

    context 'when the assessment is already queued for the same diff_sha (a duplicate submission)' do
      let_it_be_with_reload(:existing_assessment) do
        create(:merge_requests_risk_assessment, :queued, merge_request: merge_request, diff_sha: diff_sha)
      end

      it 'touches the row, since the same-state loopback leaves nothing else to save' do
        expect { service.execute }.to change { existing_assessment.reload.updated_at }
      end
    end

    context 'when the refresh event refuses and the guard cannot explain why' do
      let_it_be(:existing_assessment) do
        create(:merge_requests_risk_assessment, :complete, merge_request: merge_request, diff_sha: diff_sha)
      end

      before do
        allow(merge_request).to receive(:risk_assessment).and_return(existing_assessment)
        allow(existing_assessment).to receive(:refresh).and_return(false)
      end

      it 'returns an error naming the state it could not leave' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to include('complete')
      end
    end

    context 'when an older request for the same merge request is processed after a newer one' do
      let(:newer_service) do
        described_class.new(merge_request: merge_request, classification: classification,
          diff_sha: later_diff_sha, workflow_id: workflow.id)
      end

      let(:older_service) do
        described_class.new(merge_request: merge_request, classification: classification,
          diff_sha: earlier_diff_sha, workflow_id: workflow.id)
      end

      it 'rejects the older write no matter which request the DB sees last, never regressing the newer one' do
        expect(newer_service.execute).to be_success
        expect(older_service.execute).to be_error

        expect(merge_request.risk_assessment.reload.diff_sha).to eq(later_diff_sha)
      end
    end

    context 'when no summary is submitted' do
      let(:classification) { { 'claims' => { 'authorization' => { 'value' => 'true' } } } }

      it 'omits summary from the classification handed to the job' do
        expect_next_instance_of(MergeRequests::RiskAssessment) do |assessment|
          expect(assessment).to receive(:enqueue_risk_score_calculation)
            .with(diff_sha, { 'claims' => { 'authorization' => { 'value' => 'true' } } }, workflow.id)
        end

        expect(service.execute).to be_success
      end
    end
  end
end
