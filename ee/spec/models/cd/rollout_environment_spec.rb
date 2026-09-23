# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::RolloutEnvironment, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }
  let_it_be(:environment) { create(:cd_environment) }

  describe 'factory' do
    it 'creates a valid rollout environment using factory defaults' do
      expect(create(:cd_rollout_environment)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:rollout).required }
    it { is_expected.to belong_to(:environment).required }
    it { is_expected.to belong_to(:driver_binding).required }
    it { is_expected.to belong_to(:previous_version_set).optional }
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to have_many(:deployments) }
  end

  describe 'enums' do
    it 'defines state enum' do
      is_expected.to define_enum_for(:state).with_values(
        pending: 0,
        in_progress: 1,
        paused: 2,
        completed: 3,
        failed: 4,
        cancelled: 5
      )
    end
  end

  describe 'scopes' do
    describe '.in_organization' do
      it 'returns rollout environments belonging to the organization' do
        rollout_environment = create(:cd_rollout_environment, rollout: rollout)
        create(:cd_rollout_environment)

        expect(described_class.in_organization(rollout.organization)).to contain_exactly(rollout_environment)
      end
    end

    describe '.ordered' do
      it 'returns rollout environments ordered by position ascending' do
        # Created out of position order so the assertion proves the scope reorders them.
        second = create(:cd_rollout_environment, rollout: rollout, position: 2)
        first = create(:cd_rollout_environment, rollout: rollout, position: 1)

        expect(described_class.where(rollout: rollout).ordered).to eq([first, second])
      end
    end
  end

  describe '.latest_finished_per_environment' do
    def create_completed(environment, finished_at:)
      create(:cd_rollout_environment, environment: environment, state: :completed)
        .tap { |record| record.update_column(:finished_at, finished_at) }
    end

    it 'returns the most recently completed rollout environment for each environment' do
      other_environment = create(:cd_environment)
      _older = create_completed(environment, finished_at: 2.days.ago)
      newer = create_completed(environment, finished_at: 1.day.ago)
      other_newest = create_completed(other_environment, finished_at: 3.hours.ago)

      records = described_class.latest_finished_per_environment([environment.id, other_environment.id])

      expect(records).to contain_exactly(newer, other_newest)
    end

    it 'ignores rollout environments that are not completed' do
      terminal_but_not_completed = create(:cd_rollout_environment, environment: environment, state: :failed)
      terminal_but_not_completed.update_column(:finished_at, 1.hour.ago)
      _in_progress = create(:cd_rollout_environment, environment: environment, state: :in_progress)

      expect(described_class.latest_finished_per_environment([environment.id])).to be_empty
    end

    it 'breaks finished_at ties by picking the most recently created record' do
      finished_at = 1.day.ago
      _older_record = create_completed(environment, finished_at: finished_at)
      newer_record = create_completed(environment, finished_at: finished_at)

      expect(described_class.latest_finished_per_environment([environment.id])).to contain_exactly(newer_record)
    end
  end

  describe 'validations' do
    subject { build(:cd_rollout_environment, rollout: rollout, environment: environment) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:position) }

    it 'rejects a second rollout environment for the same environment in the same rollout' do
      create(:cd_rollout_environment, rollout: rollout, environment: environment)

      duplicate = build(:cd_rollout_environment, rollout: rollout, environment: environment)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:environment_id]).to include('already has a rollout environment in this rollout')
    end
  end

  describe 'sharding key' do
    subject { build(:cd_rollout_environment, rollout: rollout, environment: environment) }

    it { is_expected.to populate_sharding_key(:organization_id).with(rollout.organization_id) }
  end

  describe '.state_from_deployment_states' do
    using RSpec::Parameterized::TableSyntax

    where(:deployment_states, :expected_state) do
      []                                | :pending
      %w[pending pending]               | :pending
      %w[pending deploying]             | :in_progress
      %w[deploying deploying]           | :in_progress
      %w[healthy pending]               | :in_progress
      %w[healthy healthy]               | :completed
      %w[healthy degraded]              | :completed
      %w[degraded degraded]             | :completed
      %w[healthy failed]                | :failed
      %w[failed cancelled]              | :failed
      %w[healthy cancelled]             | :cancelled
      %w[deploying cancelled]           | :cancelled
    end

    with_them do
      it 'rolls the deployment states up worst-status-wins' do
        expect(described_class.state_from_deployment_states(deployment_states)).to eq(expected_state)
      end
    end
  end

  describe '#sync_state_from_deployments!' do
    let_it_be_with_reload(:rollout_environment) { create(:cd_rollout_environment, state: :pending) }

    def create_deployment(state)
      create(:cd_deployment, rollout_environment: rollout_environment,
        service: create(:cd_service), state: state)
    end

    it 'updates the cached state from the deployment states' do
      create_deployment(:healthy)
      create_deployment(:deploying)

      expect { rollout_environment.sync_state_from_deployments! }
        .to change { rollout_environment.reload.state }.from('pending').to('in_progress')
    end

    it 'stamps finished_at when the derived state is terminal' do
      create_deployment(:healthy)

      expect { rollout_environment.sync_state_from_deployments! }
        .to change { rollout_environment.reload.finished_at }.from(nil)
    end

    it 'does not derive a state for a paused (operator hold) environment' do
      rollout_environment.update!(state: :paused)
      create_deployment(:failed)

      expect { rollout_environment.sync_state_from_deployments! }
        .not_to change { rollout_environment.reload.state }.from('paused')
    end

    it 'does not raise when a second deployment leaves the derived state unchanged' do
      rollout_environment.update!(state: :in_progress)
      create_deployment(:deploying)

      expect { rollout_environment.sync_state_from_deployments! }.not_to raise_error
    end
  end

  describe 'state machine' do
    subject(:rollout_environment) { create(:cd_rollout_environment, state: :pending) }

    it 'has an initial state of pending' do
      expect(rollout_environment).to be_pending
    end

    describe 'states' do
      it 'declares all expected states' do
        is_expected.to have_states(
          :pending, :in_progress, :paused,
          :completed, :failed, :cancelled
        )
      end
    end

    describe 'event handling' do
      it { is_expected.to handle_events(:start, when: :pending) }
      it { is_expected.to reject_events(:start, when: :in_progress) }
      it { is_expected.to reject_events(:start, when: :completed) }

      it { is_expected.to handle_events(:pause, when: :in_progress) }
      it { is_expected.to reject_events(:pause, when: :pending) }
      it { is_expected.to reject_events(:pause, when: :paused) }

      it { is_expected.to handle_events(:resume, when: :paused) }
      it { is_expected.to reject_events(:resume, when: :in_progress) }
      it { is_expected.to reject_events(:resume, when: :pending) }

      # Unlike Cd::Rollout, complete/fail_environment are also reachable directly from
      # pending: the derived state (state_from_deployment_states) can skip in_progress.
      it { is_expected.to handle_events(:complete, when: :pending) }
      it { is_expected.to handle_events(:complete, when: :in_progress) }
      it { is_expected.to reject_events(:complete, when: :completed) }
      it { is_expected.to reject_events(:complete, when: :failed) }

      it { is_expected.to handle_events(:fail_environment, when: :pending) }
      it { is_expected.to handle_events(:fail_environment, when: :in_progress) }
      it { is_expected.to reject_events(:fail_environment, when: :completed) }
      it { is_expected.to reject_events(:fail_environment, when: :failed) }

      it { is_expected.to handle_events(:cancel, when: :pending) }
      it { is_expected.to handle_events(:cancel, when: :in_progress) }
      it { is_expected.to handle_events(:cancel, when: :paused) }
      it { is_expected.to reject_events(:cancel, when: :completed) }
      it { is_expected.to reject_events(:cancel, when: :failed) }
      it { is_expected.to reject_events(:cancel, when: :cancelled) }
    end

    describe 'transitions' do
      using RSpec::Parameterized::TableSyntax

      where(:event, :from_state, :to_state) do
        :start            | :pending     | :in_progress
        :pause            | :in_progress | :paused
        :resume           | :paused      | :in_progress
        :complete         | :pending     | :completed
        :complete         | :in_progress | :completed
        :fail_environment | :pending     | :failed
        :fail_environment | :in_progress | :failed
        :cancel           | :pending     | :cancelled
        :cancel           | :in_progress | :cancelled
        :cancel           | :paused      | :cancelled
      end

      with_them do
        before do
          rollout_environment.update_column(:state, described_class.states[from_state.to_s])
        end

        it "transitions from #{params[:from_state]} to #{params[:to_state]} on #{params[:event]}" do
          expect { rollout_environment.public_send(:"#{event}!") }
            .to change { rollout_environment.state }
            .from(from_state.to_s)
            .to(to_state.to_s)
        end
      end
    end

    describe 'callbacks' do
      describe 'setting started_at' do
        context 'when transitioning to in_progress for the first time' do
          it 'sets started_at' do
            freeze_time do
              rollout_environment.start!

              expect(rollout_environment.started_at).to be_like_time(Time.current)
            end
          end
        end

        context 'when resuming from paused' do
          before do
            rollout_environment.update_columns(state: described_class.states['paused'], started_at: 1.hour.ago)
          end

          it 'does not overwrite started_at' do
            original_started_at = rollout_environment.started_at

            rollout_environment.resume!

            expect(rollout_environment.started_at).to be_like_time(original_started_at)
          end
        end

        context 'when completing directly from pending' do
          it 'backfills started_at' do
            freeze_time do
              rollout_environment.complete!

              expect(rollout_environment.started_at).to be_like_time(Time.current)
            end
          end
        end

        context 'when cancelling directly from pending' do
          it 'leaves started_at nil, like Cd::Rollout#cancel' do
            rollout_environment.cancel!

            expect(rollout_environment.started_at).to be_nil
          end
        end
      end

      describe 'setting finished_at' do
        it 'sets finished_at when entering a terminal state', :aggregate_failures do
          terminal_transitions = [
            { from: :pending, event: :complete, to: :completed },
            { from: :in_progress, event: :complete, to: :completed },
            { from: :pending, event: :fail_environment, to: :failed },
            { from: :in_progress, event: :fail_environment, to: :failed },
            { from: :pending, event: :cancel, to: :cancelled },
            { from: :in_progress, event: :cancel, to: :cancelled },
            { from: :paused, event: :cancel, to: :cancelled }
          ]

          terminal_transitions.each do |transition|
            rollout_environment = create(:cd_rollout_environment, state: transition[:from])

            freeze_time do
              rollout_environment.public_send(:"#{transition[:event]}!")

              expect(rollout_environment.finished_at).to be_like_time(Time.current),
                "expected finished_at to be set when transitioning " \
                  "from #{transition[:from]} to #{transition[:to]} via #{transition[:event]}"
            end
          end
        end

        it 'does not set finished_at on non-terminal transitions', :aggregate_failures do
          non_terminal_transitions = [
            { from: :pending, event: :start, to: :in_progress },
            { from: :in_progress, event: :pause, to: :paused },
            { from: :paused, event: :resume, to: :in_progress }
          ]

          non_terminal_transitions.each do |transition|
            rollout_environment = create(:cd_rollout_environment, state: transition[:from])

            rollout_environment.public_send(:"#{transition[:event]}!")

            expect(rollout_environment.finished_at).to be_nil,
              "expected finished_at to remain nil when transitioning " \
                "from #{transition[:from]} to #{transition[:to]} via #{transition[:event]}"
          end
        end
      end
    end
  end
end
