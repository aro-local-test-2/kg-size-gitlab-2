# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resume a paused workplan generation for a work item', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let(:current_user) { developer }
  let(:fields) { 'workflow { id } errors' }
  let(:input) { { 'id' => work_item.to_global_id.to_s } }
  let(:mutation) { graphql_mutation(:workItemResumeWorkplan, input, fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_resume_workplan) }

  context 'when the service resumes the workflow' do
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: developer, issue_id: work_item.id,
        workflow_definition: 'workplan/v1')
    end

    before do
      # Asserted on the constructor rather than stubbed loosely, so a regression
      # in what `resolve` passes the service fails here.
      expect_next_instance_of(
        ::Ai::DuoWorkflows::ResumeWorkplanService, work_item: work_item, current_user: developer
      ) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: workflow }))
      end

      # Focus this spec on the mutation wiring; the WorkflowType's own read
      # authorization (duo licensing) is covered by its own specs.
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(developer, :read_duo_workflow, workflow).and_return(true)
    end

    it 'returns the resumed workflow', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['workflow']).to be_present
    end
  end

  context 'when the service returns an error' do
    before do
      allow_next_instance_of(::Ai::DuoWorkflows::ResumeWorkplanService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(
            message: ::Ai::DuoWorkflows::ResumeWorkplanService::NOT_RESUMABLE_ERROR,
            reason: :not_resumable
          )
        )
      end
    end

    it 'surfaces the error and returns no workflow', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['workflow']).to be_nil
      expect(mutation_response['errors'])
        .to include(::Ai::DuoWorkflows::ResumeWorkplanService::NOT_RESUMABLE_ERROR)
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
    let(:mutation) { graphql_mutation(:workItemResumeWorkplan, input, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

    before do
      allow_next_instance_of(::Ai::DuoWorkflows::ResumeWorkplanService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: nil }))
      end
    end
  end
end
