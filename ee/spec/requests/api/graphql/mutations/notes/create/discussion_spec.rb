# frozen_string_literal: true

require 'spec_helper'

# Only EE adds :ai_workflows to the scopes accepted for GraphQL requests
# (ee/lib/ee/gitlab/auth/request_authenticator.rb). In CE, authentication fails before
# any field resolves, so examples authenticating with that scope must live here.
RSpec.describe 'Adding a DiscussionNote with an ai_workflows scoped token',
  feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be(:token) { create(:oauth_access_token, user: current_user, scopes: [:ai_workflows]) }

  let(:noteable) { create(:merge_request, source_project: project, target_project: project) }

  # `userPermissions` (and other fields without :ai_workflows in their own
  # `scopes:`) aren't readable by this token, so select only the fields an
  # :ai_workflows caller actually requests instead of the default full set.
  let(:mutation) do
    variables = {
      noteable_id: GitlabSchema.id_from_object(noteable).to_s,
      body: 'Body text'
    }

    graphql_mutation(:create_discussion, variables, 'errors note { id body }')
  end

  def mutation_response
    graphql_mutation_response(:create_discussion)
  end

  it 'creates the discussion', :aggregate_failures do
    expect do
      post_graphql_mutation(mutation, token: { oauth_access_token: token })
    end.to change { DiscussionNote.count }.by(1)

    expect(response).to have_gitlab_http_status(:success)
    expect(mutation_response['errors']).to be_empty
    expect(mutation_response['note']['body']).to eq('Body text')
  end
end
