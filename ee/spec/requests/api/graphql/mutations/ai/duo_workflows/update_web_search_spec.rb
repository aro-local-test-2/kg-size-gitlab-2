# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'UpdateDuoWorkflowWebSearch', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  let(:web_search_enabled) { true }
  let(:service_instance) { instance_double(::Ai::DuoWorkflows::UpdateWebSearchService) }

  let(:current_user) { user }

  let(:mutation) do
    graphql_mutation(
      :update_duo_workflow_web_search,
      {
        workflow_id: workflow.to_global_id.to_s,
        web_search_enabled: web_search_enabled
      },
      <<~GQL
        workflow {
          id
          webSearchEnabled
        }
        errors
      GQL
    )
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: user) }

  context 'when dap_web_search feature flag is disabled' do
    before do
      stub_feature_flags(dap_web_search: false)
    end

    it 'returns a resource not available error' do
      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'when user has permission to update workflow' do
    before_all do
      project.add_maintainer(user)
    end

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :update_duo_workflow, workflow).and_return(true)
      allow(Ability).to receive(:allowed?).with(user, :read_duo_workflow, workflow).and_return(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_duo_workflow do
      let(:boundary_object) { :user }
      let(:authz_mutation) do
        graphql_mutation(
          :update_duo_workflow_web_search,
          { workflow_id: workflow.to_global_id.to_s, web_search_enabled: true },
          'errors'
        )
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end

    context 'when updating web search setting' do
      let(:workflow) { create(:duo_workflows_workflow, project: project, user: user, web_search_enabled: false) }

      it 'persists the value and returns success', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_blank
        expect(graphql_data_at(:update_duo_workflow_web_search, :errors)).to be_empty

        workflow_id = graphql_data_at(:update_duo_workflow_web_search, :workflow, :id)
        expect(workflow_id).to eq(workflow.to_global_id.to_s)

        persisted_workflow = GlobalID::Locator.locate(workflow_id)
        expect(persisted_workflow.web_search_enabled).to be true
      end
    end

    context 'when service returns an error' do
      it 'returns the error message', :aggregate_failures do
        allow(::Ai::DuoWorkflows::UpdateWebSearchService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:execute).and_return(
          ServiceResponse.error(message: 'Failed to update web search setting')
        )

        request

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_blank
        expect(graphql_data_at(:update_duo_workflow_web_search, :workflow)).to be_nil
        expect(graphql_data_at(:update_duo_workflow_web_search, :errors))
          .to include('Failed to update web search setting')
      end
    end
  end

  context 'when user lacks permission' do
    let_it_be(:other_user) { create(:user) }

    subject(:request) { post_graphql_mutation(mutation, current_user: other_user) }

    it 'returns authorization error without calling the service', :aggregate_failures do
      expect(::Ai::DuoWorkflows::UpdateWebSearchService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
      expect(graphql_errors.first['message']).to include("don't have permission")
    end
  end

  context 'when workflow does not exist' do
    let(:mutation) do
      graphql_mutation(
        :update_duo_workflow_web_search,
        {
          workflow_id: "gid://gitlab/Ai::DuoWorkflows::Workflow/#{non_existing_record_id}",
          web_search_enabled: true
        },
        <<~GQL
          errors
        GQL
      )
    end

    it 'returns not found error without calling the service', :aggregate_failures do
      expect(::Ai::DuoWorkflows::UpdateWebSearchService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'when identity verification is required', :saas do
    let_it_be_with_reload(:trial_group) do
      create(:group_with_plan, plan: :ultimate_trial_plan, trial: true,
        trial_starts_on: Date.current, trial_ends_on: 30.days.from_now, developers: user)
    end

    let_it_be(:trial_project) { create(:project, group: trial_group) }
    let_it_be(:trial_workflow) { create(:duo_workflows_workflow, project: trial_project, user: user) }

    let(:workflow) { trial_workflow }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_licensed_features(ai_features: true)
      create(:gitlab_subscription_add_on_purchase, :active_trial, :duo_core, namespace: trial_group)
      trial_group.namespace_settings.update!(duo_features_enabled: true, duo_core_features_enabled: true)
      trial_group.ai_settings.update!(duo_agent_platform_enabled: true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)

      allow_next_found_instance_of(User) do |found_user|
        allow(found_user).to receive(:identity_verified?).and_return(false)
      end
    end

    it 'raises identity verification error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors.first['message'])
        .to eq(s_('DuoAgentsPlatform|Identity verification is required to use GitLab Duo Agent Platform'))
    end
  end
end
