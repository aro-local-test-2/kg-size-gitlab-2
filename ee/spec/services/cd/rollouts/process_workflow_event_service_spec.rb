# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::ProcessWorkflowEventService, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wf-1')
  end

  subject(:service) { described_class.new(rollout, params: params) }

  describe '#execute' do
    context 'with an event none of the WorkflowEvents collaborators recognize' do
      let(:params) { { type: 'com.gitlab.cd.something_unknown', data: {} } }

      it 'returns success as a no-op' do
        response = service.execute

        expect(response.success?).to be(true)
        expect(response.payload[:rollout]).to eq(rollout)
      end
    end

    context 'with a rollout_succeeded event' do
      let(:params) { { type: 'com.gitlab.cd.rollout_succeeded', data: {} } }

      it 'delegates to WorkflowEvents::RolloutTransition and returns success' do
        expect { service.execute }.to change { rollout.reload.state }.from('in_progress').to('completed')
      end
    end

    context 'with channel_tokens' do
      let(:params) do
        { type: 'com.gitlab.cd.step_started', data: {},
          channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
      end

      it 'delegates to WorkflowEvents::ChannelTokens' do
        expect { service.execute }.to change { rollout.rollout_channel_tokens.count }.by(1)
      end
    end

    context 'with an approval_requested event carrying channel_tokens' do
      let(:params) do
        { type: 'com.gitlab.cd.approval_requested', data: { position: [0] },
          channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
      end

      it 'persists the token and opens the approval gate in the same pass' do
        expect { service.execute }
          .to change { rollout.rollout_channel_tokens.count }.by(1)
          .and change { rollout.reload.open_approval_gate? }.from(false).to(true)
      end

      it 'is idempotent against an at-least-once retry' do
        service.execute

        expect { described_class.new(rollout, params: params).execute }
          .not_to change { rollout.reload.rollout_transitions.count }
      end

      context 'when the rollout is already terminal' do
        let(:rollout) do
          create(:cd_rollout, application: application, version_set: version_set, state: :completed,
            workflow_ref: 'wf-1')
        end

        it 'still persists the token but does not open the gate' do
          expect { service.execute }
            .to change { rollout.rollout_channel_tokens.count }.by(1)

          expect(rollout.reload.open_approval_gate?).to be(false)
        end
      end
    end

    context 'when a collaborator raises ActiveRecord::RecordInvalid' do
      let_it_be(:environment) { create(:cd_environment, organization: organization) }
      let_it_be(:cd_service) { create(:cd_service, application: application) }

      let(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
      end

      let!(:deployment) do
        create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :deploying)
      end

      let(:params) do
        { type: 'com.gitlab.cd.service_failed',
          data: { position: [0, 0], environment: environment.name, service: cd_service.name, error: 'x' * 2001 } }
      end

      it 'is rescued into a ServiceResponse error instead of propagating' do
        response = service.execute

        expect(response.error?).to be(true)
        expect(response.message).to eq('Unable to process rollout workflow event.')
      end

      it 'tracks the exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(ActiveRecord::RecordInvalid), rollout_id: rollout.id)

        service.execute
      end
    end

    context 'with an incoming_event claim' do
      let(:incoming_event) { create(:cd_rollout_incoming_event, rollout: rollout) }

      subject(:service) { described_class.new(rollout, params: params, incoming_event: incoming_event) }

      context 'when the event is processed successfully' do
        let(:params) { { type: 'com.gitlab.cd.rollout_succeeded', data: {} } }

        it 'marks the claim completed in the same transaction as the event writes' do
          service.execute

          expect(incoming_event.reload).to be_completed
        end
      end

      context 'when a collaborator raises' do
        let_it_be(:environment) { create(:cd_environment, organization: organization) }
        let_it_be(:cd_service) { create(:cd_service, application: application) }

        let(:rollout_environment) do
          create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
        end

        let!(:deployment) do
          create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :deploying)
        end

        let(:params) do
          { type: 'com.gitlab.cd.service_failed',
            data: { position: [0, 0], environment: environment.name, service: cd_service.name, error: 'x' * 2001 } }
        end

        it 'leaves the claim pending rather than marking a swallowed error as done' do
          service.execute

          expect(incoming_event.reload).to be_pending
        end
      end
    end
  end
end
