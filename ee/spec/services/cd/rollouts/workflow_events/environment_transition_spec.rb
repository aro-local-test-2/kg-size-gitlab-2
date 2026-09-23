# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::WorkflowEvents::EnvironmentTransition, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:environment) { create(:cd_environment, organization: organization, name: 'production') }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wf-1')
  end

  let!(:rollout_environment) do
    create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :pending)
  end

  subject(:workflow_event) { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)) }

  describe '#execute' do
    context 'with a stage_started event that names its environment' do
      let(:params) do
        { type: 'com.gitlab.cd.stage_started', data: { stage_name: 'production', environment: 'production' } }
      end

      it 'transitions the named rollout environment to in_progress' do
        expect { workflow_event.execute }
          .to change { rollout_environment.reload.state }.from('pending').to('in_progress')
      end
    end

    context 'with a stage_succeeded event that names its environment' do
      let(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
      end

      let(:params) do
        { type: 'com.gitlab.cd.stage_succeeded', data: { stage_name: 'production', environment: 'production' } }
      end

      it 'transitions the named rollout environment to completed' do
        expect { workflow_event.execute }
          .to change { rollout_environment.reload.state }.from('in_progress').to('completed')
      end
    end

    context 'with a stage_failed event that names its environment' do
      let(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
      end

      let(:params) do
        { type: 'com.gitlab.cd.stage_failed', data: { stage_name: 'production', environment: 'production' } }
      end

      it 'transitions the named rollout environment to failed' do
        expect { workflow_event.execute }
          .to change { rollout_environment.reload.state }.from('in_progress').to('failed')
      end
    end

    context 'when the environment does not match any rollout environment' do
      let(:params) do
        { type: 'com.gitlab.cd.stage_started', data: { stage_name: 'production', environment: 'unknown' } }
      end

      it 'no-ops instead of raising' do
        expect { workflow_event.execute }.not_to change { rollout_environment.reload.state }
      end
    end
  end
end
