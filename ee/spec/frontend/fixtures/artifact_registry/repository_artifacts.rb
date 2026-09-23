# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository artifacts (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }

  let(:page_size) { 20 }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:list_url) { "#{repository_url}/#{format}/#{family}" }

  let(:next_cursor) { 'eyJpZCI6MjB9' }
  let(:prev_cursor) { 'eyJpZCI6MTB9' }

  let(:list_headers) do
    json_headers.merge(
      'Link' => %(<#{list_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{list_url}?cursor=#{prev_cursor}>; rel="prev")
    )
  end

  let(:kind) { 'hosted' }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format,
      'kind' => kind,
      'visibility' => 'private',
      'description' => "A #{kind} #{format} repository",
      'artifacts_count' => 2,
      'downloads_count' => 1234,
      'size_bytes' => 2048,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-06-01T00:00:00Z',
      'settings' => {}
    }
  end

  let(:variables) do
    { organizationId: organization.to_global_id.to_s, name: name, first: page_size }
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(::ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return('ar-fixture-credential')
    end

    stub_request(:get, repository_url)
      .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

    stub_request(:get, list_url)
      .with(query: { limit: page_size.to_s })
      .to_return(status: 200, headers: list_headers, body: list_body.to_json)
  end

  describe GraphQL::Query, 'the images read', type: :request do
    query_path = "#{graphql_path}/queries/get_repository_images.query.graphql"

    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:name) { 'container-images' }
    let(:format) { 'docker' }
    let(:family) { 'images' }

    let(:list_body) do
      [
        { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000', 'name' => 'payment-core',
          'last_downloaded_at' => '2026-07-03T09:15:00Z', 'digest' => 'sha256:aaaa' },
        { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'name' => 'payment-api',
          'last_downloaded_at' => nil, 'digest' => 'sha256:bbbb' }
      ]
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository, :images)).to eq(
        '__typename' => 'ArtifactRegistryImageConnection',
        'nodes' => [
          {
            '__typename' => 'ArtifactRegistryImage',
            'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
            'name' => 'payment-core',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryImage',
            'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
            'name' => 'payment-api',
            'lastDownloadedAt' => nil
          }
        ],
        'pageInfo' => {
          '__typename' => 'PageInfo',
          'hasNextPage' => true,
          'hasPreviousPage' => true,
          'startCursor' => prev_cursor,
          'endCursor' => next_cursor
        }
      )
    end
  end

  describe GraphQL::Query, 'the packages read', type: :request do
    query_path = "#{graphql_path}/queries/get_repository_packages.query.graphql"

    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:name) { 'maven-releases' }
    let(:format) { 'maven' }
    let(:family) { 'packages' }

    let(:list_body) do
      [
        { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000', 'group_id' => 'com.example.tools',
          'artifact_id' => 'payment-core', 'last_downloaded_at' => '2026-07-03T09:15:00Z' },
        { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'group_id' => 'com.example.tools',
          'artifact_id' => 'payment-api', 'last_downloaded_at' => nil }
      ]
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository, :packages)).to eq(
        '__typename' => 'ArtifactRegistryPackageConnection',
        'nodes' => [
          {
            '__typename' => 'ArtifactRegistryMavenPackage',
            'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
            'groupId' => 'com.example.tools',
            'artifactId' => 'payment-core',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryMavenPackage',
            'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
            'groupId' => 'com.example.tools',
            'artifactId' => 'payment-api',
            'lastDownloadedAt' => nil
          }
        ],
        'pageInfo' => {
          '__typename' => 'PageInfo',
          'hasNextPage' => true,
          'hasPreviousPage' => true,
          'startCursor' => prev_cursor,
          'endCursor' => next_cursor
        }
      )
    end
  end

  describe GraphQL::Query, 'the packages read of a remote npm repository', type: :request do
    query_path = "#{graphql_path}/queries/get_repository_packages.query.graphql"
    fixture_path = "#{graphql_path}/queries/get_repository_packages.npm.query.graphql"

    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:name) { 'npm-upstream' }
    let(:format) { 'npm' }
    let(:family) { 'packages' }
    let(:kind) { 'remote' }

    # Artifact Registry supplies no versions_count for a package of a remote repository, and
    # tags_count rides the stub as a field no type exposes.
    let(:list_body) do
      [
        { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000', 'name' => '@acme/ui-components',
          'scope' => '@acme', 'tags_count' => 2,
          'last_downloaded_at' => '2026-07-03T09:15:00Z' },
        { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'name' => 'design-tokens',
          'scope' => nil, 'tags_count' => 1, 'last_downloaded_at' => nil }
      ]
    end

    it "ee/graphql/#{fixture_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository, :packages)).to eq(
        '__typename' => 'ArtifactRegistryPackageConnection',
        'nodes' => [
          {
            '__typename' => 'ArtifactRegistryNpmPackage',
            'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
            'name' => '@acme/ui-components',
            'scope' => '@acme',
            'versionsCount' => nil,
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryNpmPackage',
            'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
            'name' => 'design-tokens',
            'scope' => nil,
            'versionsCount' => nil,
            'lastDownloadedAt' => nil
          }
        ],
        'pageInfo' => {
          '__typename' => 'PageInfo',
          'hasNextPage' => true,
          'hasPreviousPage' => true,
          'startCursor' => prev_cursor,
          'endCursor' => next_cursor
        }
      )
    end
  end
end
