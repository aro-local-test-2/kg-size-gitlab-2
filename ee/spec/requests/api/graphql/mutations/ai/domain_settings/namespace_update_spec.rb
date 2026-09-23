# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AiDomainSettingsNamespaceUpdate', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:root_group) { create(:group) }

  let(:params) do
    {
      namespace_id: root_group.to_global_id.to_s,
      action: 'ADD',
      domain_setting_type: 'ALLOWED',
      domains: ['newdomain.com']
    }
  end

  let(:mutation) do
    graphql_mutation(
      :ai_domain_settings_namespace_update,
      params,
      <<~GQL
        addedDomains
        errors
      GQL
    )
  end

  before_all do
    root_group.add_owner(owner)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: owner) }

  it 'updates the namespace domain settings and returns no errors', :aggregate_failures do
    request

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_blank
    expect(graphql_data_at(:ai_domain_settings_namespace_update, :errors)).to be_empty
    expect(graphql_data_at(:ai_domain_settings_namespace_update, :added_domains)).to include('newdomain.com')
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_domain_settings do
    let(:user) { owner }
    let(:boundary_object) { root_group }
    let(:authz_mutation) { graphql_mutation(:ai_domain_settings_namespace_update, params, 'errors') }
    let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
  end
end
