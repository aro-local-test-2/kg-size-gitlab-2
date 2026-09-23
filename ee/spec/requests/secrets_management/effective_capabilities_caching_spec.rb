# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Effective capabilities caching', :use_clean_rails_memory_store_caching,
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, :with_namespace, reporter_of: project) }
  let_it_be_with_reload(:secrets_manager) { create(:project_secrets_manager, project: project) }

  let(:client) { instance_double(SecretsManagement::SecretsManagerClient) }
  let(:data_path) { secrets_manager.ci_full_path('*') }
  let(:detailed_metadata_path) { secrets_manager.detailed_metadata_path('*') }

  let(:query) do
    graphql_query_for(
      'projectSecretsManager',
      { project_path: project.full_path },
      <<~FIELDS
        userPermissions {
          readMetadata
          createSecrets
          updateSecrets
          deleteSecrets
        }
      FIELDS
    )
  end

  before do
    secrets_manager.activate!
    stub_feature_flags(secrets_manager: project)
    stub_licensed_features(native_secrets_management: true)
    stub_secrets_manager_entitlement(state: :paid)
    enroll_instance_in_secrets_manager

    allow_next_instances_of(SecretsManagement::UserPermissions::ProjectEffectiveCapabilitiesService, nil) do |service|
      allow(service).to receive(:user_scoped_client).and_return(client)
    end
  end

  # The page render and the GraphQL query the Vue app sends afterwards are separate
  # requests, so before the cache each one paid its own three OpenBao round trips.
  # The spec issues the GraphQL query directly because the frontend does not yet request userPermissions.
  it 'queries OpenBao once for the page load and the GraphQL query together', :aggregate_failures do
    expect(client).to receive(:capabilities_self).once
      .with(paths: [data_path, detailed_metadata_path])
      .and_return({ "data" => { data_path => %w[create update], detailed_metadata_path => %w[list] } })

    sign_in(reporter)
    get project_secrets_url(project)

    expect(response).to have_gitlab_http_status(:ok)

    post_graphql(query, current_user: reporter)

    expect(graphql_data_at(:project_secrets_manager, :user_permissions)).to eq(
      'readMetadata' => true,
      'createSecrets' => true,
      'updateSecrets' => true,
      'deleteSecrets' => false
    )
  end
end
