# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::SyncFromTriggerService, feature_category: :code_suggestions do
  include ExclusiveLeaseHelpers

  let_it_be(:project) { create(:project) }

  let(:schedule_config) do
    { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14, 'timezone' => 'America/New_York' }
  end

  let(:trigger) do
    create(:ai_flow_trigger,
      project: project,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
      filter: { 'scheduled' => schedule_config })
  end

  let(:service) { described_class.new(trigger: trigger) }

  subject(:execute) { service.execute }

  describe '#execute' do
    context 'when the trigger is nil' do
      let(:service) { described_class.new(trigger: nil) }

      it 'succeeds without creating schedules' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end
    end

    context 'when the ai_flow_schedules feature flag is disabled' do
      before do
        stub_feature_flags(ai_flow_schedules: false)
      end

      it 'succeeds without creating schedules' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end
    end

    context 'when the exclusive lock is already held' do
      before do
        stub_exclusive_lease_taken("ai_flow_schedules:sync_from_trigger:#{trigger.id}")
      end

      it 'returns an error without creating a schedule' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.message).to eq('Could not acquire lock to sync flow schedule')
      end
    end

    context 'when the trigger has the scheduled event type and schedule config' do
      it 'creates a schedule from the config' do
        expect { execute }.to change { Ai::FlowSchedule.count }.by(1)

        expect(execute).to be_success

        schedule = execute.payload[:flow_schedule]
        expect(schedule).to have_attributes(
          project_id: project.id,
          ai_flow_trigger_id: trigger.id,
          cron: '30 14 * * *',
          cron_timezone: 'America/New_York',
          description: trigger.description,
          active: true
        )
        expect(schedule.next_run_at).to be_present
      end

      context 'when the trigger already has a schedule' do
        let!(:existing_schedule) do
          create(:ai_flow_schedule, flow_trigger: trigger, cron: '0 9 * * 1', cron_timezone: 'UTC')
        end

        it 'updates the existing schedule instead of creating a new one' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_success
          expect(existing_schedule.reload).to have_attributes(
            cron: '30 14 * * *',
            cron_timezone: 'America/New_York'
          )
        end

        it 'recalculates next_run_at for the new cron' do
          expect { execute }.to change { existing_schedule.reload.next_run_at }
        end

        context 'when the schedule config is unchanged' do
          let!(:existing_schedule) do
            create(:ai_flow_schedule, flow_trigger: trigger, cron: '30 14 * * *',
              cron_timezone: 'America/New_York')
          end

          it 'preserves next_run_at' do
            expect { execute }.not_to change { existing_schedule.reload.next_run_at }
          end
        end
      end

      context 'when the schedule config is invalid' do
        before do
          # The trigger JSON schema rejects unknown frequencies, so bypass
          # validation to cover rows written before the schema existed.
          trigger.update_column(:filter, { 'scheduled' => { 'frequency' => 'SOMETIMES' } })
        end

        it 'returns the converter error' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_error
          expect(execute.message).to include('Unknown schedule frequency: SOMETIMES')
        end
      end

      context 'when the schedule cannot be saved' do
        before do
          create(:plan_limits, :default_plan, ai_flow_schedules: 1)
          other_trigger = create(:ai_flow_trigger, project: project)
          create(:ai_flow_schedule, flow_trigger: other_trigger)
        end

        it 'returns the validation error' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_error
          expect(execute.message).to include('Maximum number of ai flow schedules (1) exceeded')
        end
      end
    end

    context 'when the trigger has the scheduled event type but no schedule config' do
      let(:trigger) do
        create(:ai_flow_trigger,
          project: project,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          filter: {})
      end

      it 'succeeds without creating or removing schedules' do
        existing_schedule = create(:ai_flow_schedule, flow_trigger: trigger)

        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_success
        expect(existing_schedule.reload).to be_persisted
      end
    end

    context 'when the trigger does not have the scheduled event type' do
      let(:trigger) do
        create(:ai_flow_trigger,
          project: project,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
      end

      it 'removes existing schedules' do
        create(:ai_flow_schedule, flow_trigger: trigger)

        expect { execute }.to change { Ai::FlowSchedule.count }.by(-1)
        expect(execute).to be_success
      end

      it 'succeeds when there is nothing to remove' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end
    end
  end
end
