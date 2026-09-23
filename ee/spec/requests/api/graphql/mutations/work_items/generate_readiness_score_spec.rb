# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Generate a readiness score for a work item', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let(:current_user) { developer }
  let(:fields) { 'workflow { id } errors' }
  let(:input) { { 'id' => work_item.to_global_id.to_s } }
  let(:mutation) { graphql_mutation(:workItemGenerateReadinessScore, input, fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_generate_readiness_score) }

  context 'when the service starts a workflow' do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: developer) }

    before do
      # Exercises the real GenerateReadinessScoreService; only the CI-backed workflow
      # creation is stubbed, since that's covered by the service's own specs.
      allow(::Ai::DuoWorkflows::CreateAndStartWorkflowService).to receive(:new).and_return(
        instance_double(::Ai::DuoWorkflows::CreateAndStartWorkflowService,
          execute: ServiceResponse.success(payload: { workflow: workflow }))
      )

      # Focus this spec on the mutation wiring; the WorkflowType's own read
      # authorization (duo licensing) is covered by its own specs.
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(developer, :read_duo_workflow, workflow).and_return(true)
    end

    it 'returns the started workflow', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['workflow']).to be_present
    end
  end

  context 'when the service returns an error' do
    before do
      allow_next_instance_of(::Ai::DuoWorkflows::GenerateReadinessScoreService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(
            message: 'Readiness score generation is not enabled for this project',
            reason: :feature_disabled
          )
        )
      end
    end

    it 'surfaces the error and returns no workflow', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['workflow']).to be_nil
      expect(mutation_response['errors']).to include('Readiness score generation is not enabled for this project')
    end
  end

  context 'when the user cannot update the work item' do
    let(:current_user) { create(:user) }

    it 'returns a resource-not-available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(
        a_hash_including('message' => a_string_including("does not exist or you don't have permission"))
      )
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:mutation) { graphql_mutation(:workItemGenerateReadinessScore, input, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

    before do
      allow_next_instance_of(::Ai::DuoWorkflows::GenerateReadinessScoreService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: nil }))
      end
    end
  end
end
