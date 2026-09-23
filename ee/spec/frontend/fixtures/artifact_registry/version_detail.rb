# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry version detail (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'
  version_query_path = "#{graphql_path}/queries/get_version.query.graphql"
  files_query_path = "#{graphql_path}/queries/get_version_files.query.graphql"

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }
  let_it_be(:project) { create(:project, organization: organization, developers: user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:package_url) { "#{repository_url}/#{format}/packages/#{artifact_id}" }
  let(:version_url) { "#{repository_url}/#{format}/versions/#{version_id}" }
  let(:files_url) { "#{version_url}/files" }

  let(:version_query) { get_graphql_query_as_string(version_query_path, ee: true) }
  let(:files_query) { get_graphql_query_as_string(files_query_path, ee: true) }

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
      'settings' => {}
    }
  end

  let(:variables) do
    {
      organizationId: organization.to_global_id.to_s,
      name: name,
      artifactId: artifact_id,
      versionId: version_id
    }
  end

  let(:files_variables) { variables.merge(first: 20) }

  let(:repository_fields) do
    {
      '__typename' => 'ArtifactRegistryRepositoryDetails',
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format.upcase,
      'kind' => 'HOSTED'
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

    stub_request(:get, package_url)
      .to_return(status: 200, headers: json_headers, body: package_body.to_json)

    stub_request(:get, version_url)
      .to_return(status: 200, headers: json_headers, body: version_body.to_json)
  end

  describe GraphQL::Query, 'the Maven version read', type: :request do
    jar_file_id = 'a1a2a3a4-0000-0000-0000-000000000000'
    pom_file_id = 'a2a3a4a5-0000-0000-0000-000000000000'

    let(:name) { 'maven-releases' }
    let(:format) { 'maven' }
    let(:artifact_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
    let(:version_id) { 'b8c9d0e1-0000-0000-0000-000000000000' }
    let(:commit_sha) { 'f19ac02a8d3b41e57c9f0a4d2b8e6135ac97d40e' }

    let(:package_body) do
      { 'id' => artifact_id, 'group_id' => 'com.example.tools', 'artifact_id' => 'payment-core' }
    end

    let(:version_body) do
      {
        'id' => version_id,
        'version' => '3.2.1',
        'size' => nil,
        'package_id' => artifact_id,
        'created_by' => user.id.to_s,
        'project_id' => project.id.to_s,
        'git_commit_sha' => commit_sha
      }
    end

    let(:statistics_body) { { 'files_count' => 2 } }

    let(:files_body) do
      [
        {
          'id' => jar_file_id,
          'file_name' => 'payment-core-3.2.1.jar',
          'size' => 1_048_576,
          'sha256' => 'a' * 64,
          'sha1' => 'b' * 40,
          'sha512' => 'c' * 128,
          'md5' => 'd' * 32,
          'created_at' => '2026-06-10T09:15:00Z'
        },
        {
          'id' => pom_file_id,
          'file_name' => 'payment-core-3.2.1.pom',
          'size' => 4096,
          'sha256' => 'e' * 64,
          'sha1' => 'f' * 40,
          'sha512' => '0' * 128,
          'md5' => nil
        }
      ]
    end

    it "ee/graphql/#{version_query_path}.json" do
      stub_statistics_read

      post_graphql(version_query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        repository_fields.merge(
          'package' => {
            '__typename' => 'ArtifactRegistryMavenPackageDetails',
            'id' => artifact_id,
            'groupId' => 'com.example.tools',
            'artifactId' => 'payment-core'
          },
          'version' => {
            '__typename' => 'ArtifactRegistryVersionDetails',
            'id' => version_id,
            'version' => '3.2.1',
            'createdAt' => nil,
            'sizeBytes' => nil,
            'createdBy' => {
              '__typename' => 'UserCore',
              'id' => user.to_global_id.to_s,
              'name' => user.name
            },
            'project' => {
              '__typename' => 'Project',
              'id' => project.to_global_id.to_s,
              'name' => project.name,
              'fullPath' => project.full_path,
              'webPath' => project_path(project)
            },
            'gitCommitSha' => commit_sha,
            'statistics' => {
              '__typename' => 'ArtifactRegistryVersionStatistics',
              'filesCount' => '2'
            }
          }
        )
      )
    end

    it "ee/graphql/#{files_query_path}.json" do
      stub_files_read

      post_graphql(files_query, current_user: user, variables: files_variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        repository_fields.merge(
          'version' => {
            '__typename' => 'ArtifactRegistryVersionDetails',
            'id' => version_id,
            'files' => files_connection(
              [
                {
                  '__typename' => 'ArtifactRegistryMavenVersionFile',
                  'id' => jar_file_id,
                  'fileName' => 'payment-core-3.2.1.jar',
                  'sizeBytes' => '1048576',
                  'sha256' => 'a' * 64,
                  'sha1' => 'b' * 40,
                  'sha512' => 'c' * 128,
                  'md5' => 'd' * 32,
                  'createdAt' => '2026-06-10T09:15:00+00:00'
                },
                {
                  '__typename' => 'ArtifactRegistryMavenVersionFile',
                  'id' => pom_file_id,
                  'fileName' => 'payment-core-3.2.1.pom',
                  'sizeBytes' => '4096',
                  'sha256' => 'e' * 64,
                  'sha1' => 'f' * 40,
                  'sha512' => '0' * 128,
                  'md5' => nil,
                  'createdAt' => nil
                }
              ]
            )
          }
        )
      )
    end
  end

  describe GraphQL::Query, 'the npm version read', type: :request do
    version_fixture_path = "#{graphql_path}/queries/get_version.npm.query.graphql"
    files_fixture_path = "#{graphql_path}/queries/get_version_files.npm.query.graphql"
    tarball_file_id = 'a3a4a5a6-0000-0000-0000-000000000000'

    let(:name) { 'npm-releases' }
    let(:format) { 'npm' }
    let(:artifact_id) { 'f6a7b8c9-0000-0000-0000-000000000000' }
    let(:version_id) { 'c9d0e1f2-0000-0000-0000-000000000000' }

    let(:package_body) do
      { 'id' => artifact_id, 'name' => '@acme/ui-components', 'scope' => '@acme' }
    end

    let(:version_body) do
      {
        'id' => version_id,
        'version' => '3.2.1',
        'created_at' => '2026-06-10T00:00:00Z',
        'size' => 524_288,
        'package_id' => artifact_id,
        'created_by' => nil,
        'project_id' => nil,
        'git_commit_sha' => nil
      }
    end

    let(:statistics_body) { {} }

    let(:files_body) do
      [
        {
          'id' => tarball_file_id,
          'file_name' => 'ui-components-3.2.1.tgz',
          'size' => 524_288,
          'sha256' => 'd' * 64,
          'created_at' => '2026-06-10T00:00:00Z'
        }
      ]
    end

    it "ee/graphql/#{version_fixture_path}.json" do
      stub_statistics_read

      post_graphql(version_query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        repository_fields.merge(
          'package' => {
            '__typename' => 'ArtifactRegistryNpmPackageDetails',
            'id' => artifact_id,
            'name' => '@acme/ui-components',
            'scope' => '@acme'
          },
          'version' => {
            '__typename' => 'ArtifactRegistryVersionDetails',
            'id' => version_id,
            'version' => '3.2.1',
            'createdAt' => '2026-06-10T00:00:00+00:00',
            'sizeBytes' => '524288',
            'createdBy' => nil,
            'project' => nil,
            'gitCommitSha' => nil,
            'statistics' => {
              '__typename' => 'ArtifactRegistryVersionStatistics',
              'filesCount' => nil
            }
          }
        )
      )
    end

    it "ee/graphql/#{files_fixture_path}.json" do
      stub_files_read

      post_graphql(files_query, current_user: user, variables: files_variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        repository_fields.merge(
          'version' => {
            '__typename' => 'ArtifactRegistryVersionDetails',
            'id' => version_id,
            'files' => files_connection(
              [
                {
                  '__typename' => 'ArtifactRegistryNpmVersionFile',
                  'id' => tarball_file_id,
                  'fileName' => 'ui-components-3.2.1.tgz',
                  'sizeBytes' => '524288',
                  'sha256' => 'd' * 64,
                  'createdAt' => '2026-06-10T00:00:00+00:00'
                }
              ]
            )
          }
        )
      )
    end
  end

  def stub_statistics_read
    stub_request(:get, "#{version_url}/statistics")
      .to_return(status: 200, headers: json_headers, body: statistics_body.to_json)
  end

  def stub_files_read
    stub_request(:get, files_url)
      .with(query: { limit: '20' })
      .to_return(status: 200, headers: json_headers, body: files_body.to_json)
  end

  def files_connection(nodes)
    {
      '__typename' => 'ArtifactRegistryVersionFileConnection',
      'nodes' => nodes,
      'pageInfo' => {
        '__typename' => 'PageInfo',
        'hasNextPage' => false,
        'hasPreviousPage' => false,
        'startCursor' => nil,
        'endCursor' => nil
      }
    }
  end
end
