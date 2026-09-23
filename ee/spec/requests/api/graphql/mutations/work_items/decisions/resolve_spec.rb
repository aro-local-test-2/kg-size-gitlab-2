# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resolving a work item decision', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, group]) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:resolving_note) { create(:note, noteable: work_item, project: project) }

  let_it_be_with_reload(:decision) { create(:work_item_decision, work_item: work_item) }
  let_it_be_with_reload(:option) { create(:work_item_decision_option, decision: decision) }

  let(:current_user) { reporter }
  let(:mutation_params) do
    {
      id: decision.to_global_id.to_s,
      resolution_rationale: 'Chosen for consistency with the stack',
      selected_option_ids: [option.to_global_id.to_s],
      resolving_note_id: resolving_note.to_global_id.to_s
    }
  end

  let(:mutation) { graphql_mutation(:work_item_decision_resolve, mutation_params, mutation_fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_decision_resolve) }
  let(:mutation_fields) do
    <<~FIELDS
      decision {
        id
        resolutionRationale
        resolvedAt
        noteUrl
        resolvedBy {
          id
        }
        options {
          nodes {
            id
            selected
          }
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

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'when user can update the work item' do
    it 'resolves the decision and selects the options' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['decision']).to include(
        'resolutionRationale' => 'Chosen for consistency with the stack',
        'noteUrl' => ::Gitlab::UrlBuilder.build(resolving_note)
      )
      expect(mutation_response.dig('decision', 'resolvedAt')).to be_present
      expect(mutation_response.dig('decision', 'resolvedBy', 'id')).to eq(current_user.to_global_id.to_s)
      expect(mutation_response.dig('decision', 'options', 'nodes')).to contain_exactly(
        a_hash_including('id' => option.to_global_id.to_s, 'selected' => true)
      )

      expect(decision.reload).to have_attributes(
        resolved_by: current_user,
        resolving_note: resolving_note
      )
    end

    context 'when the decision is already resolved' do
      before do
        decision.update!(resolved_at: Time.current, resolved_by: reporter)
      end

      it 'returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Decision is already resolved')
      end
    end

    context 'when the resolving note is a system note' do
      let_it_be(:system_note) { create(:note, :system, noteable: work_item, project: project) }

      let(:mutation_params) do
        {
          id: decision.to_global_id.to_s,
          resolving_note_id: system_note.to_global_id.to_s
        }
      end

      it 'returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Note cannot resolve this decision')
      end
    end

    context 'when rejecting all options without a rationale' do
      let(:mutation_params) { { id: decision.to_global_id.to_s } }

      it 'returns an error and does not resolve the decision' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Resolution rationale is required when rejecting all options')
        expect(decision.reload.resolved_at).to be_nil
      end
    end

    context 'when more options than the limit are selected' do
      let(:mutation_params) do
        {
          id: decision.to_global_id.to_s,
          selected_option_ids: Array.new(WorkItems::Decision::MAX_OPTIONS_PER_DECISION + 1) do |i|
            "gid://gitlab/WorkItems::DecisionOption/#{i + 1}"
          end
        }
      end

      it 'returns an error and resolves nothing' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          "selectedOptionIds is too long (maximum is #{WorkItems::Decision::MAX_OPTIONS_PER_DECISION})"
        )
        expect(decision.reload.resolved_at).to be_nil
      end
    end

    context 'when a selected option belongs to another decision' do
      let_it_be(:other_option) { create(:work_item_decision_option) }

      let(:mutation_params) do
        {
          id: decision.to_global_id.to_s,
          selected_option_ids: [other_option.to_global_id.to_s]
        }
      end

      it 'returns an error and selects nothing' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Selected options must belong to the decision')
        expect(other_option.reload.selected).to be(false)
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:work_item_decision_resolve, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, namespace: group) }
    let_it_be(:epic_decision) { create(:work_item_decision, work_item: epic_work_item) }

    let(:mutation_params) { { id: epic_decision.to_global_id.to_s } }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
      expect(epic_decision.reload.resolved_at).to be_nil
    end
  end

  context 'with group level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:group_decision) { create(:work_item_decision, work_item: group_work_item) }

    let(:mutation_params) { { id: group_decision.to_global_id.to_s } }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(:work_item_decision_resolve, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
