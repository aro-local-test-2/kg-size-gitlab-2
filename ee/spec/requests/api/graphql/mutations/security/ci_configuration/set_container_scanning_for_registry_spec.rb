# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SetContainerScanningForRegistry', feature_category: :container_scanning do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }

  let(:variables) { { namespace_path: project.full_path, enable: true } }
  let(:mutation) { graphql_mutation(:set_container_scanning_for_registry, variables) }
  let(:mutation_response) { graphql_mutation_response(:setContainerScanningForRegistry) }

  context 'when authorized' do
    before do
      stub_licensed_features(container_scanning_for_registry: true)
    end

    it 'enables container scanning for registry' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['containerScanningForRegistryEnabled']).to be(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_setting do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
