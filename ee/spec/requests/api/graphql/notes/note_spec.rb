# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.note(id)', feature_category: :team_planning do
  include GraphqlHelpers

  describe 'for a group-level note' do
    let_it_be(:group) { create(:group) }
    let_it_be(:user) { create(:user, developer_of: group) }
    let_it_be_with_reload(:epic) { create(:epic, group: group) }
    let_it_be(:note) { create(:note, project: nil, noteable: epic) }

    let(:query) { graphql_query_for('note', { 'id' => global_id_of(note) }, 'id body') }

    before do
      stub_licensed_features(epics: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_note do
      let(:boundary_object) { group }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  # Only EE adds :ai_workflows to the scopes accepted for GraphQL requests
  # (ee/lib/ee/gitlab/auth/request_authenticator.rb), so these examples cannot live in the
  # CE spec: FOSS rejects the token before any field resolves.
  describe 'awardEmoji when authenticated with a token that has the ai_workflows scope' do
    let_it_be(:reporter_user) { create(:user) }
    let_it_be(:project) { create(:project, :private, reporters: reporter_user) }
    let_it_be(:issue, freeze: false) { create(:issue, project: project) }
    # Awarding an emoji bumps the note, so it cannot be frozen.
    let_it_be(:note, freeze: false) { create(:note, noteable: issue, project: project) }
    let_it_be(:oauth_token) { create(:oauth_access_token, user: reporter_user, scopes: [:ai_workflows]) }

    let(:note_params) { { 'id' => global_id_of(note) } }

    let(:award_emoji_fields) do
      <<~FIELDS
        id
        awardEmoji {
          nodes {
            name
            user {
              username
            }
          }
        }
      FIELDS
    end

    let(:query) { graphql_query_for('note', note_params, award_emoji_fields) }

    before do
      post_graphql(query, token: { oauth_access_token: oauth_token })
    end

    context 'when the note has reactions' do
      let_it_be(:downvote) { create(:award_emoji, :downvote, awardable: note, user: reporter_user) }

      it 'returns the reactions' do
        expect(graphql_data_at(:note, :award_emoji, :nodes)).to contain_exactly(
          { 'name' => AwardEmoji::THUMBS_DOWN, 'user' => { 'username' => reporter_user.username } }
        )
      end
    end

    context 'when the note has no reactions' do
      it 'returns an empty connection rather than nil' do
        expect(graphql_data_at(:note, :id)).to eq(global_id_of(note).to_s)
        expect(graphql_data_at(:note, :award_emoji, :nodes)).to eq([])
      end
    end

    shared_examples 'a noteable outside the allowlist' do
      let(:note_params) { { 'id' => global_id_of(unlisted_note) } }

      it 'does not expose the reactions' do
        expect(graphql_data_at(:note, :id)).to eq(global_id_of(unlisted_note).to_s)
        expect(graphql_data_at(:note, :award_emoji)).to be_nil
      end

      context 'when the token carries the api scope' do
        let(:oauth_token) { create(:oauth_access_token, user: reporter_user, scopes: [:api]) }

        it 'exposes the reactions' do
          expect(graphql_data_at(:note, :award_emoji, :nodes)).to contain_exactly(
            { 'name' => AwardEmoji::THUMBS_DOWN, 'user' => { 'username' => reporter_user.username } }
          )
        end
      end
    end

    context 'when the note is on a merge request' do
      let_it_be(:merge_request_note, freeze: false) { create(:note_on_merge_request, project: project) }
      let_it_be(:merge_request_reaction) do
        create(:award_emoji, :downvote, awardable: merge_request_note, user: reporter_user)
      end

      let(:note_params) { { 'id' => global_id_of(merge_request_note) } }

      it 'returns the reactions' do
        expect(graphql_data_at(:note, :award_emoji, :nodes)).to contain_exactly(
          { 'name' => AwardEmoji::THUMBS_DOWN, 'user' => { 'username' => reporter_user.username } }
        )
      end
    end

    context 'when the note is on a snippet' do
      let_it_be(:unlisted_note, freeze: false) { create(:note_on_project_snippet, project: project) }
      let_it_be(:snippet_reaction) do
        create(:award_emoji, :downvote, awardable: unlisted_note, user: reporter_user)
      end

      it_behaves_like 'a noteable outside the allowlist'
    end

    context 'when the note is on a wiki page' do
      let_it_be(:unlisted_note, freeze: false) { create(:note_on_wiki_page, project: project) }
      let_it_be(:wiki_page_reaction) do
        create(:award_emoji, :downvote, awardable: unlisted_note, user: reporter_user)
      end

      it_behaves_like 'a noteable outside the allowlist'
    end
  end
end
