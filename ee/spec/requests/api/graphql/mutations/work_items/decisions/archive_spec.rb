# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Archiving a work item decision', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, group]) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }

  let(:current_user) { reporter }
  let(:mutation_params) { { id: decision.to_global_id.to_s } }
  let(:mutation) { graphql_mutation(:work_item_decision_archive, mutation_params, mutation_fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_decision_archive) }
  let(:mutation_fields) do
    <<~FIELDS
      decision {
        id
        state
        archivedAt
        resolvedAt
        resolvedBy {
          id
        }
      }
      errors
    FIELDS
  end

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

    it 'returns a resource not available error and does not archive the decision' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { decision.reload.archived_at }.from(nil)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
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
    it 'archives the decision and keeps the resolution' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { decision.reload.archived_at }.from(nil)
        .and not_change { decision.reload.slice(:resolved_at, :resolved_by_id) }

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['decision']).to eq(
        'id' => decision.to_global_id.to_s,
        'state' => 'ARCHIVED',
        'archivedAt' => decision.archived_at.iso8601,
        'resolvedAt' => decision.resolved_at.iso8601,
        'resolvedBy' => { 'id' => decision.resolved_by.to_global_id.to_s }
      )
    end

    context 'when the decision is already archived' do
      let_it_be_with_reload(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

      it 'returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Decision is already archived')
        expect(mutation_response.dig('decision', 'id')).to eq(decision.to_global_id.to_s)
      end
    end

    context 'when the decision is not resolved' do
      let_it_be_with_reload(:decision) { create(:work_item_decision, work_item: work_item) }

      it 'returns an error and keeps the decision active' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { decision.reload.archived_at }.from(nil)

        expect(mutation_response['errors']).to include('Only resolved decisions can be archived')
        expect(mutation_response['decision']).to include(
          'id' => decision.to_global_id.to_s, 'state' => 'ACTIVE', 'archivedAt' => nil, 'resolvedAt' => nil
        )
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:work_item_decision_archive, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, namespace: group) }
    let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: epic_work_item) }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it 'returns a resource not available error and does not archive the decision' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { decision.reload.archived_at }.from(nil)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'with group level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:decision) { create(:work_item_decision, :resolved, work_item: group_work_item) }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(:work_item_decision_archive, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
