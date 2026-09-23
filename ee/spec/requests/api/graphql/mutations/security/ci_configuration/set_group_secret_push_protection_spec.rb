# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SetGroupSecretPushProtection', feature_category: :secret_detection do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, maintainer_of: group) }

  let(:variables) { { namespace_path: group.full_path, secret_push_protection_enabled: true } }
  let(:mutation) { graphql_mutation(:set_group_secret_push_protection, variables) }
  let(:mutation_response) { graphql_mutation_response(:setGroupSecretPushProtection) }

  context 'when authorized' do
    before do
      stub_licensed_features(secret_push_protection: true)
    end

    it 'enables secret push protection for the group' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_setting do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
