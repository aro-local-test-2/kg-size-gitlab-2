# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::RiskAssessment, feature_category: :duo_code_review do
  using RSpec::Parameterized::TableSyntax

  describe 'associations' do
    it { is_expected.to belong_to(:merge_request).required }
    it { is_expected.to belong_to(:duo_workflow).optional }
    it { is_expected.to have_many(:risk_outcomes).class_name('MergeRequests::RiskOutcome') }
  end

  describe 'state machine' do
    let_it_be(:merge_request) { create(:merge_request) }
    let_it_be(:earlier_diff) do
      create(:merge_request_diff, merge_request: merge_request,
        head_commit_sha: Digest::SHA1.hexdigest(SecureRandom.hex)) # rubocop:disable Fips/SHA1 -- test data
    end

    let_it_be(:later_diff) do
      earlier_diff
      create(:merge_request_diff, merge_request: merge_request,
        head_commit_sha: Digest::SHA1.hexdigest(SecureRandom.hex)) # rubocop:disable Fips/SHA1 -- test data
    end

    let(:workflow_id) { 99 }

    describe '#enqueue' do
      it 'queues a pending assessment and schedules its timeout' do
        assessment = create(:merge_requests_risk_assessment, :pending, merge_request: merge_request)

        expect(assessment).to receive(:enqueue_timeout)

        expect(assessment.enqueue).to be(true)
        expect(assessment).to be_queued
      end

      %i[complete failed].each do |from_state|
        it "queues a #{from_state} assessment again, so the new run gets its own timeout" do
          assessment = create(:merge_requests_risk_assessment, from_state, merge_request: merge_request)

          expect(assessment).to receive(:enqueue_timeout)

          expect(assessment.enqueue).to be(true)
          expect(assessment).to be_queued
        end
      end

      it 'refuses an assessment already queued, so a run in flight keeps a single timer' do
        assessment = create(:merge_requests_risk_assessment, :queued, merge_request: merge_request)

        expect(assessment).not_to receive(:enqueue_timeout)

        expect(assessment.enqueue).to be(false)
        expect(assessment).to be_queued
      end
    end

    describe '#refresh' do
      let(:diff_sha) { earlier_diff.head_commit_sha }
      let(:classification) { { 'claims' => {}, 'summary' => 'Looks fine.' } }
      let(:risk_assessment) do
        create(:merge_requests_risk_assessment, merge_request: merge_request, diff_sha: diff_sha)
      end

      it 'transitions to queued and passes the event args to the risk score calculation' do
        expect(risk_assessment).to receive(:enqueue_risk_score_calculation).with(diff_sha, classification, workflow_id)

        risk_assessment.refresh(diff_sha, classification, workflow_id)

        expect(risk_assessment).to be_queued
      end

      it 'leaves diff_sha and classification for the enqueued job to write' do
        original_diff_sha = risk_assessment.diff_sha

        risk_assessment.refresh(later_diff.head_commit_sha, classification)

        expect(risk_assessment.diff_sha).to eq(original_diff_sha)
        expect(risk_assessment.classification).to eq({})
      end

      %i[pending queued complete].each do |from_state|
        context "when the assessment is #{from_state}" do
          let(:risk_assessment) do
            create(:merge_requests_risk_assessment, from_state, merge_request: merge_request, diff_sha: diff_sha)
          end

          it 'transitions to queued and enqueues the risk score calculation' do
            expect(risk_assessment).to receive(:enqueue_risk_score_calculation).with(diff_sha, classification,
              workflow_id)

            expect(risk_assessment.refresh(diff_sha, classification, workflow_id)).to be(true)
            expect(risk_assessment).to be_queued
          end
        end
      end

      context 'when a previous attempt failed' do
        let(:risk_assessment) do
          create(:merge_requests_risk_assessment, :failed, merge_request: merge_request, diff_sha: diff_sha)
        end

        it 'transitions to queued and enqueues the risk score calculation' do
          expect(risk_assessment).to receive(:enqueue_risk_score_calculation).with(diff_sha, classification,
            workflow_id)

          expect(risk_assessment.refresh(diff_sha, classification, workflow_id)).to be(true)
          expect(risk_assessment).to be_queued
        end
      end

      context 'when the incoming revision is older than the current one' do
        let(:risk_assessment) do
          create(:merge_requests_risk_assessment, merge_request: merge_request,
            diff_sha: later_diff.head_commit_sha)
        end

        it 'is refused by the guard, so nothing is enqueued' do
          expect(risk_assessment).not_to receive(:enqueue_risk_score_calculation)

          expect(risk_assessment.refresh(earlier_diff.head_commit_sha, classification, workflow_id)).to be(false)
          expect(risk_assessment).to be_pending
        end
      end
    end

    describe '#finish' do
      it 'completes a queued assessment' do
        assessment = create(:merge_requests_risk_assessment, :queued, merge_request: merge_request)

        expect(assessment.finish).to be(true)
        expect(assessment).to be_complete
      end

      it 'refuses to complete an assessment that was never queued' do
        assessment = create(:merge_requests_risk_assessment, :pending, merge_request: merge_request)

        expect(assessment.finish).to be(false)
        expect(assessment).to be_pending
      end
    end

    describe '#mark_failed' do
      it 'fails an assessment still waiting on a result' do
        assessment = create(:merge_requests_risk_assessment, :queued, merge_request: merge_request)

        expect(assessment.mark_failed).to be(true)
        expect(assessment).to be_failed
      end

      it 'leaves a completed assessment alone' do
        assessment = create(:merge_requests_risk_assessment, :complete, merge_request: merge_request)

        expect(assessment.mark_failed).to be(false)
        expect(assessment).to be_complete
      end
    end

    describe '#enqueue_timeout' do
      let(:assessment) { create(:merge_requests_risk_assessment, :queued, merge_request: merge_request) }

      it 'defers the timeout job until after the transaction commits' do
        expect(assessment).to receive(:run_after_commit)

        assessment.enqueue_timeout
      end

      it 'hands the job the merge request the timer watches' do
        allow(assessment).to receive(:run_after_commit).and_yield

        expect(Ai::RiskClassification::TimeoutWorker).to receive(:enqueue).with(merge_request.id)

        assessment.enqueue_timeout
      end
    end

    describe '#enqueue_risk_score_calculation' do
      let(:assessment) { create(:merge_requests_risk_assessment, :queued, merge_request: merge_request) }

      it 'defers the scoring job until after the transaction commits' do
        expect(assessment).to receive(:run_after_commit)

        assessment.enqueue_risk_score_calculation('abc', { 'claims' => {} }, 7)
      end

      it 'hands the job the revision, the claims and the session' do
        allow(assessment).to receive(:run_after_commit).and_yield

        expect(Ai::RiskClassification::CalculateScoreWorker).to receive(:perform_async)
          .with(assessment.merge_request_id, 'abc', { 'claims' => {} }, 7)

        assessment.enqueue_risk_score_calculation('abc', { 'claims' => {} }, 7)
      end
    end

    describe '#refreshable_for?' do
      let(:risk_assessment) do
        create(:merge_requests_risk_assessment, merge_request: merge_request,
          diff_sha: earlier_diff.head_commit_sha)
      end

      it 'accepts a later revision' do
        expect(risk_assessment.refreshable_for?(later_diff.head_commit_sha)).to be(true)
      end

      it 'accepts the same revision, so a retried submission still lands' do
        expect(risk_assessment.refreshable_for?(earlier_diff.head_commit_sha)).to be(true)
      end

      it 'refuses an earlier revision' do
        risk_assessment.update!(diff_sha: later_diff.head_commit_sha)

        expect(risk_assessment.refreshable_for?(earlier_diff.head_commit_sha)).to be(false)
      end

      it 'refuses a revision that is not in the merge request history' do
        unknown_sha = Digest::SHA1.hexdigest(SecureRandom.hex) # rubocop:disable Fips/SHA1 -- test data

        expect(risk_assessment.refreshable_for?(unknown_sha)).to be(false)
      end

      it 'fails open when the current diff_sha no longer resolves to a revision' do
        risk_assessment.update!(diff_sha: Digest::SHA1.hexdigest(SecureRandom.hex)) # rubocop:disable Fips/SHA1 -- pruned diff

        expect(risk_assessment.refreshable_for?(earlier_diff.head_commit_sha)).to be(true)
      end

      it 'accepts a revision that was force-pushed back to, since it is current again' do
        risk_assessment.update!(diff_sha: later_diff.head_commit_sha)
        create(:merge_request_diff, merge_request: merge_request, head_commit_sha: earlier_diff.head_commit_sha)

        expect(risk_assessment.refreshable_for?(earlier_diff.head_commit_sha)).to be(true)
      end
    end
  end

  describe '.ensure_for!' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project) }

    it 'records the revision the run will be assessed against' do
      assessment = described_class.ensure_for!(merge_request)

      expect(assessment).to be_pending
      expect(assessment.diff_sha).to eq(merge_request.diff_head_sha)
    end

    it 'reuses the row a previous run recorded' do
      existing = create(:merge_requests_risk_assessment, :complete, merge_request: merge_request)

      expect { described_class.ensure_for!(merge_request) }.not_to change { described_class.count }
      expect(described_class.ensure_for!(merge_request)).to eq(existing)
    end

    context 'when a concurrent run records the row first' do
      before do
        allow(merge_request).to receive(:create_risk_assessment!) do
          create(:merge_requests_risk_assessment, merge_request_id: merge_request.id, project_id: project.id)
          raise ActiveRecord::RecordNotUnique, 'duplicate key'
        end
      end

      it 'reads that row rather than failing the run' do
        expect(described_class.ensure_for!(merge_request)).to eq(merge_request.reload.risk_assessment)
      end
    end

    context 'when the failure is not a race' do
      before do
        allow(merge_request).to receive(:create_risk_assessment!).and_raise(ActiveRecord::RecordNotUnique)
      end

      it 'raises, so a real write failure is not read as a duplicate' do
        expect { described_class.ensure_for!(merge_request) }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe 'sharding key' do
    let_it_be(:merge_request) { create(:merge_request) }

    subject { build(:merge_requests_risk_assessment, merge_request: merge_request, project_id: nil) }

    it { is_expected.to populate_sharding_key(:project_id).with(merge_request.project_id) }

    context 'when project_id cannot be derived' do
      let(:risk_assessment) { build(:merge_requests_risk_assessment, merge_request: nil, project_id: nil) }

      it 'is invalid' do
        expect(risk_assessment).to be_invalid
        expect(risk_assessment.errors[:project_id]).to include("can't be blank")
      end
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:diff_sha) }
    it { is_expected.to validate_length_of(:diff_sha).is_at_most(64) }
    it { is_expected.to validate_length_of(:scoring_function_version).is_at_most(20) }
    it { is_expected.to validate_length_of(:rationale).is_at_most(2048) }

    it { is_expected.to allow_value(nil, 0, 50, 100).for(:score) }
    it { is_expected.not_to allow_value(-1, 101).for(:score) }
    it { is_expected.to allow_value(nil, 0, 50, 100).for(:confidence) }
    it { is_expected.not_to allow_value(-1, 101).for(:confidence) }

    describe 'merge_request_id uniqueness' do
      let_it_be(:existing) { create(:merge_requests_risk_assessment) }

      it 'rejects a second assessment for the same merge request' do
        duplicate = build(:merge_requests_risk_assessment, merge_request: existing.merge_request)

        expect(duplicate).to be_invalid
        expect(duplicate.errors[:merge_request_id]).to include('has already been taken')
      end
    end

    describe 'classification' do
      let(:risk_assessment) { build(:merge_requests_risk_assessment) }

      let(:classification) do
        { verdict: 'low_risk' }
      end

      before do
        risk_assessment.classification = classification
      end

      it 'matches the classification json schema' do
        expect(risk_assessment.classification.as_json).to match_schema(
          Rails.root.join('ee/app/validators/json_schemas/merge_requests_risk_assessment_classification.json')
        )
      end

      context 'when not an object' do
        let(:classification) { 'not-an-object' }

        it 'is invalid' do
          expect(risk_assessment).not_to be_valid
          expect(risk_assessment.errors[:classification]).to be_present
        end
      end

      context 'when it exceeds the size limit' do
        let(:classification) { { verdict: 'a' * 64.kilobytes } }

        it 'is invalid' do
          expect(risk_assessment).not_to be_valid
          expect(risk_assessment.errors[:classification]).to include(/is too large/)
        end
      end
    end

    describe 'signal_breakdown' do
      let(:risk_assessment) { build(:merge_requests_risk_assessment) }

      let(:signal_breakdown) do
        [{ signal: 'large_diff' }]
      end

      before do
        risk_assessment.signal_breakdown = signal_breakdown
      end

      it 'matches the signal_breakdown json schema' do
        expect(risk_assessment.signal_breakdown.as_json).to match_schema(
          Rails.root.join('ee/app/validators/json_schemas/merge_requests_risk_assessment_signal_breakdown.json')
        )
      end

      context 'when not an array' do
        let(:signal_breakdown) { { signal: 'large_diff' } }

        it 'is invalid' do
          expect(risk_assessment).not_to be_valid
          expect(risk_assessment.errors[:signal_breakdown]).to be_present
        end
      end

      context 'when it exceeds the size limit' do
        let(:signal_breakdown) { [{ signal: 'a' * 64.kilobytes }] }

        it 'is invalid' do
          expect(risk_assessment).not_to be_valid
          expect(risk_assessment.errors[:signal_breakdown]).to include(/is too large/)
        end
      end
    end
  end

  describe '#risk_tier' do
    let(:assessment) { build(:merge_requests_risk_assessment) }

    where(:score, :tier) do
      nil | nil
      5   | :low
      35  | :medium
      60  | :high
      85  | :critical
    end

    with_them do
      it 'derives the tier from the score via Thresholds' do
        assessment.score = score
        expect(assessment.risk_tier).to eq(tier)
      end
    end
  end

  describe '#confidence_tier' do
    let(:assessment) { build(:merge_requests_risk_assessment) }

    where(:confidence, :tier) do
      nil | nil
      5   | :low
      35  | :medium
      60  | :high
      85  | :critical
    end

    with_them do
      it 'derives the tier from the score via Thresholds' do
        assessment.confidence = confidence
        expect(assessment.confidence_tier).to eq(tier)
      end
    end
  end
end
