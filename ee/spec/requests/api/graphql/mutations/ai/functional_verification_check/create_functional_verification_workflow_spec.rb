# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CreateFunctionalVerificationWorkflow', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:user) { create(:admin) }
  let_it_be(:namespace) { create(:group) }

  let(:mutation) do
    graphql_mutation(
      :create_functional_verification_workflow,
      { full_path: namespace.full_path, check_type: 'AGENTIC_CHAT' },
      <<~GQL
        workflowId
        errors
      GQL
    )
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: user) }

  before do
    allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
      .with(user).and_return(true)
  end

  context 'when the verification check is not enabled for the user' do
    before do
      allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
        .with(user).and_return(false)
    end

    it 'returns a resource not available error without creating a workflow' do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'when the namespace does not exist' do
    let(:mutation) do
      graphql_mutation(
        :create_functional_verification_workflow,
        { full_path: 'does-not-exist', check_type: 'AGENTIC_CHAT' },
        <<~GQL
          workflowId
          errors
        GQL
      )
    end

    it 'returns a resource not available error without creating a workflow' do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'when Duo is not enabled for the namespace' do
    let(:namespace) { create(:group) }

    before do
      namespace.namespace_settings.update!(duo_features_enabled: false, lock_duo_features_enabled: false)
    end

    it 'returns a resource not available error without creating a workflow' do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'when the user cannot read the namespace' do
    before do
      allow(::Ability).to receive(:allowed?).and_call_original
      allow(::Ability).to receive(:allowed?).with(user, :read_namespace, namespace).and_return(false)
    end

    it 'returns a resource not available error without creating a workflow' do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end

  context 'with granular token permissions', :enable_admin_mode do
    let(:workflow) { create(:duo_workflows_workflow, namespace: namespace, user: user) }
    let(:service_instance) { instance_double(::Ai::DuoWorkflows::CreateWorkflowService) }

    before do
      allow(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new).and_return(service_instance)
      allow(service_instance).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: workflow }))
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_functional_verification_workflow do
      let(:boundary_object) { :instance }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'when CreateWorkflowService succeeds' do
    let(:workflow) { create(:duo_workflows_workflow, namespace: namespace, user: user) }
    let(:service_instance) { instance_double(::Ai::DuoWorkflows::CreateWorkflowService) }

    before do
      allow(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new)
        .with(
          container: namespace,
          current_user: user,
          params: {
            goal: Mutations::Ai::FunctionalVerificationCheck::CreateFunctionalVerificationWorkflow::GOALS[:agentic_chat],
            workflow_definition:
              Mutations::Ai::FunctionalVerificationCheck::CreateFunctionalVerificationWorkflow::WORKFLOW_DEFINITIONS[
                :agentic_chat],
            trigger_source: :verification
          }
        ).and_return(service_instance)
      allow(service_instance).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: workflow }))
    end

    it 'marks a verification run as running and returns the workflow id', :aggregate_failures do
      expect(::Ai::DuoAgentPlatform::FunctionalVerificationRunService).to receive(:new)
        .with(check_type: :agentic_chat).and_call_original
      expect_any_instance_of(::Ai::DuoAgentPlatform::FunctionalVerificationRunService) do |service|
        expect(service).to receive(:mark_running).with(workflow_id: workflow.id)
      end

      request

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to be_blank
      expect(graphql_data_at(:create_functional_verification_workflow, :errors)).to be_empty
      expect(graphql_data_at(:create_functional_verification_workflow, :workflow_id))
        .to eq(workflow.to_global_id.to_s)
    end
  end

  context 'when CreateWorkflowService returns an error' do
    let(:service_instance) { instance_double(::Ai::DuoWorkflows::CreateWorkflowService) }

    before do
      allow(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new).and_return(service_instance)
      allow(service_instance).to receive(:execute).and_return(ServiceResponse.error(message: 'boom'))
    end

    it 'returns an error without marking a verification run as running' do
      expect(::Ai::DuoAgentPlatform::FunctionalVerificationRunService).not_to receive(:new)

      request

      expect(graphql_errors).not_to be_blank
    end
  end
end
