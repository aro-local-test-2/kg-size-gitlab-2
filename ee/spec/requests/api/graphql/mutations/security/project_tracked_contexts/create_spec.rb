# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SecurityRefsTrack', feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:maintainer) { create(:user) }

  let(:current_user) { maintainer }

  let(:input) do
    {
      projectPath: project.full_path,
      refs: [{ name: project.default_branch, refType: 'BRANCH' }]
    }
  end

  let(:mutation) { graphql_mutation(:security_refs_track, input, tracked_refs_fields) }

  def tracked_refs_fields
    <<~FIELDS
      trackedRefs {
        id
        name
        refType
      }
      errors
    FIELDS
  end

  def mutation_result
    graphql_mutation_response(:security_refs_track)
  end

  before_all do
    project.add_maintainer(maintainer)
  end

  before do
    stub_licensed_features(security_dashboard: true)
    stub_feature_flags(vulnerabilities_across_contexts: project.root_namespace)
  end

  describe 'GraphQL mutation' do
    context 'when user has permissions' do
      it_behaves_like 'authorizing granular token permissions for GraphQL', :create_security_project_tracked_ref do
        let(:user) { current_user }
        let(:boundary_object) { project }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      it 'tracks the ref' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_result['errors']).to be_empty
        expect(mutation_result['trackedRefs']).to contain_exactly(
          a_hash_including('name' => project.default_branch, 'refType' => 'BRANCH')
        )
      end
    end
  end
end
