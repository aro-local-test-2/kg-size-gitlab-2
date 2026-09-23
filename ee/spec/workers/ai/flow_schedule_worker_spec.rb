# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowScheduleWorker, feature_category: :code_suggestions do
  include ExclusiveLeaseHelpers

  subject(:perform) { described_class.new.perform }

  let_it_be(:project) { create(:project) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }

  let!(:due_schedule) do
    create(:ai_flow_schedule, flow_trigger: flow_trigger, project: project).tap do |schedule|
      schedule.update_column(:next_run_at, 1.minute.ago)
    end
  end

  shared_examples 'excludes the schedule from the batch' do
    it 'does not enqueue a run worker for it' do
      expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts) do |_delay, schedules, **|
        expect(schedules).to contain_exactly(due_schedule)
      end

      perform
    end
  end

  it 'enqueues a run worker for the due schedule' do
    expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts).with(
      1, [due_schedule], arguments_proc: instance_of(Proc), context_proc: instance_of(Proc)
    )

    perform
  end

  it 'builds job arguments carrying the schedule id and the scheduling flag' do
    expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts) do |_delay, schedules, **procs|
      expect(procs[:arguments_proc].call(schedules.first)).to match_array([due_schedule.id, { 'scheduling' => true }])
    end

    perform
  end

  it 'builds a logging context from the schedule project' do
    expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts) do |_delay, schedules, **procs|
      expect(procs[:context_proc].call(schedules.first)).to eq(project: project)
    end

    perform
  end

  context 'when the schedule is not due yet' do
    let!(:future_schedule) do
      create(:ai_flow_schedule, flow_trigger: flow_trigger, project: project)
    end

    it_behaves_like 'excludes the schedule from the batch'
  end

  context 'when the schedule is inactive' do
    let!(:inactive_schedule) do
      create(:ai_flow_schedule, :inactive, flow_trigger: flow_trigger, project: project).tap do |schedule|
        schedule.update_column(:next_run_at, 1.minute.ago)
      end
    end

    it_behaves_like 'excludes the schedule from the batch'
  end

  context 'when another instance already holds the lock' do
    let!(:lease) { stub_exclusive_lease_taken(described_class.name.underscore) }

    it 'does not enqueue any run workers' do
      expect(lease).to receive(:try_obtain).exactly(described_class::LOCK_RETRY + 1).times
      expect(Ai::RunFlowScheduleWorker).not_to receive(:bulk_perform_in_with_contexts)

      expect { perform }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    end
  end

  context 'with scheduling delay across batches' do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 1)
    end

    let!(:other_due_schedule) do
      create(:ai_flow_schedule, flow_trigger: flow_trigger, project: project).tap do |schedule|
        schedule.update_column(:next_run_at, 2.minutes.ago)
      end
    end

    it 'delays later batches by DELAY * batch index' do
      expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts)
        .with(1, [due_schedule], arguments_proc: instance_of(Proc), context_proc: instance_of(Proc))
      expect(Ai::RunFlowScheduleWorker).to receive(:bulk_perform_in_with_contexts)
        .with(described_class::DELAY, [other_due_schedule], arguments_proc: instance_of(Proc),
          context_proc: instance_of(Proc))

      perform
    end
  end

  context 'when the ai_flow_schedules feature flag is disabled' do
    before do
      stub_feature_flags(ai_flow_schedules: false)
    end

    it 'does not enqueue any run workers' do
      expect(Ai::RunFlowScheduleWorker).not_to receive(:bulk_perform_in_with_contexts)

      perform
    end
  end
end
