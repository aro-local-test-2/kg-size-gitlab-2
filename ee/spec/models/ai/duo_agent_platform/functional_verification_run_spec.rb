# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoAgentPlatform::FunctionalVerificationRun, feature_category: :duo_agent_platform do
  subject(:run) { build(:duo_agent_platform_functional_verification_run) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:check_type) }
    it { is_expected.to validate_uniqueness_of(:workflow_id).allow_nil }
    it { is_expected.to validate_length_of(:message).is_at_most(described_class::MAX_MESSAGE_LENGTH) }

    it 'requires a message when the run has failed' do
      run = build(:duo_agent_platform_functional_verification_run, status: :failed, message: nil)

      expect(run).to be_invalid
      expect(run.errors[:message]).to include("can't be blank")
    end

    # Not `validate_uniqueness_of`: that matcher mutates the value to probe case
    # sensitivity, which an enum column rejects outright.
    it 'rejects a second run for a check type that already has one' do
      create(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat)
      duplicate = build(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat)

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:check_type]).to include('has already been taken')
    end

    it 'rejects a second run for a workflow that already has one' do
      run = create(:duo_agent_platform_functional_verification_run)
      duplicate = build(:duo_agent_platform_functional_verification_run, workflow_id: run.workflow_id)

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:workflow_id]).to include('has already been taken')
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:check_type).with_values(described_class::CHECK_TYPES) }
    it { is_expected.to define_enum_for(:status).with_values(described_class::STATUSES) }
  end

  describe 'the unique index on check_type' do
    let_it_be(:existing) { create(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat) }

    # The model validation alone does not prove the database constraint exists.
    it 'rejects a second row for the same check type' do
      duplicate = build(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'the unique index on workflow_id' do
    let_it_be(:existing) { create(:duo_agent_platform_functional_verification_run) }

    # The model validation alone does not prove the database constraint exists.
    # CHECK_TYPES only defines one value today, so this row also collides on
    # check_type; either unique index raising RecordNotUnique proves the DB
    # still rejects the insert.
    it 'rejects a second row for the same workflow' do
      duplicate = build(:duo_agent_platform_functional_verification_run, workflow_id: existing.workflow_id)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'the outcome folded into status' do
    it 'reports a passing run' do
      run = build(:duo_agent_platform_functional_verification_run, :passed)

      expect(run).to be_passed
      expect(run).not_to be_failed
    end

    it 'reports a failing run, keeping the detail in the message' do
      run = build(:duo_agent_platform_functional_verification_run, :failed)

      expect(run).to be_failed
      expect(run.message).to include('internal_error')
    end
  end

  describe '.current_for' do
    it 'returns the row for the given check type' do
      run = create(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat)

      expect(described_class.current_for(:agentic_chat)).to eq(run)
    end

    it 'returns nil when no row exists for the check type' do
      expect(described_class.current_for(:agentic_chat)).to be_nil
    end
  end

  describe '.current_for_workflow' do
    it 'returns the row for the given workflow_id' do
      run = create(:duo_agent_platform_functional_verification_run)

      expect(described_class.current_for_workflow(run.workflow_id)).to eq(run)
    end

    it 'returns nil when no row exists for the workflow_id' do
      expect(described_class.current_for_workflow(non_existing_record_id)).to be_nil
    end
  end

  describe '.start_run' do
    context 'when no row exists yet for the check type' do
      it 'creates a running row with the given workflow_id' do
        run = described_class.start_run(:agentic_chat, workflow_id: 123)

        expect(run).to have_attributes(status: 'running', workflow_id: 123, message: nil)
      end
    end

    context 'when a row already exists for the check type' do
      let!(:existing) { create(:duo_agent_platform_functional_verification_run, :failed, check_type: :agentic_chat) }

      it 'overwrites the existing row instead of creating a new one' do
        expect { described_class.start_run(:agentic_chat, workflow_id: 456) }
          .not_to change { described_class.count }

        expect(existing.reload).to have_attributes(status: 'running', workflow_id: 456, message: nil)
      end
    end
  end

  describe '.complete_run' do
    let!(:run) { create(:duo_agent_platform_functional_verification_run, check_type: :agentic_chat) }

    it 'updates the row matching the workflow_id and returns true' do
      result = described_class.complete_run(
        check_type: :agentic_chat, workflow_id: run.workflow_id, status: :passed, message: 'done'
      )

      expect(result).to be(true)
      expect(run.reload).to have_attributes(status: 'passed', message: 'done')
    end

    it 'truncates an overly long message' do
      described_class.complete_run(
        check_type: :agentic_chat, workflow_id: run.workflow_id, status: :failed, message: 'a' * 2000
      )

      expect(run.reload.message.length).to eq(described_class::MAX_MESSAGE_LENGTH)
    end

    context 'when the run has already been superseded by a newer workflow_id' do
      it 'is a no-op and returns false' do
        result = described_class.complete_run(
          check_type: :agentic_chat, workflow_id: non_existing_record_id, status: :passed, message: 'done'
        )

        expect(result).to be(false)
        expect(run.reload.status).to eq('running')
      end
    end

    context 'when the run has already timed out' do
      let!(:run) { create(:duo_agent_platform_functional_verification_run, :failed, check_type: :agentic_chat) }

      it 'is a no-op and does not overwrite the timed-out result' do
        result = described_class.complete_run(
          check_type: :agentic_chat, workflow_id: run.workflow_id, status: :passed, message: 'done'
        )

        expect(result).to be(false)
        expect(run.reload.status).to eq('failed')
      end
    end

    context 'when status is failed and message is blank' do
      it 'raises ArgumentError' do
        expect do
          described_class.complete_run(
            check_type: :agentic_chat, workflow_id: run.workflow_id, status: :failed, message: nil
          )
        end.to raise_error(ArgumentError, 'message is required when status is failed')
      end
    end
  end
end
