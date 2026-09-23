# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a work item decision', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, group]) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:origin_note) { create(:discussion_note_on_issue, noteable: work_item, project: project) }

  let(:current_user) { reporter }
  # Drawn from a real thread, matching the FE's source; the backend still
  # stores it as opaque provenance and never verifies the discussion exists
  let(:discussion_id) { origin_note.discussion_id }
  let(:mutation_params) do
    {
      work_item_id: work_item.to_global_id.to_s,
      title: 'Which storage backend should we use?',
      description: 'We need to settle this before implementation',
      discussion_id: "gid://gitlab/Discussion/#{discussion_id}",
      source_link: 'https://docs.google.com/document/d/abc123',
      options: [
        { content: 'Use PostgreSQL', recommended: true, description: 'Matches the existing stack' },
        { content: 'Use Redis' }
      ]
    }
  end

  let(:mutation) { graphql_mutation(:work_item_decision_create, mutation_params, mutation_fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_decision_create) }
  let(:mutation_fields) do
    <<~FIELDS
      decision {
        id
        title
        description
        discussionId
        sourceLink
        resolvedAt
        resolvedBy { id }
        resolutionRationale
        options {
          nodes {
            content
            recommended
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
    it 'creates the decision with its options' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { work_item.decisions.count }.by(1)
        .and change { WorkItems::DecisionOption.count }.by(2)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['decision']).to include(
        'title' => 'Which storage backend should we use?',
        'description' => 'We need to settle this before implementation',
        'discussionId' => "gid://gitlab/Discussion/#{discussion_id}",
        'sourceLink' => 'https://docs.google.com/document/d/abc123',
        'resolvedAt' => nil,
        'resolvedBy' => nil
      )
      expect(mutation_response.dig('decision', 'options', 'nodes')).to contain_exactly(
        a_hash_including('content' => 'Use PostgreSQL', 'recommended' => true, 'selected' => false),
        a_hash_including('content' => 'Use Redis', 'recommended' => false, 'selected' => false)
      )
    end

    context 'when source_link is not a valid URL' do
      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          title: 'Which storage backend should we use?',
          source_link: 'not a url'
        }
      end

      it 'returns validation errors and creates nothing' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect(mutation_response['decision']).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/Source link/))
      end
    end

    context 'when more options than the limit are given' do
      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          title: 'Which storage backend should we use?',
          options: Array.new(WorkItems::Decision::MAX_OPTIONS_PER_DECISION + 1) { |i| { content: "Option #{i}" } }
        }
      end

      it 'returns an error and creates nothing' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect_graphql_errors_to_include(
          "options is too long (maximum is #{WorkItems::Decision::MAX_OPTIONS_PER_DECISION})"
        )
      end
    end

    context 'when resolution is explicitly null' do
      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          title: 'Which storage backend should we use?',
          resolution: nil
        }
      end

      it 'creates an open decision' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .to change { work_item.decisions.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response.dig('decision', 'resolvedAt')).to be_nil
      end
    end

    context 'when creating a resolved decision' do
      let(:resolution_params) do
        { decision: 'Use PostgreSQL for the storage backend', rationale: 'Settled in the design sync' }
      end

      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          source_link: 'https://docs.google.com/document/d/abc123',
          resolution: resolution_params
        }
      end

      it 'creates the resolved decision with the made decision as its selected option' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .to change { work_item.decisions.count }.by(1)
          .and change { WorkItems::DecisionOption.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['decision']).to include(
          'title' => nil,
          'resolutionRationale' => 'Settled in the design sync',
          'resolvedBy' => { 'id' => current_user.to_gid.to_s }
        )
        expect(mutation_response.dig('decision', 'resolvedAt')).to be_present
        expect(mutation_response.dig('decision', 'options', 'nodes')).to contain_exactly(
          a_hash_including('content' => 'Use PostgreSQL for the storage backend', 'selected' => true)
        )
      end

      context 'when attributing the resolution to another user' do
        let_it_be(:resolver_user) { create(:user, reporter_of: project) }

        let(:resolution_params) do
          { decision: 'Go with Redis', resolved_by_id: resolver_user.to_gid.to_s }
        end

        it 'records the given user as the resolver' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response.dig('decision', 'resolvedBy', 'id')).to eq(resolver_user.to_gid.to_s)
        end
      end

      context 'when the resolver cannot access the work item' do
        let_it_be(:outsider) { create(:user) }

        let(:resolution_params) { { decision: 'Go with Redis', resolved_by_id: outsider.to_gid.to_s } }

        it 'returns an error and creates nothing' do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { WorkItems::Decision.count }

          expect(mutation_response['errors']).to include(a_string_matching(/Resolver must have access/))
        end
      end

      context 'when options are also given' do
        let(:mutation_params) do
          {
            work_item_id: work_item.to_global_id.to_s,
            resolution: resolution_params,
            options: [{ content: 'Use PostgreSQL' }]
          }
        end

        it 'returns an error and creates nothing' do
          expect { post_graphql_mutation(mutation, current_user: current_user) }
            .not_to change { WorkItems::Decision.count }

          expect_graphql_errors_to_include(
            'Only one of [options, resolution] arguments is allowed at the same time.'
          )
        end
      end
    end

    context 'when neither title nor resolution is given' do
      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          options: [{ content: 'Use PostgreSQL' }]
        }
      end

      it 'returns an error and creates nothing' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect_graphql_errors_to_include('At least one of [title, resolution] arguments is required.')
      end
    end

    context 'when the decision is invalid' do
      let(:mutation_params) do
        {
          work_item_id: work_item.to_global_id.to_s,
          title: 'a' * (WorkItems::Decision::TITLE_LENGTH_MAX + 1)
        }
      end

      it 'returns validation errors and creates nothing' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::Decision.count }

        expect(mutation_response['decision']).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/Title is too long/))
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:work_item_decision_create, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, namespace: group) }

    let(:mutation_params) do
      {
        work_item_id: epic_work_item.to_global_id.to_s,
        title: 'Epic question'
      }
    end

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it 'returns a resource not available error' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { WorkItems::Decision.count }

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'with group level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }

    let(:mutation_params) do
      {
        work_item_id: group_work_item.to_global_id.to_s,
        title: 'Group-level question'
      }
    end

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(:work_item_decision_create, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
