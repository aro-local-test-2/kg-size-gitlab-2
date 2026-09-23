# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting project label information', feature_category: :team_planning do
  include GraphqlHelpers

  context 'when authenticated with an OAuth token carrying the ai_workflows scope' do
    let_it_be(:developer) { create(:user) }
    let_it_be(:private_project) { create(:project, :private) }
    let_it_be(:private_project_label) { create(:label, project: private_project, title: 'testing') }
    let_it_be(:oauth_token) { create(:oauth_access_token, user: developer, scopes: [:ai_workflows]) }

    let(:query) do
      graphql_query_for('project', { full_path: private_project.full_path }, [
        query_graphql_field(:labels, { title: 'testing' }, [query_graphql_field(:nodes, nil, %w[id title])])
      ])
    end

    before_all do
      private_project.add_developer(developer)
    end

    it 'returns the labels', :aggregate_failures do
      post_graphql(query, token: { oauth_access_token: oauth_token })

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :labels, :nodes)).to contain_exactly(
        a_hash_including('id' => private_project_label.to_global_id.to_s, 'title' => 'testing')
      )
    end
  end
end
