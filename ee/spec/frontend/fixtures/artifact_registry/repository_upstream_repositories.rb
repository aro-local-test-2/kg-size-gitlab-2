# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository upstream repositories (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'
  query_path = "#{graphql_path}/queries/get_repository_upstream_repositories.query.graphql"

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:list_url) { "#{repository_url}/#{format}/upstream_repositories" }

  let(:query) { get_graphql_query_as_string(query_path, ee: true) }
  let(:variables) { { organizationId: organization.to_global_id.to_s, name: name } }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format,
      'kind' => 'virtual',
      'visibility' => 'private',
      'description' => "A virtual #{format} repository",
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-06-01T00:00:00Z',
      'settings' => {}
    }
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
      .to_return(status: 200, headers: json_headers, body: list_body.to_json)
  end

  describe GraphQL::Query, 'the upstream-list read of a package family repository', type: :request do
    let(:name) { 'maven-virtual' }
    let(:format) { 'maven' }

    let(:list_body) do
      [
        { 'id' => 'a1000000-0000-4000-8000-000000000001', 'position' => 1,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000001',
                                     'name' => 'maven-central-proxy', 'format' => 'maven',
                                     'kind' => 'remote' } },
        { 'id' => 'a1000000-0000-4000-8000-000000000002', 'position' => 2,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000002',
                                     'name' => 'payments-releases', 'format' => 'maven',
                                     'kind' => 'hosted' } },
        { 'id' => 'a1000000-0000-4000-8000-000000000003', 'position' => 3,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000003',
                                     'name' => 'platform-snapshots', 'format' => 'maven',
                                     'kind' => 'hosted' } }
      ]
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'maven-virtual',
        'kind' => 'VIRTUAL',
        'upstreamRepositories' => [
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000001',
            'position' => 1,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000001',
              'name' => 'maven-central-proxy',
              'kind' => 'REMOTE'
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000002',
            'position' => 2,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000002',
              'name' => 'payments-releases',
              'kind' => 'HOSTED'
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000003',
            'position' => 3,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000003',
              'name' => 'platform-snapshots',
              'kind' => 'HOSTED'
            }
          }
        ]
      )
    end
  end

  describe GraphQL::Query, 'the upstream-list read of a container family repository', type: :request do
    fixture_path = "#{graphql_path}/queries/get_repository_upstream_repositories.container.query.graphql"

    let(:name) { 'docker-virtual' }
    let(:format) { 'docker' }

    let(:list_body) do
      [
        { 'id' => 'b1000000-0000-4000-8000-000000000001', 'position' => 1,
          'upstream_repository' => { 'id' => 'e1000000-0000-4000-8000-000000000001',
                                     'name' => 'docker-hub-proxy', 'format' => 'docker',
                                     'kind' => 'remote' } },
        { 'id' => 'b1000000-0000-4000-8000-000000000002', 'position' => 2,
          'upstream_repository' => { 'id' => 'e1000000-0000-4000-8000-000000000002',
                                     'name' => 'base-images', 'format' => 'oci',
                                     'kind' => 'hosted' } }
      ]
    end

    it "ee/graphql/#{fixture_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'docker-virtual',
        'kind' => 'VIRTUAL',
        'upstreamRepositories' => [
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'b1000000-0000-4000-8000-000000000001',
            'position' => 1,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'e1000000-0000-4000-8000-000000000001',
              'name' => 'docker-hub-proxy',
              'kind' => 'REMOTE'
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'b1000000-0000-4000-8000-000000000002',
            'position' => 2,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'e1000000-0000-4000-8000-000000000002',
              'name' => 'base-images',
              'kind' => 'HOSTED'
            }
          }
        ]
      )
    end
  end
end
