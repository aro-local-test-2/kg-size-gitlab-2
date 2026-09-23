# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RiskClassification::CalculateScoreWorker, feature_category: :duo_code_review do
  let_it_be(:merge_request) { create(:merge_request) }

  let(:diff_sha) { merge_request.diff_head_sha }
  let(:classification) do
    {
      'claims' => {
        'authorization' => { 'value' => 'true', 'evidence' => 'app/policies/project_policy.rb:42' },
        'api_contract' => { 'value' => 'false' }
      },
      'summary' => 'Adds a session token refresh path.'
    }
  end

  let(:workflow) do
    create(:duo_workflows_workflow, project: merge_request.target_project,
      user: merge_request.author, merge_request: merge_request)
  end

  let!(:assessment) do
    create(:merge_requests_risk_assessment, :queued, merge_request: merge_request, diff_sha: diff_sha)
  end

  subject(:perform) { described_class.new.perform(merge_request.id, diff_sha, classification, workflow.id) }

  context 'when assessment is queued' do
    before do
      perform
      assessment.reload
    end

    it 'updates the assessment score and metadata', :aggregate_failures do
      expect(assessment).to be_complete
      expect(assessment.score).to be_between(0, 100)
      expect(assessment.confidence).to be_between(0, 100)
      expect(assessment.scoring_function_version).to eq('v1')
      expect(assessment.assessed_at).to be_present
      expect(assessment.classification).to eq(classification)
      expect(assessment.rationale).to eq('Adds a session token refresh path.')
      expect(assessment.duo_workflow_id).to eq(workflow.id)
      expect(assessment.diff_sha).to eq(diff_sha)
      expect(assessment.missing_signals).to be_present
      expect(assessment.signal_breakdown.pluck('signal')).to include('authorization')
    end
  end

  context 'when the assessment is no longer queued' do
    before do
      assessment.mark_failed
    end

    it 'leaves the row as it stands rather than half-applying a score' do
      perform

      expect(assessment.reload).to be_failed
      expect(assessment.score).to be_nil
    end

    it 'logs the discarded score, so a timed-out flow that came back is visible' do
      expect(Gitlab::AppLogger).to receive(:warn).with(
        hash_including(
          message: 'Risk classification score arrived for an assessment that is not queued',
          merge_request_id: merge_request.id,
          status: :failed
        )
      )

      perform
    end
  end

  context 'when the merge request does not exist' do
    it 'does not raise errors' do
      expect do
        described_class.new.perform(non_existing_record_id, diff_sha, classification, workflow.id)
      end.not_to raise_error
    end
  end

  context 'when the assessment does not exist' do
    it 'does not raise errors' do
      assessment.destroy!

      expect { perform }.not_to raise_error
    end
  end

  it 'does not complete an assessment that failed elsewhere while this worker is deciding' do
    # Simulates TimeoutWorker failing the row in between this worker's initial
    # (unlocked) read and the row lock #perform now takes before acting.
    allow_next_found_instance_of(MergeRequests::RiskAssessment) do |instance|
      allow(instance).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        MergeRequests::RiskAssessment.find(assessment.id).mark_failed
        original.call(*args, &block)
      end
    end

    perform

    expect(assessment.reload).to be_failed
    expect(assessment.score).to be_nil
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [merge_request.id, diff_sha, classification, workflow.id] }
  end

  describe 'domain tags' do
    it 'tags only the domains a claim answered positively' do
      perform

      expect(assessment.reload.domain_tags).to contain_exactly('authorization')
    end

    it 'tags nothing when no domain was touched' do
      described_class.new.perform(
        merge_request.id, diff_sha,
        { 'claims' => { 'authorization' => { 'value' => 'false' } }, 'summary' => 'Typo fix.' },
        workflow.id
      )

      expect(assessment.reload.domain_tags).to be_empty
    end
  end
end
