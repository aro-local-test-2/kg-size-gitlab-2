# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::ResolveGateService, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:user) { create(:user) }

  let(:rollout) do
    create(:cd_rollout, version_set: version_set, application: application, state: :in_progress, workflow_ref: 'wf-1')
  end

  let(:status) { :approved }
  let(:reason) { nil }

  subject(:service) do
    described_class.new(rollout, current_user: user, status: status, resolution_reason: reason)
  end

  describe '#execute' do
    context 'when the rollout has an open approval gate' do
      let(:request_approval_step) { nil }

      let!(:request_approval_transition) do
        create(:cd_rollout_transition, rollout: rollout, event: 'request_approval',
          from_state: 'in_progress', to_state: 'in_progress', rollout_step: request_approval_step)
      end

      it 'queries cd_rollout_transitions for the open gate only once' do
        queries = ActiveRecord::QueryRecorder.new { service.execute }
        gate_lookup_queries = queries.log.count do |sql|
          sql.include?('FROM "cd_rollout_transitions"') && sql.include?('request_approval')
        end

        expect(gate_lookup_queries).to eq(1)
      end

      context 'when approving' do
        let(:status) { :approved }

        it 'creates an approve transition journal entry' do
          response = nil

          expect { response = service.execute }.to change { ::Cd::RolloutTransition.count }.by(1)

          expect(response).to be_success
          expect(response.payload[:rollout_transition]).to have_attributes(
            rollout: rollout,
            organization: organization,
            event: 'approve',
            from_state: 'in_progress',
            to_state: 'in_progress',
            principal: "user:#{user.id}",
            resolution_reason: nil
          )
        end

        it 'does not change the rollout state' do
          expect { service.execute }.not_to change { rollout.reload.state }
        end

        it 'closes the approval gate' do
          service.execute

          expect(rollout.reload.open_approval_gate?).to be(false)
        end

        it 'fires the cd_rollout_gate_updated subscription trigger' do
          expect(GraphqlTriggers).to receive(:cd_rollout_gate_updated).with(rollout)

          service.execute
        end

        it 'enqueues a job to push the decision to the workflow' do
          response = nil

          expect { response = service.execute }
            .to change { Cd::Rollouts::PushGateDecisionWorker.jobs.size }.by(1)

          transition = response.payload[:rollout_transition]

          expect(Cd::Rollouts::PushGateDecisionWorker.jobs.last['args']).to eq(
            [rollout.id, request_approval_transition.id, transition.event, user.id]
          )
        end
      end

      context 'when rejecting' do
        let(:status) { :rejected }

        it 'creates a reject transition journal entry' do
          response = nil

          expect { response = service.execute }.to change { ::Cd::RolloutTransition.count }.by(1)

          expect(response.payload[:rollout_transition]).to have_attributes(
            event: 'reject',
            from_state: 'in_progress',
            to_state: 'in_progress',
            principal: "user:#{user.id}"
          )
        end
      end

      context 'with a reason' do
        let(:reason) { 'Looks good to ship' }

        it 'records the reason as the transition\'s resolution reason' do
          response = service.execute

          expect(response.payload[:rollout_transition].resolution_reason).to eq('Looks good to ship')
        end
      end

      context 'when the transition is invalid' do
        let(:reason) { 'a' * 2001 }

        it 'returns an error response and does not create a transition' do
          response = nil

          expect { response = service.execute }.not_to change { ::Cd::RolloutTransition.count }

          expect(response).to be_error
          expect(response.message).to include(a_string_matching(/Resolution reason is too long/))
        end
      end

      context 'when the status is unknown' do
        let(:status) { :unknown }

        it 'returns an error response and does not create a transition' do
          response = nil

          expect { response = service.execute }.not_to change { ::Cd::RolloutTransition.count }

          expect(response).to be_error
          expect(response.message).to include(a_string_matching(/unknown gate status/i))
        end
      end
    end

    context 'when the rollout has no open approval gate' do
      it 'returns an error response and does not create a transition' do
        response = nil

        expect { response = service.execute }.not_to change { ::Cd::RolloutTransition.count }

        expect(response).to be_error
        expect(response.message).to include(a_string_matching(/no open approval gate/i))
      end
    end

    context 'when the approval gate has already been resolved' do
      before do
        create(:cd_rollout_transition, rollout: rollout, event: 'request_approval', created_at: 1.hour.ago)
        create(:cd_rollout_transition, rollout: rollout, event: 'approve')
      end

      it 'returns an error response and does not create a transition' do
        response = nil

        expect { response = service.execute }.not_to change { ::Cd::RolloutTransition.count }

        expect(response).to be_error
        expect(response.message).to include(a_string_matching(/no open approval gate/i))
      end
    end
  end
end
