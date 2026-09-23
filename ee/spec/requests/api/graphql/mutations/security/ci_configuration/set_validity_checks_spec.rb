# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SetValidityChecks', feature_category: :secret_detection do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }

  let(:variables) { { namespace_path: project.full_path, enable: true } }
  let(:mutation) { graphql_mutation(:set_validity_checks, variables) }
  let(:mutation_response) { graphql_mutation_response(:setValidityChecks) }

  context 'when authorized' do
    before do
      stub_licensed_features(secret_detection_validity_checks: true)
    end

    it 'enables validity checks' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['validityChecksEnabled']).to be(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_setting do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
