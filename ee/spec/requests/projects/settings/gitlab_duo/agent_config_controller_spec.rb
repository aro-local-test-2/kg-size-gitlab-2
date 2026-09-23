# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects::Settings::GitlabDuo::AgentConfig', :saas_gitlab_com_subscriptions,
  feature_category: :duo_agent_platform do
  let_it_be(:developer) { create(:user, :with_namespace) }
  let_it_be(:maintainer) { create(:user, :with_namespace) }

  let(:user) { maintainer }

  let_it_be_with_reload(:group) do
    create(:group_with_plan, plan: :ultimate_trial_plan, trial: true,
      trial_starts_on: Date.current, trial_ends_on: 30.days.from_now,
      developers: developer, maintainers: maintainer)
  end

  let_it_be_with_reload(:project) { create(:project, group: group) }

  let(:path) { project_settings_gitlab_duo_agent_config_path(project) }
  let(:service_response) { ServiceResponse.success(payload: { workflow_id: 99 }) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true, ai_catalog: true)
    stub_licensed_features(ai_catalog: true, ai_features: true)
    create(:gitlab_subscription_add_on_purchase, :active_trial, :duo_core, namespace: group)
    project.project_setting.update!(duo_remote_flows_enabled: true, duo_features_enabled: true)
    group.namespace_settings.update!(
      duo_features_enabled: true, experiment_features_enabled: true, duo_core_features_enabled: true
    )
    group.ai_settings.update!(duo_agent_platform_enabled: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)

    allow_next_instance_of(::Ai::DuoWorkflows::GenerateAgentConfigService) do |service|
      allow(service).to receive(:execute).and_return(service_response)
    end

    sign_in(user)
  end

  describe 'POST #create' do
    it 'starts the generation and returns the workflow id' do
      post path

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response).to eq({ 'workflow_id' => 99 })
    end

    it 'builds the service for the project and the current user' do
      expect(::Ai::DuoWorkflows::GenerateAgentConfigService).to receive(:new)
        .with(project: project, current_user: user)
        .and_return(instance_double(::Ai::DuoWorkflows::GenerateAgentConfigService, execute: service_response))

      post path

      expect(response).to have_gitlab_http_status(:created)
    end

    context 'when the service fails because a run is already active' do
      let(:service_response) do
        ServiceResponse.error(
          message: 'An agent configuration run is already in progress.', payload: { workflow_id: 55 }
        )
      end

      it 'returns the message and the workflow id so the row can link the session' do
        post path

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(
          { 'message' => 'An agent configuration run is already in progress.', 'workflow_id' => 55 }
        )
      end
    end

    context 'when the service fails without an active run' do
      let(:service_response) { ServiceResponse.error(message: 'The agent configuration file already exists.') }

      it 'returns only the message' do
        post path

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq({ 'message' => 'The agent configuration file already exists.' })
      end
    end

    context 'when the readiness feature flag is off' do
      before do
        stub_feature_flags(duo_agent_readiness_settings: false)
      end

      it 'returns not found' do
        post path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    # The flow runs in CI, so it cannot start without remote flows.
    context 'when remote flows are disabled' do
      before do
        project.project_setting.update!(duo_remote_flows_enabled: false)
      end

      it 'returns not found' do
        post path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when Duo features are disabled for the project' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
      end

      it 'returns not found' do
        post path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is only a developer' do
      let(:user) { developer }

      it 'is forbidden, because generating the file configures the project' do
        post path

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end
end
