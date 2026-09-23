# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SetLicenseScanningForCyclonedx', feature_category: :software_composition_analysis do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }

  let(:variables) { { project_path: project.full_path, enable: true } }
  let(:mutation) { graphql_mutation(:set_license_scanning_for_cyclonedx, variables) }
  let(:mutation_response) { graphql_mutation_response(:setLicenseScanningForCyclonedx) }

  context 'when authorized' do
    before do
      stub_licensed_features(license_scanning: true)
    end

    it 'enables license scanning for CycloneDX' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['licenseScanningForCyclonedxEnabled']).to be(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_setting do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
