# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RunFlowScheduleWorker, feature_category: :code_suggestions do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be_with_reload(:flow_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be_with_reload(:schedule) do
    create(:ai_flow_schedule, flow_trigger: flow_trigger, project: project, description: 'Nightly run')
  end

  let(:options) { {} }
  let(:schedule_id) { schedule.id }

  subject(:perform) { described_class.new.perform(schedule_id, options) }

  shared_examples 'skips execution with a logged error' do |error_message|
    it 'logs an error and does not execute a flow' do
      expect(Gitlab::AppLogger).to receive(:error).with(
        message: 'Failed to execute AI flow schedule',
        schedule_id: schedule_id,
        error_message: error_message
      )
      expect(Ai::FlowTriggers::RunService).not_to receive(:new)

      perform
    end
  end

  describe '#perform' do
    context 'when the schedule does not exist' do
      let(:schedule_id) { non_existing_record_id }

      it_behaves_like 'skips execution with a logged error', 'Schedule not found'
    end

    context 'when the schedule was deactivated after being enqueued' do
      before do
        schedule.update!(active: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Schedule is not active, skipping scheduled run'

      it 'does not record a failure or notify owners' do
        expect(NotificationService).not_to receive(:new)

        expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        # Reactivating recalculates next_run_at, so there is nothing to advance here.
        it 'does not advance next_run_at' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.not_to change { schedule.reload.next_run_at }
          end
        end
      end
    end

    context 'when the schedule has no flow trigger' do
      before do
        allow_next_found_instance_of(Ai::FlowSchedule) do |instance|
          allow(instance).to receive(:flow_trigger).and_return(nil)
        end
      end

      it_behaves_like 'skips execution with a logged error', 'Flow trigger not found for schedule'
    end

    context 'when the project is archived' do
      before do
        project.update!(archived: true)
      end

      it_behaves_like 'skips execution with a logged error', 'Project or ancestors are archived'
    end

    context 'when the project is scheduled for deletion' do
      before do
        allow_next_found_instance_of(Project) do |instance|
          allow(instance).to receive(:deletion_in_progress_or_scheduled_in_hierarchy_chain?).and_return(true)
        end
      end

      it_behaves_like 'skips execution with a logged error',
        'Project, namespace or ancestors are scheduled for deletion'
    end

    context 'when scheduling and next_run_at is in the future' do
      let(:options) { { 'scheduling' => true } }

      before do
        schedule.update_column(:next_run_at, 1.hour.from_now)
      end

      it_behaves_like 'skips execution with a logged error', 'Schedule next run time is in future'
    end

    context 'when the flow trigger is not active' do
      before do
        flow_trigger.update!(active: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Flow trigger is not active, skipping scheduled run'

      it 'does not record a failure or notify owners' do
        expect(NotificationService).not_to receive(:new)

        expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        it 'still advances next_run_at so the schedule resumes normally once reactivated' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.to change { schedule.reload.next_run_at }
          end
        end
      end
    end

    context 'when the schedule is valid and due' do
      let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }
      let(:response) { ServiceResponse.success }

      before do
        allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
        allow(run_service).to receive(:execute).and_return(response)
      end

      it 'runs the flow with scheduled trigger metadata' do
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          project: project,
          flow_trigger: flow_trigger,
          trigger_source: :scheduled,
          flow_schedule: schedule
        ).and_return(run_service)
        expect(run_service).to receive(:execute).with({ event: :scheduled, input: 'Nightly run' })

        perform
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        it 'advances next_run_at before executing' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.to change { schedule.reload.next_run_at }
          end
        end
      end

      context 'when not scheduling (for example a manual retry)' do
        it 'does not advance next_run_at' do
          expect { perform }.not_to change { schedule.reload.next_run_at }
        end
      end

      context 'when the response is wrapped in an array (response, workflow)' do
        let(:workflow) { instance_double(Ai::DuoWorkflows::Workflow) }
        let(:response) { [ServiceResponse.success, workflow] }

        it 'unwraps the response and records success' do
          perform

          expect(schedule.reload.last_run_status).to eq('success')
        end
      end

      context 'when execution succeeds' do
        it 'records success' do
          schedule.update!(consecutive_failure_count: 1, last_run_status: :execution_error)

          perform

          expect(schedule.reload).to have_attributes(
            consecutive_failure_count: 0,
            last_run_status: 'success',
            last_run_error: nil
          )
        end
      end

      context 'when execution returns an error response' do
        let(:response) { ServiceResponse.error(message: 'flow definition invalid') }

        it 'records the failure with the response message' do
          perform

          expect(schedule.reload).to have_attributes(
            last_run_status: 'execution_error',
            last_run_error: 'flow definition invalid',
            consecutive_failure_count: 1
          )
        end

        it 'logs the error' do
          expect(Gitlab::AppLogger).to receive(:error).with(
            message: 'Failed to execute AI flow schedule',
            schedule_id: schedule.id,
            error_message: 'flow definition invalid'
          )

          perform
        end

        it 'notifies owners and maintainers of the failure' do
          expect_next_instance_of(NotificationService) do |service|
            expect(service).to receive(:ai_flow_schedule_failed).with(instance_of(Ai::FlowSchedule))
          end

          perform
        end

        context 'when the response has no message' do
          let(:response) { ServiceResponse.error(message: nil) }

          it 'falls back to a generic error message' do
            perform

            expect(schedule.reload.last_run_error).to eq('Unknown execution error')
          end
        end

        context 'when this failure crosses the consecutive-failure threshold' do
          before do
            schedule.update!(consecutive_failure_count: Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES - 1)
          end

          it 'deactivates the schedule and notifies owners and maintainers' do
            expect_next_instance_of(NotificationService) do |service|
              expect(service).to receive(:ai_flow_schedule_deactivated).with(instance_of(Ai::FlowSchedule))
            end

            perform

            expect(schedule.reload.active).to be(false)
          end
        end
      end

      context 'when the response carries a reason the schedule cannot act on' do
        shared_examples 'skips the run without counting a failure' do |logged_message|
          it 'logs the skip and leaves the failure count untouched' do
            expect(Gitlab::AppLogger).to receive(:error).with(
              message: 'Failed to execute AI flow schedule',
              schedule_id: schedule.id,
              error_message: "#{logged_message}, skipping scheduled run"
            )
            expect(NotificationService).not_to receive(:new)

            expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
          end

          it 'does not deactivate a schedule that is one failure from the threshold' do
            schedule.update!(consecutive_failure_count: Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES - 1)

            perform

            expect(schedule.reload).to have_attributes(active: true, last_run_status: nil)
          end
        end

        context 'when the flow is blocked by a feature flag' do
          let(:response) do
            ServiceResponse.error(
              message: 'flow is disabled by a feature flag',
              reason: :flow_disabled_by_feature_flag
            )
          end

          it_behaves_like 'skips the run without counting a failure', 'flow is disabled by a feature flag'
        end

        context 'when autonomous service account execution is disabled' do
          let(:response) do
            ServiceResponse.error(
              message: 'cannot be triggered by non-human users',
              reason: :non_human_trigger_not_permitted
            )
          end

          it_behaves_like 'skips the run without counting a failure', 'cannot be triggered by non-human users'
        end

        context 'when the namespace has exhausted its AI credits' do
          let(:response) do
            ServiceResponse.error(message: ['Usage quota exceeded'], reason: :usage_quota_exceeded)
          end

          it_behaves_like 'skips the run without counting a failure', 'Usage quota exceeded'
        end
      end

      context 'when execution raises an error' do
        let(:error) { StandardError.new('boom') }

        before do
          allow(run_service).to receive(:execute).and_raise(error)
        end

        it 'records a generic failure message' do
          perform

          expect(schedule.reload.last_run_error).to eq(described_class::UNEXPECTED_ERROR_MESSAGE)
        end

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            error, schedule_id: schedule.id, flow_trigger_id: flow_trigger.id
          )

          perform
        end
      end
    end

    describe 'idempotency' do
      let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }

      before do
        schedule.update!(next_run_at: 1.minute.ago)

        allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
        allow(run_service).to receive(:execute).and_return(ServiceResponse.success)
      end

      context 'with a scheduled run' do
        it_behaves_like 'an idempotent worker' do
          let(:job_args) { [schedule.id, { 'scheduling' => true }] }

          it 'executes the flow once because next_run_at is advanced before execution' do
            expect(run_service).to receive(:execute).once

            perform_idempotent_work
          end
        end
      end

      context 'with a manual run' do
        it_behaves_like 'an idempotent worker' do
          let(:job_args) { [schedule.id, {}] }

          # Without the 'scheduling' flag there is no next_run_at guard, so
          # re-execution is prevented by deduplicate :until_executed, not here.
          it 'executes the flow once per invocation' do
            expect(run_service).to receive(:execute).exactly(worker_exec_times).times

            perform_idempotent_work
          end
        end
      end
    end
  end
end
