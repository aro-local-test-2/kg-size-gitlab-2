# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Updating a work item decision', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, group]) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:origin_note) { create(:discussion_note_on_issue, noteable: work_item, project: project) }
  let_it_be(:resolving_note) { create(:note, noteable: work_item, project: project) }

  let_it_be(:original_discussion_id) { SecureRandom.hex(20) }
  let_it_be_with_reload(:decision) do
    create(
      :work_item_decision,
      work_item: work_item,
      description: 'Original context',
      discussion_id: original_discussion_id,
      source_link: 'https://example.com/original'
    )
  end

  let(:current_user) { reporter }
  let(:discussion_gid) { "gid://gitlab/Discussion/#{origin_note.discussion_id}" }
  let(:mutation_params) do
    {
      id: decision.to_global_id.to_s,
      title: 'Which cache should we use?',
      description: 'The current cache is slow',
      discussion_id: discussion_gid,
      source_link: 'https://docs.google.com/document/d/abc123'
    }
  end

  let(:mutation) { graphql_mutation(:work_item_decision_update, mutation_params, mutation_fields) }
  let(:mutation_response) { graphql_mutation_response(:work_item_decision_update) }
  let(:mutation_fields) do
    <<~FIELDS
      decision {
        id
        title
        description
        resolutionRationale
        discussionId
        sourceLink
        resolvedAt
        resolvedBy {
          id
        }
        resolvingNoteId
        noteUrl
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

  context 'when the decision does not exist' do
    let(:mutation_params) do
      { id: "gid://gitlab/WorkItems::Decision/#{non_existing_record_id}", title: 'Which cache should we use?' }
    end

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
    end
  end

  context 'when user can update the work item' do
    it 'updates the decision' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['decision']).to include(
        'id' => decision.to_global_id.to_s,
        'title' => 'Which cache should we use?',
        'description' => 'The current cache is slow',
        'discussionId' => discussion_gid,
        'sourceLink' => 'https://docs.google.com/document/d/abc123',
        'resolvedAt' => nil
      )

      expect(decision.reload.discussion_id).to eq(origin_note.discussion_id)
    end

    context 'when the decision is resolved' do
      let_it_be(:resolver) { create(:user, reporter_of: project) }
      let_it_be_with_reload(:decision) do
        create(:work_item_decision, :resolved, work_item: work_item, resolution_rationale: 'Original rationale')
      end

      let(:mutation_params) do
        {
          id: decision.to_global_id.to_s,
          title: 'Which cache should we use?',
          resolution_rationale: 'Redis is already in the stack',
          resolved_by_id: resolver.to_global_id.to_s,
          resolving_note_id: resolving_note.to_global_id.to_s
        }
      end

      it 'updates the resolution without touching resolvedAt' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { decision.reload.resolved_at }

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['decision']).to include(
          'title' => 'Which cache should we use?',
          'resolutionRationale' => 'Redis is already in the stack',
          'resolvedAt' => decision.resolved_at.iso8601,
          'resolvedBy' => { 'id' => resolver.to_global_id.to_s },
          'resolvingNoteId' => resolving_note.to_global_id.to_s,
          'noteUrl' => ::Gitlab::UrlBuilder.build(resolving_note)
        )
      end

      context 'when the resolver does not have access to the work item' do
        let_it_be(:outsider) { create(:user) }

        let(:mutation_params) { { id: decision.to_global_id.to_s, resolved_by_id: outsider.to_global_id.to_s } }

        it 'returns an error and does not update the decision' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to include('Resolver must have access to the work item')
          expect(mutation_response.dig('decision', 'resolvedBy', 'id')).to eq(decision.resolved_by.to_global_id.to_s)
        end
      end

      context 'when the resolving note belongs to another noteable' do
        let_it_be(:other_note) { create(:note) }

        let(:mutation_params) { { id: decision.to_global_id.to_s, resolving_note_id: other_note.to_global_id.to_s } }

        it 'returns an error and does not update the decision' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to include('Note cannot resolve this decision')
          expect(mutation_response.dig('decision', 'resolvingNoteId')).to be_nil
        end
      end
    end

    context 'when the decision is archived' do
      let_it_be_with_reload(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

      let(:mutation_params) { { id: decision.to_global_id.to_s, title: 'Which cache should we use?' } }

      it 'returns an error and does not update the decision' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Archived decisions cannot be updated')
        expect(mutation_response.dig('decision', 'title')).to eq('Which storage backend should we use?')
      end
    end

    context 'when a resolution argument is provided for an open decision' do
      let(:mutation_params) do
        { id: decision.to_global_id.to_s, resolution_rationale: 'Redis is already in the stack' }
      end

      it 'returns an error and does not update the decision' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include(
          'Resolution rationale can only be updated on resolved decisions'
        )
        expect(mutation_response.dig('decision', 'resolutionRationale')).to be_nil
      end
    end

    context 'when only some arguments are provided' do
      let(:mutation_params) { { id: decision.to_global_id.to_s, title: 'Which cache should we use?' } }

      it 'leaves the other fields untouched' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['decision']).to eq(
          'id' => decision.to_global_id.to_s,
          'title' => 'Which cache should we use?',
          'description' => 'Original context',
          'resolutionRationale' => nil,
          'discussionId' => "gid://gitlab/Discussion/#{original_discussion_id}",
          'sourceLink' => 'https://example.com/original',
          'resolvedAt' => nil,
          'resolvedBy' => nil,
          'resolvingNoteId' => nil,
          'noteUrl' => nil
        )
      end
    end

    context 'when no updatable argument is provided' do
      let(:mutation_params) { { id: decision.to_global_id.to_s } }

      it 'returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          'At least one of [title, description, resolutionRationale, discussionId, sourceLink, ' \
            'resolvedById, resolvingNoteId] arguments is required.'
        )
      end
    end

    context 'when a provided argument is blank' do
      using RSpec::Parameterized::TableSyntax

      where(:argument, :value) do
        :title                | nil
        :title                | ''
        :title                | '   '
        :description          | ''
        :resolution_rationale | nil
        :discussion_id        | nil
        :source_link          | "\t"
        :resolved_by_id       | nil
        :resolving_note_id    | nil
      end

      with_them do
        let(:mutation_params) { { id: decision.to_global_id.to_s, argument => value } }

        it 'returns an error and does not update the decision' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect_graphql_errors_to_include("#{argument.to_s.camelize(:lower)} can't be blank")
          expect(decision.reload.title).to eq('Which storage backend should we use?')
        end
      end
    end

    context 'when the source link is not a valid URL' do
      let(:mutation_params) { { id: decision.to_global_id.to_s, source_link: 'not a url' } }

      it 'returns an error and does not update the decision' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('Source link is blocked: Only allowed schemes are http, https')
        expect(mutation_response.dig('decision', 'sourceLink')).to eq('https://example.com/original')
      end
    end

    context 'when the title is too long' do
      let(:mutation_params) do
        { id: decision.to_global_id.to_s, title: 'a' * (WorkItems::Decision::TITLE_LENGTH_MAX + 1) }
      end

      it 'returns an error and does not update the decision' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include(
          "Title is too long (maximum is #{WorkItems::Decision::TITLE_LENGTH_MAX} characters)"
        )
        expect(mutation_response.dig('decision', 'title')).to eq('Which storage backend should we use?')
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:work_item_decision_update, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, namespace: group) }
    let_it_be(:epic_decision) { create(:work_item_decision, work_item: epic_work_item) }

    let(:mutation_params) { { id: epic_decision.to_global_id.to_s, title: 'Which cache should we use?' } }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The resource that you are attempting to access does not exist')
      expect(epic_decision.reload.title).to eq('Which storage backend should we use?')
    end
  end

  context 'with group level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:group_decision) { create(:work_item_decision, work_item: group_work_item) }

    let(:mutation_params) { { id: group_decision.to_global_id.to_s, title: 'Which cache should we use?' } }

    before do
      stub_licensed_features(epics: true, ai_workflows: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(:work_item_decision_update, mutation_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
