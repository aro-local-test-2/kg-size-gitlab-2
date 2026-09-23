# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting a work item decision', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, group]) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let(:decision) { create(:work_item_decision, work_item: work_item) }
  let(:current_user) { reporter }
  let(:mutation_params) { { id: decision.to_global_id.to_s } }
  let(:mutation) { graphql_mutation(:work_item_decision_delete, mutation_params, 'decision { id } errors') }
  let(:mutation_response) { graphql_mutation_response(:work_item_decision_delete) }

  before do
    stub_licensed_features(ai_workflows: true)
  end

  context 'when decision_log feature flag is disabled' do
    before do
      stub_feature_flags(decision_log: false)
    end

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'when user does not have permission to update the work item' do
    let(:current_user) { guest }

    it 'returns a resource not available error and keeps the decision' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
      expect(WorkItems::Decision.exists?(decision.id)).to be(true)
    end
  end

  context 'when the decision does not exist' do
    let(:mutation_params) { { id: "gid://gitlab/WorkItems::Decision/#{non_existing_record_id}" } }

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'when user can update the work item' do
    it 'deletes the decision and returns it' do
      decision_gid = decision.to_global_id.to_s

      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { WorkItems::Decision.count }.by(-1)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['decision']).to eq('id' => decision_gid)
    end

    context 'when the decision is resolved' do
      let(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }

      it 'returns an error and keeps the decision' do
        decision

        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect(mutation_response['errors']).to include('Resolved decisions cannot be deleted')
        expect(mutation_response['decision']).to be_nil
      end
    end

    context 'when the decision is archived' do
      let(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

      it 'returns an error and keeps the decision' do
        decision

        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect(mutation_response['errors']).to include('Archived decisions cannot be deleted')
        expect(mutation_response['decision']).to be_nil
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:work_item_decision_delete, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, namespace: group) }

    let(:decision) { create(:work_item_decision, work_item: epic_work_item) }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it 'returns a resource not available error and keeps the decision' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
      expect(WorkItems::Decision.exists?(decision.id)).to be(true)
    end
  end

  context 'with group level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }

    let(:decision) { create(:work_item_decision, work_item: group_work_item) }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(:work_item_decision_delete, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
