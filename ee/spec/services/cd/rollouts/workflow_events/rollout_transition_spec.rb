# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::WorkflowEvents::RolloutTransition, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wf-1')
  end

  subject(:workflow_event) { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)) }

  describe '#execute' do
    context 'with a rollout_succeeded event' do
      let(:params) { { type: 'com.gitlab.cd.rollout_succeeded', data: {} } }

      it 'completes the rollout' do
        expect { workflow_event.execute }.to change { rollout.reload.state }.from('in_progress').to('completed')
      end

      it 'is idempotent against an at-least-once retry' do
        workflow_event.execute

        expect { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)).execute }
          .not_to change { rollout.reload.state }
      end
    end

    context 'with a step_started event naming the approval step type' do
      let(:params) do
        { type: 'com.gitlab.cd.step_started',
          data: { position: [0, 0], step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE } }
      end

      it 'opens an approval gate under a row lock on the rollout' do
        expect(rollout).to receive(:with_lock).and_call_original

        expect { workflow_event.execute }.to change { rollout.reload.open_approval_gate? }.from(false).to(true)
      end

      context 'when the event names a matching rollout step' do
        let!(:rollout_step) do
          create(:cd_rollout_step, rollout: rollout, path: '0.0', step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE)
        end

        it 'records the gated step on the request_approval transition' do
          workflow_event.execute

          gate_transition = rollout.reload.rollout_transitions.gate_events.sole
          expect(gate_transition.rollout_step).to eq(rollout_step)
        end
      end

      context 'when the event names no matching rollout step' do
        it 'still opens the gate, with no rollout_step recorded' do
          workflow_event.execute

          gate_transition = rollout.reload.rollout_transitions.gate_events.sole
          expect(gate_transition.rollout_step).to be_nil
        end

        it 'looks up the step only once, even though #open_gate and #transition_step both need it' do
          queries = ActiveRecord::QueryRecorder.new { workflow_event.execute }

          step_lookup_queries = queries.log.count { |sql| sql.include?('"cd_rollout_steps"') }

          expect(step_lookup_queries).to eq(1)
        end
      end

      context 'when the event carries no step position at all' do
        let(:params) do
          { type: 'com.gitlab.cd.step_started', data: { step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE } }
        end

        it 'still opens the gate, with no rollout_step recorded' do
          workflow_event.execute

          gate_transition = rollout.reload.rollout_transitions.gate_events.sole
          expect(gate_transition.rollout_step).to be_nil
        end
      end

      it 'checks the gate state after acquiring the lock, not before' do
        # A concurrent caller could have opened the gate between an earlier,
        # unlocked check and this call's create!. Asserting the check happens
        # only inside #with_lock (not before it) is what rules that window out.
        call_order = []

        allow(rollout).to receive(:with_lock).and_wrap_original do |method, &block|
          call_order << :with_lock
          method.call(&block)
        end
        allow(rollout).to receive(:open_approval_gate?).and_wrap_original do |method|
          call_order << :open_approval_gate?
          method.call
        end

        workflow_event.execute

        expect(call_order).to eq([:with_lock, :open_approval_gate?])
      end
    end

    context 'with an approval_requested event' do
      let(:params) do
        { type: 'com.gitlab.cd.approval_requested', data: { position: [0, 0], reason: 'needs sign-off' } }
      end

      it 'opens an approval gate under a row lock on the rollout, with no step_type check needed' do
        expect(rollout).to receive(:with_lock).and_call_original

        expect { workflow_event.execute }.to change { rollout.reload.open_approval_gate? }.from(false).to(true)
      end

      it 'records the reason on the request_approval transition' do
        workflow_event.execute

        gate_transition = rollout.reload.rollout_transitions.gate_events.sole
        expect(gate_transition.reason).to eq('needs sign-off')
      end

      it 'fires the cd_rollout_gate_updated subscription trigger' do
        expect(GraphqlTriggers).to receive(:cd_rollout_gate_updated).with(rollout)

        workflow_event.execute
      end

      it 'is idempotent against an at-least-once retry' do
        workflow_event.execute

        expect { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)).execute }
          .not_to change { rollout.reload.open_approval_gate? }
      end

      context 'when the event names a matching rollout step' do
        let!(:rollout_step) do
          create(:cd_rollout_step, rollout: rollout, path: '0.0', step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE)
        end

        it 'transitions the step to awaiting_approval and records it on the request_approval transition' do
          workflow_event.execute

          expect(rollout_step.reload.state).to eq('awaiting_approval')

          gate_transition = rollout.reload.rollout_transitions.gate_events.sole
          expect(gate_transition.rollout_step).to eq(rollout_step)
        end
      end

      context 'when the rollout is already in a terminal state' do
        let(:rollout) do
          create(:cd_rollout, application: application, version_set: version_set, state: :failed,
            workflow_ref: 'wf-1')
        end

        it 'does not open the gate' do
          expect { workflow_event.execute }.not_to change { rollout.reload.open_approval_gate? }
        end
      end
    end

    context 'when a step_started event names a rollout step' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '1', state: :pending) }

      let(:params) do
        { type: 'com.gitlab.cd.step_started', data: { position: [1], step_type: 'com.gitlab.cd.steps.wait' } }
      end

      it 'transitions the rollout step to running' do
        expect { workflow_event.execute }.to change { rollout_step.reload.state }.from('pending').to('running')
      end
    end

    context 'when a step_succeeded event completes the only step in the rollout' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '0', state: :running) }

      let(:params) do
        { type: 'com.gitlab.cd.step_succeeded', data: { position: [0], step_type: 'com.gitlab.cd.steps.wait' } }
      end

      it 'completes the rollout step but leaves the rollout in progress until rollout_succeeded arrives' do
        workflow_event.execute

        expect(rollout_step.reload.state).to eq('success')
        expect(rollout.reload.state).to eq('in_progress')
      end
    end

    context 'when a step_failed event names a rollout step' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '0', state: :running) }

      let(:params) do
        { type: 'com.gitlab.cd.step_failed',
          data: { position: [0], step_type: 'com.gitlab.cd.steps.wait', error: 'boom' } }
      end

      it 'fails the rollout step, records the error, and fails the rollout immediately' do
        workflow_event.execute

        expect(rollout_step.reload).to have_attributes(state: 'failed', error: 'boom')
        expect(rollout.reload.state).to eq('failed')
      end
    end
  end
end
