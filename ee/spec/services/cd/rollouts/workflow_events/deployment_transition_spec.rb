# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::WorkflowEvents::DeploymentTransition, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:environment) { create(:cd_environment, organization: organization) }
  let_it_be(:cd_service) { create(:cd_service, application: application) }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wf-1')
  end

  let(:rollout_environment) do
    create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
  end

  let!(:deployment) do
    create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :pending)
  end

  let(:data) { { position: [0, 0], environment: environment.name, service: cd_service.name } }

  subject(:workflow_event) { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)) }

  describe '#execute' do
    context 'with service_started' do
      let(:params) { { type: 'com.gitlab.cd.service_started', data: data } }

      it 'transitions the deployment to deploying and journals it' do
        expect { workflow_event.execute }.to change { deployment.reload.state }.from('pending').to('deploying')

        transition = deployment.deployment_transitions.last
        expect(transition).to have_attributes(
          event: 'start_deploying', from_state: 'pending', to_state: 'deploying', principal: 'system:autoflow'
        )
      end

      it 'is idempotent against an at-least-once retry' do
        workflow_event.execute

        expect { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)).execute }
          .to not_change { deployment.reload.state }
          .and not_change { deployment.deployment_transitions.count }
      end
    end

    context 'with service_succeeded' do
      let(:params) { { type: 'com.gitlab.cd.service_succeeded', data: data } }

      before do
        deployment.start_deploying!
      end

      it 'transitions the deployment to healthy and journals it' do
        expect { workflow_event.execute }.to change { deployment.reload.state }.from('deploying').to('healthy')
      end
    end

    context 'with service_failed' do
      let(:data) { super().merge(error: 'sync timed out') }
      let(:params) { { type: 'com.gitlab.cd.service_failed', data: data } }

      before do
        deployment.start_deploying!
      end

      it 'transitions the deployment to failed and journals the error as the reason' do
        expect { workflow_event.execute }.to change { deployment.reload.state }.from('deploying').to('failed')

        expect(deployment.deployment_transitions.last.reason).to eq('sync timed out')
      end
    end

    context 'when the event arrives before the deployment reaches the expected prior state' do
      let(:params) { { type: 'com.gitlab.cd.service_succeeded', data: data } }

      it 'no-ops instead of raising' do
        expect { workflow_event.execute }.to not_change { deployment.reload.state }
          .and not_change { deployment.deployment_transitions.count }
      end
    end

    context 'when data names no matching service' do
      let(:data) { super().merge(service: 'unknown-service') }
      let(:params) { { type: 'com.gitlab.cd.service_started', data: data } }

      it 'no-ops instead of raising' do
        expect { workflow_event.execute }.not_to change { deployment.reload.state }
      end
    end

    context 'when the transition journal write fails validation' do
      # reason has a 2000-char limit (Cd::DeploymentTransition), so this raises for real
      # rather than mocking the failure. ProcessWorkflowEventService is what catches it.
      let(:data) { super().merge(error: 'x' * 2001) }
      let(:params) { { type: 'com.gitlab.cd.service_failed', data: data } }

      before do
        deployment.start_deploying!
      end

      it 'raises, rolling back the deployment state transition too' do
        expect { workflow_event.execute }.to raise_error(ActiveRecord::RecordInvalid)

        expect(deployment.reload.state).to eq('deploying')
        expect(deployment.deployment_transitions).to be_empty
      end
    end
  end
end
