# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry namespace permissions (JavaScript fixtures)', feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  describe GraphQL::Query, type: :request do
    query_path = 'packages_and_registries/artifact_registry/graphql/queries/get_registry_permissions.query.graphql'

    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:organization_user, organization: organization).user }

    let(:base_url) { 'https://artifact-registry.example.test' }
    let(:slug) { 'resolved-handle' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }
    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:variables) { { organizationId: organization.to_global_id.to_s } }
    let(:namespace_permissions) { ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with(true) }

    let(:namespace_details_body) do
      {
        'slug' => slug,
        'created_at' => '2026-07-01T10:00:00Z',
        'permissions' => namespace_permissions
      }
    end

    include_context 'with a resolved Artifact Registry handle'

    before do
      stub_config(artifact_registry: { api_url: base_url })

      allow_next_instance_of(::ArtifactRegistry::TokenExchange) do |token_exchange|
        allow(token_exchange).to receive(:token_for).and_return('ar-fixture-credential')
      end

      stub_request(:get, "#{base_url}/api/v1/#{slug}/namespace")
        .with(query: { include_permissions: 'true' })
        .to_return(status: 200, headers: json_headers, body: namespace_details_body.to_json)
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry)).to eq(
        '__typename' => 'ArtifactRegistry',
        'id' => namespace_mapping.ar_namespace_id,
        'userPermissions' => namespace_permissions
          .transform_keys { |action| action.camelize(:lower) }
          .merge('__typename' => 'ArtifactRegistryNamespacePermissions')
      )
    end
  end
end
