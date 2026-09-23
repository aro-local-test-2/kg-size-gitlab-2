# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RiskClassification::TimeoutWorker, feature_category: :duo_code_review do
  let_it_be(:merge_request) { create(:merge_request) }

  describe '.enqueue' do
    it 'schedules a job a full window out, so the flow has the whole run to report back' do
      freeze_time do
        expect { described_class.enqueue(merge_request.id) }.to change { described_class.jobs.size }.by(1)

        job = described_class.jobs.last
        expect(job['args']).to eq([merge_request.id])
        expect(job['at']).to eq(described_class::TIMEOUT_DURATION.from_now.to_f)
      end
    end
  end

  describe '#perform' do
    subject(:perform) do
      travel_to(described_class::TIMEOUT_DURATION.from_now + 1.minute) do
        described_class.new.perform(merge_request.id)
      end
    end

    it 'fails an assessment the flow never reported back on' do
      assessment = create(:merge_requests_risk_assessment, :pending, merge_request: merge_request)

      perform

      expect(assessment.reload).to be_failed
    end

    it 'fails an assessment whose scoring never completed' do
      assessment = create(:merge_requests_risk_assessment, :queued, merge_request: merge_request)

      perform

      expect(assessment.reload).to be_failed
    end

    it 'leaves a completed assessment alone' do
      assessment = create(:merge_requests_risk_assessment, :complete, merge_request: merge_request)

      perform

      expect(assessment.reload).to be_complete
    end

    it 'schedules nothing for a scored assessment, so a completed row stops waking the timer' do
      create(:merge_requests_risk_assessment, :complete, merge_request: merge_request)

      expect(described_class).not_to receive(:perform_in)

      travel_to(described_class::TIMEOUT_DURATION.from_now - 10.minutes) do
        described_class.new.perform(merge_request.id)
      end
    end

    context 'when the assessment was touched inside the window' do
      let!(:assessment) { create(:merge_requests_risk_assessment, :queued, merge_request: merge_request) }

      subject(:perform_early) do
        travel_to(described_class::TIMEOUT_DURATION.from_now - 10.minutes) do
          described_class.new.perform(merge_request.id)
        end
      end

      it 'leaves it alone, so a stale timer cannot fail a fresh classification' do
        perform_early

        expect(assessment.reload).to be_queued
      end

      it 'defers itself to the end of the idle window the row now has' do
        expect(described_class).to receive(:perform_in) do |delay, merge_request_id|
          expect(delay).to be_within(1.minute).of(10.minutes)
          expect(merge_request_id).to eq(merge_request.id)
        end

        perform_early
      end
    end

    it 'logs the timeout so a dead flow is visible without querying' do
      create(:merge_requests_risk_assessment, :pending, merge_request: merge_request)

      expect(Gitlab::AppLogger).to receive(:warn).with(
        hash_including(message: 'Risk classification timed out', merge_request_id: merge_request.id)
      )

      perform
    end

    it 'does nothing when the merge request has no assessment' do
      expect(Gitlab::AppLogger).not_to receive(:warn)

      expect { perform }.not_to raise_error
    end

    it 'does nothing when the merge request is gone' do
      expect { described_class.new.perform(non_existing_record_id) }.not_to raise_error
    end

    it 'does not fail an assessment that completes elsewhere while this worker is deciding' do
      assessment = create(:merge_requests_risk_assessment, :queued, merge_request: merge_request)

      # Simulates CalculateScoreWorker completing the row in between this worker's
      # initial (unlocked) read and the row lock #perform now takes before acting.
      allow_next_found_instance_of(MergeRequests::RiskAssessment) do |instance|
        allow(instance).to receive(:with_lock).and_wrap_original do |original, *args, &block|
          MergeRequests::RiskAssessment.find(assessment.id).finish
          original.call(*args, &block)
        end
      end

      perform

      expect(assessment.reload).to be_complete
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [merge_request.id] }
      # :complete rather than :queued: a queued row still inside its window makes
      # #perform reschedule a real perform_in call, which under Sidekiq::Testing.inline!
      # re-enters #perform synchronously - unrelated to idempotency, so avoided here.
      let!(:assessment) { create(:merge_requests_risk_assessment, :complete, merge_request: merge_request) }
    end
  end
end
