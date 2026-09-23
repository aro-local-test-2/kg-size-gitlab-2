# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repositories (JavaScript fixtures)', feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  describe GraphQL::Query, type: :request do
    query_path = 'packages_and_registries/artifact_registry/graphql/queries/get_repositories.query.graphql'

    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:organization_user, organization: organization).user }

    let(:base_url) { 'https://artifact-registry.example.test' }
    let(:slug) { 'resolved-handle' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }
    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:variables) { { organizationId: organization.to_global_id.to_s, first: 20 } }
    let(:namespace_permissions) { ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with(true) }
    let(:repository_permissions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true) }
    let(:repository_permissions_block) do
      repository_permissions
        .transform_keys { |action| action.camelize(:lower) }
        .merge('__typename' => 'ArtifactRegistryRepositoryPermissions')
    end

    # A page reached part-way through a walk, so Artifact Registry answers with both Link cursors.
    # Nothing may parse them (ADR-009); the paging specs only hand them back.
    let(:next_cursor) { 'eyJuYW1lIjoibXktcmVwb3NpdG9yeSJ9' }
    let(:prev_cursor) { 'eyJuYW1lIjoiY29udGFpbmVyLWltYWdlcyJ9' }

    # A repository whose content has changed, alongside one nothing was ever published to: zero
    # counters and no `last_updated_at`.
    let(:page_body) do
      [
        {
          'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
          'name' => 'my-repository',
          'format' => 'maven',
          'kind' => 'hosted',
          'visibility' => 'private',
          'description' => 'A hosted Maven repository',
          'artifacts_count' => 3,
          'downloads_count' => 1234,
          'size_bytes' => 2048,
          'created_at' => '2026-05-12T09:24:00Z',
          'last_updated_at' => '2026-06-01T00:00:00Z',
          'permissions' => repository_permissions
        },
        {
          'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
          'name' => 'container-images',
          'format' => 'docker',
          'kind' => 'virtual',
          'visibility' => 'private',
          'description' => nil,
          'artifacts_count' => 0,
          'downloads_count' => 0,
          'size_bytes' => 0,
          'created_at' => '2026-05-14T09:24:00Z',
          'last_updated_at' => nil,
          'permissions' => repository_permissions
        }
      ]
    end

    let(:response_headers) do
      {
        'Content-Type' => 'application/json',
        'Link' => %(<#{base_url}/api/v1/#{slug}/repositories?cursor=#{next_cursor}>; rel="next", ) +
          %(<#{base_url}/api/v1/#{slug}/repositories?cursor=#{prev_cursor}>; rel="prev")
      }
    end

    include_context 'with a resolved Artifact Registry handle'

    before do
      stub_config(artifact_registry: { api_url: base_url })

      allow_next_instance_of(::ArtifactRegistry::TokenExchange) do |token_exchange|
        allow(token_exchange).to receive(:token_for).and_return('ar-fixture-credential')
      end

      stub_request(:get, "#{base_url}/api/v1/#{slug}/repositories")
        .with(query: { limit: '20', sort: 'last_updated_at', order: 'desc', include_permissions: 'true' })
        .to_return(
          status: 200,
          body: { 'repositories' => page_body, 'permissions' => namespace_permissions }.to_json,
          headers: response_headers
        )
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repositories)).to match(
        a_hash_including(
          'nodes' => [
            {
              '__typename' => 'ArtifactRegistryRepository',
              'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
              'name' => 'my-repository',
              'format' => 'MAVEN',
              'kind' => 'HOSTED',
              'visibility' => 'PRIVATE',
              'downloadsCount' => '1234',
              'sizeBytes' => '2048',
              'lastUpdatedAt' => '2026-06-01T00:00:00+00:00',
              'userPermissions' => repository_permissions_block
            },
            {
              '__typename' => 'ArtifactRegistryRepository',
              'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
              'name' => 'container-images',
              'format' => 'DOCKER',
              'kind' => 'VIRTUAL',
              'visibility' => 'PRIVATE',
              'downloadsCount' => '0',
              'sizeBytes' => '0',
              'lastUpdatedAt' => nil,
              'userPermissions' => repository_permissions_block
            }
          ],
          'pageInfo' => a_hash_including(
            'hasNextPage' => true,
            'hasPreviousPage' => true,
            'startCursor' => prev_cursor,
            'endCursor' => next_cursor
          ),
          'userPermissions' => namespace_permissions
            .transform_keys { |action| action.camelize(:lower) }
            .merge('__typename' => 'ArtifactRegistryNamespacePermissions')
        )
      )
    end
  end
end
