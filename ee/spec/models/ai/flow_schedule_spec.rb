# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedule, feature_category: :code_suggestions do
  let_it_be(:project) { create(:project) }

  describe 'associations' do
    it { is_expected.to belong_to(:project).required }
    it { is_expected.to belong_to(:flow_trigger).class_name('Ai::FlowTrigger').required }
  end

  describe 'validations' do
    subject { build(:ai_flow_schedule) }

    it { is_expected.to validate_presence_of(:cron) }
    it { is_expected.to validate_length_of(:cron).is_at_most(255) }
    it { is_expected.to validate_presence_of(:cron_timezone) }
    it { is_expected.to validate_length_of(:cron_timezone).is_at_most(255) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_length_of(:description).is_at_most(255) }

    describe 'cron_expression_valid' do
      it 'is valid with a correct cron expression' do
        schedule = build(:ai_flow_schedule, cron: '0 9 * * 1', cron_timezone: 'UTC')

        expect(schedule).to be_valid
      end

      it 'is invalid with an incorrect cron expression' do
        schedule = build(:ai_flow_schedule, cron: 'invalid', cron_timezone: 'UTC')

        expect(schedule).not_to be_valid
        expect(schedule.errors[:cron]).to include('syntax is invalid')
      end

      it 'is invalid with an incorrect timezone' do
        schedule = build(:ai_flow_schedule, cron: '0 9 * * 1', cron_timezone: 'InvalidTZ')

        expect(schedule).not_to be_valid
      end
    end

    describe 'flow_trigger_project_matches' do
      it 'is valid when the project matches the flow trigger project' do
        schedule = build(:ai_flow_schedule, flow_trigger: create(:ai_flow_trigger))

        expect(schedule).to be_valid
      end

      it 'is invalid when the project does not match the flow trigger project', :aggregate_failures do
        schedule = build(:ai_flow_schedule, flow_trigger: create(:ai_flow_trigger), project: create(:project))

        expect(schedule).not_to be_valid
        expect(schedule.errors[:base]).to include('flow_trigger project does not match project')
      end
    end
  end

  describe 'enums' do
    it 'defines last_run_status' do
      is_expected.to define_enum_for(:last_run_status)
        .with_values(success: 0, sa_invalid: 1, execution_error: 2)
        .with_prefix(:last_run)
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active schedules' do
        active = create(:ai_flow_schedule)
        create(:ai_flow_schedule, :inactive)

        expect(described_class.active).to contain_exactly(active)
      end
    end

    describe '.runnable_schedules' do
      it 'returns only active schedules that are due to run' do
        due = create(:ai_flow_schedule)
        due.update!(next_run_at: 1.minute.ago)
        create(:ai_flow_schedule) # future next_run_at
        due_but_inactive = create(:ai_flow_schedule, :inactive)
        due_but_inactive.update!(next_run_at: 1.minute.ago)

        expect(described_class.runnable_schedules).to contain_exactly(due)
      end

      it 'excludes a schedule whose next_run_at is exactly now' do
        schedule = create(:ai_flow_schedule)

        freeze_time do
          schedule.update!(next_run_at: Time.zone.now)

          expect(described_class.runnable_schedules).not_to include(schedule)
        end
      end

      it 'excludes a schedule with no next_run_at' do
        schedule = create(:ai_flow_schedule)
        schedule.update!(next_run_at: nil)

        expect(described_class.runnable_schedules).not_to include(schedule)
      end
    end

    describe '.preload_project_route' do
      it 'returns the schedules unfiltered' do
        schedule = create(:ai_flow_schedule)

        expect(described_class.preload_project_route).to contain_exactly(schedule)
      end

      it 'preloads the project and its route to avoid N+1 queries' do
        access = ->(schedule) { schedule.project.full_path }

        create(:ai_flow_schedule)
        create(:ai_flow_schedule)

        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          described_class.preload_project_route.each(&access)
        end

        create(:ai_flow_schedule)

        actual = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          described_class.preload_project_route.each(&access)
        end

        expect(actual.count).to eq(control.count)
      end
    end
  end

  describe 'Schedulable integration' do
    it 'sets next_run_at on create' do
      schedule = create(:ai_flow_schedule)

      expect(schedule.next_run_at).to be_future
    end

    it 'snaps next_run_at to the dispatcher worker cadence', time_travel_to: '2026-08-05 12:00:00 UTC' do
      schedule = create(:ai_flow_schedule, cron: '0 9 * * 1', cron_timezone: 'UTC')

      expect(schedule.next_run_at).to eq(Time.zone.parse('2026-08-10 09:03:00 UTC'))
    end
  end

  describe '#allow_next_run_at_update?' do
    let(:schedule) { create(:ai_flow_schedule) }

    it 'returns true when cron changes' do
      schedule.cron = '0 10 * * *'

      expect(schedule.allow_next_run_at_update?).to be true
    end

    it 'returns true when cron_timezone changes' do
      schedule.cron_timezone = 'America/New_York'

      expect(schedule.allow_next_run_at_update?).to be true
    end

    it 'returns true when activated from inactive' do
      schedule.update_column(:active, false)
      schedule.active = true

      expect(schedule.allow_next_run_at_update?).to be true
    end

    it 'returns false when only description changes' do
      schedule.description = 'new description'

      expect(schedule.allow_next_run_at_update?).to be false
    end
  end

  describe 'next_run_at recalculation on save (design decision D8)' do
    let_it_be_with_reload(:schedule) { create(:ai_flow_schedule) }

    it 'recalculates next_run_at when cron changes' do
      expect { schedule.update!(cron: '0 22 * * *') }.to change { schedule.next_run_at }
    end

    it 'recalculates next_run_at when cron_timezone changes' do
      expect { schedule.update!(cron_timezone: 'America/New_York') }.to change { schedule.next_run_at }
    end

    it 'recalculates next_run_at when reactivated' do
      schedule.update!(active: false)
      schedule.update_column(:next_run_at, nil)

      schedule.update!(active: true)

      expect(schedule.reload.next_run_at).to be_future
    end

    it 'preserves next_run_at when unrelated attributes change' do
      schedule.update_column(:next_run_at, nil)

      schedule.update!(description: 'updated description')

      expect(schedule.reload.next_run_at).to be_nil
    end

    it 'preserves next_run_at when deactivated' do
      schedule.update_column(:next_run_at, nil)

      schedule.update!(active: false)

      expect(schedule.reload.next_run_at).to be_nil
    end
  end

  describe '#schedule_next_run!' do
    let(:schedule) { create(:ai_flow_schedule) }

    it 'persists a freshly calculated next_run_at' do
      schedule.update_column(:next_run_at, nil)

      schedule.schedule_next_run!

      expect(schedule.reload.next_run_at).to be_future
    end

    it 'saves and recalculates from a pending cron change', :aggregate_failures do
      original_next_run_at = schedule.reload.next_run_at
      schedule.cron = '0 22 * * *'

      schedule.schedule_next_run!

      expect(schedule).not_to be_changed
      expect(schedule.reload.next_run_at).not_to eq(original_next_run_at)
    end
  end

  describe '#worker_cron_expression' do
    let(:schedule) { build(:ai_flow_schedule) }

    it 'uses the registered dispatcher worker cron' do
      allow(Gitlab::SidekiqConfig).to receive(:cron_jobs)
        .and_return({ 'ai_flow_schedule_worker' => { 'cron' => '*/5 * * * *' } })

      expect(schedule.worker_cron_expression).to eq('*/5 * * * *')
    end
  end

  describe '#record_success!' do
    it 'resets failure tracking and sets success status' do
      schedule = create(:ai_flow_schedule, consecutive_failure_count: 2, last_run_status: :sa_invalid,
        last_run_error: 'some error')

      schedule.record_success!

      expect(schedule.consecutive_failure_count).to eq(0)
      expect(schedule.last_run_status).to eq('success')
      expect(schedule.last_run_error).to be_nil
      expect(schedule.last_run_at).to be_present
    end
  end

  describe '#record_failure!' do
    it 'increments failure count and sets error' do
      schedule = create(:ai_flow_schedule)

      schedule.record_failure!('Something went wrong')

      expect(schedule.consecutive_failure_count).to eq(1)
      expect(schedule.last_run_status).to eq('execution_error')
      expect(schedule.last_run_error).to eq('Something went wrong')
      expect(schedule.last_run_at).to be_present
      expect(schedule.active).to be true
    end

    it 'records the given failure status' do
      schedule = create(:ai_flow_schedule)

      schedule.record_failure!('Service account unavailable', status: :sa_invalid)

      expect(schedule.last_run_status).to eq('sa_invalid')
    end

    it 'deactivates after MAX_CONSECUTIVE_FAILURES' do
      schedule = create(:ai_flow_schedule, consecutive_failure_count: 2)

      schedule.record_failure!('Service account unavailable')

      expect(schedule.consecutive_failure_count).to eq(3)
      expect(schedule.active).to be false
    end

    it 'truncates long error messages' do
      schedule = create(:ai_flow_schedule)
      long_error = 'x' * 2000

      schedule.record_failure!(long_error)

      expect(schedule.last_run_error.length).to be <= 1024
    end

    it 'accepts a nil error message' do
      schedule = create(:ai_flow_schedule)

      schedule.record_failure!(nil)

      expect(schedule.last_run_error).to be_nil
    end
  end

  describe '#deactivated_by_failures?' do
    it 'returns true when inactive with max failures' do
      schedule = build(:ai_flow_schedule, :deactivated_by_failures)

      expect(schedule.deactivated_by_failures?).to be true
    end

    it 'returns false when active' do
      schedule = build(:ai_flow_schedule, consecutive_failure_count: 3)

      expect(schedule.deactivated_by_failures?).to be false
    end

    it 'returns false when inactive but below threshold' do
      schedule = build(:ai_flow_schedule, active: false, consecutive_failure_count: 1)

      expect(schedule.deactivated_by_failures?).to be false
    end
  end

  describe '#deactivate!' do
    it 'sets active to false' do
      schedule = create(:ai_flow_schedule)

      schedule.deactivate!

      expect(schedule.reload.active).to be false
    end

    it 'resets consecutive_failure_count' do
      schedule = create(:ai_flow_schedule, consecutive_failure_count: 2)

      schedule.deactivate!

      expect(schedule.reload.consecutive_failure_count).to eq(0)
    end
  end

  describe '#service_account' do
    it 'delegates to flow_trigger' do
      schedule = build(:ai_flow_schedule)

      expect(schedule.service_account).to eq(schedule.flow_trigger.service_account)
    end
  end

  describe 'plan limits' do
    it 'includes Limitable' do
      expect(described_class.ancestors).to include(Limitable)
    end

    it 'uses project as limit scope' do
      expect(described_class.limit_scope).to eq(:project)
    end

    it 'uses ai_flow_schedules as limit name' do
      expect(described_class.limit_name).to eq('ai_flow_schedules')
    end

    it_behaves_like 'includes Limitable concern' do
      subject { build(:ai_flow_schedule, flow_trigger: create(:ai_flow_trigger)) }
    end
  end

  describe 'factory' do
    it 'creates the schedule in the flow trigger project' do
      schedule = create(:ai_flow_schedule)

      expect(schedule.project).to eq(schedule.flow_trigger.project)
    end

    it 'creates a valid deactivated_by_failures schedule', :aggregate_failures do
      schedule = create(:ai_flow_schedule, :deactivated_by_failures)

      expect(schedule).to be_valid
      expect(schedule).to be_deactivated_by_failures
    end
  end
end
