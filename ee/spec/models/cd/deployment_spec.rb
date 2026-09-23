# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Deployment, feature_category: :continuous_delivery do
  let_it_be(:application) { create(:cd_application) }
  let_it_be(:service) { create(:cd_service, application: application) }
  let_it_be(:rollout_environment) { create(:cd_rollout_environment) }

  describe 'factory' do
    it 'creates a valid deployment using factory defaults' do
      expect(create(:cd_deployment)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:service).required }
    it { is_expected.to belong_to(:rollout_environment).required }
    it { is_expected.to have_many(:deployment_transitions) }

    it 'orders deployment_transitions by created_at ascending' do
      deployment = create(:cd_deployment)
      newer = create(:cd_deployment_transition, deployment: deployment, created_at: 1.day.ago)
      older = create(:cd_deployment_transition, deployment: deployment, created_at: 2.days.ago)

      expect(deployment.deployment_transitions).to eq([older, newer])
    end
  end

  describe 'enums' do
    it 'defines state enum' do
      is_expected.to define_enum_for(:state).with_values(
        pending: 0,
        deploying: 1,
        healthy: 2,
        degraded: 3,
        failed: 4,
        cancelled: 5
      )
    end
  end

  describe 'validations' do
    subject do
      build(:cd_deployment,
        service: service,
        rollout_environment: rollout_environment)
    end

    it { is_expected.to be_valid }

    it 'rejects a second deployment for the same service in the same rollout environment' do
      create(:cd_deployment,
        service: service,
        rollout_environment: rollout_environment)

      duplicate = build(:cd_deployment,
        service: service,
        rollout_environment: rollout_environment)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:service_id]).to include('already has a deployment in this rollout environment')
    end
  end

  describe 'sharding key' do
    subject do
      build(:cd_deployment,
        service: service,
        rollout_environment: rollout_environment)
    end

    it { is_expected.to populate_sharding_key(:organization_id).with(service.organization_id) }
  end

  describe '.last_deployed_at_by_service' do
    let_it_be(:other_service) { create(:cd_service, application: application) }

    it 'returns the most recently finished deployment timestamp for each service, keyed by service id' do
      older = create(:cd_deployment, service: service, state: :healthy, finished_at: 2.hours.ago)
      newer = create(:cd_deployment, service: service, state: :healthy, finished_at: 1.hour.ago)
      other_deployment = create(:cd_deployment, service: other_service, state: :failed, finished_at: 3.hours.ago)

      result = described_class.last_deployed_at_by_service([service.id, other_service.id])

      expect(result[service.id]).to be_like_time(newer.finished_at)
      expect(result[service.id]).not_to be_like_time(older.finished_at)
      expect(result[other_service.id]).to be_like_time(other_deployment.finished_at)
    end

    it 'omits services with no finished deployment' do
      create(:cd_deployment, service: service, state: :pending)

      expect(described_class.last_deployed_at_by_service([service.id])).to eq({})
    end

    it 'omits services that are not in the given list of ids' do
      create(:cd_deployment, service: service, state: :healthy, finished_at: 1.hour.ago)
      create(:cd_deployment, service: other_service, state: :healthy, finished_at: 1.hour.ago)

      expect(described_class.last_deployed_at_by_service([service.id]).keys).to contain_exactly(service.id)
    end
  end

  describe 'state machine' do
    subject(:deployment) do
      create(:cd_deployment, service: service, rollout_environment: rollout_environment)
    end

    it 'has an initial state of pending' do
      expect(deployment).to be_pending
    end

    describe 'states' do
      it 'declares all expected states' do
        is_expected.to have_states(
          :pending, :deploying, :healthy, :degraded,
          :failed, :cancelled
        )
      end
    end

    describe 'event handling' do
      it { is_expected.to handle_events(:start_deploying, when: :pending) }
      it { is_expected.to reject_events(:start_deploying, when: :deploying) }
      it { is_expected.to reject_events(:start_deploying, when: :healthy) }

      it { is_expected.to handle_events(:mark_healthy, when: :deploying) }
      it { is_expected.to reject_events(:mark_healthy, when: :pending) }
      it { is_expected.to reject_events(:mark_healthy, when: :degraded) }
      it { is_expected.to reject_events(:mark_healthy, when: :failed) }

      it { is_expected.to handle_events(:mark_degraded, when: :deploying) }
      it { is_expected.to reject_events(:mark_degraded, when: :pending) }
      it { is_expected.to reject_events(:mark_degraded, when: :healthy) }
      it { is_expected.to reject_events(:mark_degraded, when: :failed) }

      it { is_expected.to handle_events(:fail_deployment, when: :deploying) }
      it { is_expected.to reject_events(:fail_deployment, when: :pending) }
      it { is_expected.to reject_events(:fail_deployment, when: :healthy) }
      it { is_expected.to reject_events(:fail_deployment, when: :degraded) }
      it { is_expected.to reject_events(:fail_deployment, when: :failed) }

      it { is_expected.to handle_events(:cancel, when: :deploying) }
      it { is_expected.to reject_events(:cancel, when: :pending) }
      it { is_expected.to reject_events(:cancel, when: :healthy) }
      it { is_expected.to reject_events(:cancel, when: :degraded) }
      it { is_expected.to reject_events(:cancel, when: :failed) }
      it { is_expected.to reject_events(:cancel, when: :cancelled) }
    end

    describe 'transitions' do
      using RSpec::Parameterized::TableSyntax

      where(:event, :from_state, :to_state) do
        :start_deploying  | :pending   | :deploying
        :mark_healthy     | :deploying | :healthy
        :mark_degraded    | :deploying | :degraded
        :fail_deployment  | :deploying | :failed
        :cancel           | :deploying | :cancelled
      end

      with_them do
        before do
          deployment.update_column(:state, described_class.states[from_state.to_s])
        end

        it "transitions from #{params[:from_state]} to #{params[:to_state]} on #{params[:event]}" do
          expect { deployment.public_send(:"#{event}!") }
            .to change { deployment.state }
            .from(from_state.to_s)
            .to(to_state.to_s)
        end
      end
    end

    describe 'callbacks' do
      describe 'setting started_at' do
        context 'when transitioning to deploying for the first time' do
          it 'sets started_at' do
            freeze_time do
              deployment.start_deploying!

              expect(deployment.started_at).to be_like_time(Time.current)
            end
          end
        end
      end

      describe 'setting finished_at' do
        it 'sets finished_at when entering a terminal state', :aggregate_failures do
          terminal_transitions = [
            { from: :deploying, event: :mark_healthy, to: :healthy },
            { from: :deploying, event: :mark_degraded, to: :degraded },
            { from: :deploying, event: :fail_deployment, to: :failed },
            { from: :deploying, event: :cancel, to: :cancelled }
          ]

          terminal_transitions.each do |transition|
            deployment = build_deployment_in_state(transition[:from])

            freeze_time do
              deployment.public_send(:"#{transition[:event]}!")

              expect(deployment.finished_at).to be_like_time(Time.current),
                "expected finished_at to be set when transitioning " \
                  "from #{transition[:from]} to #{transition[:to]} via #{transition[:event]}"
            end
          end
        end

        it 'does not set finished_at on non-terminal transitions', :aggregate_failures do
          non_terminal_transitions = [
            { from: :pending, event: :start_deploying, to: :deploying }
          ]

          non_terminal_transitions.each do |transition|
            deployment = build_deployment_in_state(transition[:from])

            deployment.public_send(:"#{transition[:event]}!")

            expect(deployment.finished_at).to be_nil,
              "expected finished_at to remain nil when transitioning " \
                "from #{transition[:from]} to #{transition[:to]} via #{transition[:event]}"
          end
        end

        # Creates a fresh deployment with a unique (rollout_environment_id, service_id)
        # pair to avoid the uniqueness constraint.
        def build_deployment_in_state(state)
          fresh_service = create(:cd_service, application: application)
          deployment = create(:cd_deployment, service: fresh_service)
          deployment.update_column(:state, described_class.states[state.to_s])
          deployment
        end
      end

      describe 'recording service environment health' do
        let(:environment) { rollout_environment.environment }

        def deployment_in_state(state)
          fresh_service = create(:cd_service, application: application)

          create(:cd_deployment, service: fresh_service, rollout_environment: rollout_environment).tap do |deployment|
            deployment.update_column(:state, described_class.states[state.to_s])
          end
        end

        def health_for(deployment)
          ::Cd::ServiceEnvironmentHealth.find_by!(service: deployment.service, environment: environment)
        end

        it 'records healthy service health when the deployment finishes healthy' do
          deployment = deployment_in_state(:deploying)

          deployment.mark_healthy!

          expect(health_for(deployment)).to be_healthy
          expect(health_for(deployment).observed_at).to be_like_time(deployment.finished_at)
        end

        it 'records degraded service health when the deployment finishes degraded' do
          deployment = deployment_in_state(:deploying)

          deployment.mark_degraded!

          expect(health_for(deployment)).to be_degraded
        end

        it 'overwrites the existing row for the same service and environment' do
          deployment = deployment_in_state(:deploying)
          existing = create(:cd_service_environment_health, service: deployment.service, environment: environment,
            health: :failed)

          expect { deployment.mark_healthy! }.not_to change { ::Cd::ServiceEnvironmentHealth.count }
          expect(existing.reload).to be_healthy
        end

        it 'does not record service health for failed or cancelled deployments', :aggregate_failures do
          %i[fail_deployment cancel].each do |event|
            deployment = deployment_in_state(:deploying)

            expect { deployment.public_send(:"#{event}!") }.not_to change { ::Cd::ServiceEnvironmentHealth.count }
          end
        end
      end

      describe 'triggering cd_service_updated and cd_environment_service_updated' do
        let(:deploying_deployment) do
          create(:cd_deployment, service: create(:cd_service, application: application)).tap do |deployment|
            deployment.update_column(:state, described_class.states['deploying'])
          end
        end

        %i[mark_healthy mark_degraded fail_deployment cancel].each do |event|
          it "fires both subscription triggers on #{event}", :aggregate_failures do
            expect(GraphqlTriggers).to receive(:cd_service_updated).with(deploying_deployment.service)
            expect(GraphqlTriggers).to receive(:cd_environment_service_updated).with(deploying_deployment)

            deploying_deployment.public_send(:"#{event}!")
          end
        end

        it 'does not fire on a non-terminal transition', :aggregate_failures do
          pending_deployment = create(:cd_deployment, service: create(:cd_service, application: application))

          expect(GraphqlTriggers).not_to receive(:cd_service_updated)
          expect(GraphqlTriggers).not_to receive(:cd_environment_service_updated)

          pending_deployment.start_deploying!
        end

        it 'does not fire when the transaction is rolled back', :aggregate_failures do
          expect(GraphqlTriggers).not_to receive(:cd_service_updated)
          expect(GraphqlTriggers).not_to receive(:cd_environment_service_updated)

          described_class.transaction do
            deploying_deployment.mark_healthy!
            raise ActiveRecord::Rollback
          end
        end
      end

      describe 'triggering cd_deployment_updated' do
        [
          { from: :pending,   event: :start_deploying },
          { from: :deploying, event: :mark_healthy },
          { from: :deploying, event: :mark_degraded },
          { from: :deploying, event: :fail_deployment },
          { from: :deploying, event: :cancel }
        ].each do |transition|
          it "fires the subscription trigger for the deployment on #{transition[:event]}" do
            deployment = create(:cd_deployment, service: create(:cd_service, application: application))
            deployment.update_column(:state, described_class.states[transition[:from].to_s])

            expect(GraphqlTriggers).to receive(:cd_deployment_updated).with(deployment)

            deployment.public_send(:"#{transition[:event]}!")
          end
        end

        it 'does not fire when the transaction is rolled back' do
          deployment = create(:cd_deployment, service: create(:cd_service, application: application))
          deployment.update_column(:state, described_class.states['deploying'])

          expect(GraphqlTriggers).not_to receive(:cd_deployment_updated)

          described_class.transaction do
            deployment.mark_healthy!
            raise ActiveRecord::Rollback
          end
        end
      end
    end
  end

  describe '.for_service' do
    it 'returns deployments for the given service' do
      other_service = create(:cd_service, application: application)
      matching = create(:cd_deployment, service: service, rollout_environment: rollout_environment)
      create(:cd_deployment, service: other_service, rollout_environment: rollout_environment)

      expect(described_class.for_service(service)).to contain_exactly(matching)
    end
  end

  describe 'syncing the rollout environment state' do
    let_it_be_with_reload(:rollout_environment) { create(:cd_rollout_environment, state: :pending) }

    let(:deployment) do
      create(:cd_deployment, rollout_environment: rollout_environment, service: create(:cd_service))
    end

    it 'rolls the state up into the rollout environment when a deployment state changes' do
      deployment.start_deploying!

      expect(rollout_environment.reload.state).to eq('in_progress')
    end

    it 'completes the rollout environment when its deployments finish healthy' do
      deployment.start_deploying!
      deployment.mark_healthy!

      expect(rollout_environment.reload.state).to eq('completed')
    end

    it 'fails the rollout environment when a deployment fails' do
      deployment.start_deploying!
      deployment.fail_deployment!

      expect(rollout_environment.reload.state).to eq('failed')
    end

    it 'does not touch the rollout environment when a deployment is created' do
      expect { create(:cd_deployment, rollout_environment: rollout_environment, service: create(:cd_service)) }
        .not_to change { rollout_environment.reload.updated_at }
    end
  end
end
