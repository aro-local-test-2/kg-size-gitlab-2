# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoAgentPlatform::FunctionalVerificationRunService, feature_category: :duo_agent_platform do
  let(:check_type) { :agentic_chat }

  subject(:service) { described_class.new(check_type: check_type) }

  describe '#mark_running' do
    let(:workflow_id) { 123 }

    subject(:mark_running) { service.mark_running(workflow_id: workflow_id) }

    context 'when no run exists yet for the check type' do
      it 'creates a running row for the check type' do
        expect { mark_running }.to change {
          Ai::DuoAgentPlatform::FunctionalVerificationRun.count
        }.by(1)

        run = Ai::DuoAgentPlatform::FunctionalVerificationRun.find_by(check_type: check_type)
        expect(run).to have_attributes(status: 'running', workflow_id: workflow_id, message: nil)
      end
    end

    context 'when a run already exists for the check type' do
      let!(:existing_run) do
        create(:duo_agent_platform_functional_verification_run, :failed, check_type: check_type)
      end

      it 'overwrites the existing row instead of creating a new one' do
        expect { mark_running }.not_to change { Ai::DuoAgentPlatform::FunctionalVerificationRun.count }

        expect(existing_run.reload).to have_attributes(status: 'running', workflow_id: workflow_id, message: nil)
      end
    end
  end

  describe '#mark_completed' do
    let!(:run) do
      create(:duo_agent_platform_functional_verification_run, check_type: check_type)
    end

    subject(:mark_completed) { service.mark_completed(workflow_id: run.workflow_id, status: :passed, message: 'done') }

    it 'updates the row matching the workflow_id and returns true' do
      expect(mark_completed).to be(true)

      expect(run.reload).to have_attributes(status: 'passed', message: 'done')
    end

    it 'truncates an overly long message' do
      service.mark_completed(workflow_id: run.workflow_id, status: :failed, message: 'a' * 2000)

      expect(run.reload.message.length)
        .to eq(Ai::DuoAgentPlatform::FunctionalVerificationRun::MAX_MESSAGE_LENGTH)
    end

    context 'when the run has already been superseded by a newer workflow_id' do
      subject(:mark_completed) do
        service.mark_completed(workflow_id: non_existing_record_id, status: :passed, message: 'done')
      end

      it 'is a no-op and returns false' do
        expect(mark_completed).to be(false)

        expect(run.reload.status).to eq('running')
      end
    end
  end

  describe '#read' do
    subject(:read) { service.read }

    context 'when no row exists for the check type' do
      it 'returns the not_run state' do
        expect(read).to eq(state: described_class::NOT_RUN_STATE)
      end
    end

    context 'when a row exists with a status' do
      let!(:run) do
        create(:duo_agent_platform_functional_verification_run, :passed, check_type: check_type, workflow_id: 123,
          message: nil)
      end

      it 'returns the current state' do
        expect(read).to eq(
          state: 'passed',
          workflow_id: 123,
          message: nil,
          checked_at: run.reload.updated_at
        )
      end
    end

    context 'when the running row is stale past the timeout' do
      let!(:run) do
        travel_to((described_class::RUN_TIMEOUT + described_class::STALE_MARGIN + 1.second).ago) do
          create(:duo_agent_platform_functional_verification_run, check_type: check_type, workflow_id: 123)
        end
      end

      it 'returns a failed state without persisting it' do
        expect(read).to eq(
          state: 'failed',
          workflow_id: 123,
          message: s_('DuoAgentPlatform|Verification check timed out.'),
          checked_at: run.reload.updated_at
        )
        expect(run.reload.status).to eq('running')
      end

      it 'returns failed state on repeated reads without ever persisting it' do
        2.times do
          expect(read).to include(state: 'failed')
          expect(run.reload.status).to eq('running')
        end
      end
    end

    context 'when the running row is not yet stale' do
      let!(:run) do
        create(:duo_agent_platform_functional_verification_run, check_type: check_type, workflow_id: 123)
      end

      it 'returns the running state unchanged' do
        expect(read).to include(state: 'running')
      end
    end
  end
end
