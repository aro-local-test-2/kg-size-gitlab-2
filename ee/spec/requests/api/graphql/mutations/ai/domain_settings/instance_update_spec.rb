# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AiDomainSettingsInstanceUpdate', :enable_admin_mode, feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }

  let(:params) do
    {
      action: 'ADD',
      domain_setting_type: 'ALLOWED',
      domains: ['newdomain.com']
    }
  end

  let(:mutation) do
    graphql_mutation(
      :ai_domain_settings_instance_update,
      params,
      <<~GQL
        addedDomains
        errors
      GQL
    )
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: admin) }

  it 'updates the instance domain settings and returns no errors', :aggregate_failures do
    request

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_blank
    expect(graphql_data_at(:ai_domain_settings_instance_update, :errors)).to be_empty
    expect(graphql_data_at(:ai_domain_settings_instance_update, :added_domains)).to include('newdomain.com')
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_domain_settings do
    let(:user) { admin }
    let(:boundary_object) { :instance }
    let(:authz_mutation) { graphql_mutation(:ai_domain_settings_instance_update, params, 'errors') }
    let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
  end
end
