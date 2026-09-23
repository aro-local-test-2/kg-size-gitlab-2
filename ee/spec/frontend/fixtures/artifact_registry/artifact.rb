# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry artifact (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'
  query_path = "#{graphql_path}/queries/get_artifact.query.graphql"

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:artifact_url) { "#{repository_url}/#{format}/#{family}/#{artifact_id}" }

  let(:query) { get_graphql_query_as_string(query_path, ee: true) }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => "A hosted #{format} repository",
      'artifacts_count' => 2,
      'downloads_count' => 1234,
      'size_bytes' => 2048,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-06-01T00:00:00Z',
      'settings' => {},
      'permissions' => repository_permissions
    }
  end

  let(:repository_permissions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true) }

  let(:repository_permissions_block) do
    repository_permissions
      .transform_keys { |action| action.camelize(:lower) }
      .merge('__typename' => 'ArtifactRegistryRepositoryPermissions')
  end

  let(:variables) do
    { organizationId: organization.to_global_id.to_s, name: name, artifactId: artifact_id }
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(::ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return('ar-fixture-credential')
    end

    stub_request(:get, repository_url)
      .with(query: { include_permissions: 'true' })
      .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

    stub_request(:get, artifact_url)
      .to_return(status: 200, headers: json_headers, body: artifact_body.to_json)
  end

  describe GraphQL::Query, 'the Maven package read', type: :request do
    let(:name) { 'maven-releases' }
    let(:format) { 'maven' }
    let(:family) { 'packages' }
    let(:artifact_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }

    let(:artifact_body) do
      { 'id' => artifact_id, 'group_id' => 'com.example.tools', 'artifact_id' => 'payment-core' }
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => name,
        'format' => 'MAVEN',
        'image' => nil,
        'package' => {
          '__typename' => 'ArtifactRegistryMavenPackageDetails',
          'id' => artifact_id,
          'groupId' => 'com.example.tools',
          'artifactId' => 'payment-core'
        },
        'userPermissions' => repository_permissions_block
      )
    end
  end

  describe GraphQL::Query, 'the npm package read', type: :request do
    fixture_path = "#{graphql_path}/queries/get_artifact.npm.query.graphql"

    let(:name) { 'npm-releases' }
    let(:format) { 'npm' }
    let(:family) { 'packages' }
    let(:artifact_id) { 'f6a7b8c9-0000-0000-0000-000000000000' }

    let(:artifact_body) do
      { 'id' => artifact_id, 'name' => '@acme/ui-components', 'scope' => '@acme' }
    end

    it "ee/graphql/#{fixture_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => name,
        'format' => 'NPM',
        'image' => nil,
        'package' => {
          '__typename' => 'ArtifactRegistryNpmPackageDetails',
          'id' => artifact_id,
          'name' => '@acme/ui-components',
          'scope' => '@acme'
        },
        'userPermissions' => repository_permissions_block
      )
    end
  end

  describe GraphQL::Query, 'the container image read', type: :request do
    fixture_path = "#{graphql_path}/queries/get_artifact.image.query.graphql"

    let(:name) { 'container-images' }
    let(:format) { 'docker' }
    let(:family) { 'images' }
    let(:artifact_id) { 'a7b8c9d0-0000-0000-0000-000000000000' }

    let(:artifact_body) do
      { 'id' => artifact_id, 'name' => 'payment-service', 'digest' => 'sha256:aaaa' }
    end

    it "ee/graphql/#{fixture_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => name,
        'format' => 'DOCKER',
        'image' => {
          '__typename' => 'ArtifactRegistryImage',
          'id' => artifact_id,
          'name' => 'payment-service'
        },
        'package' => nil,
        'userPermissions' => repository_permissions_block
      )
    end
  end
end
