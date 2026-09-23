# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry version files connection', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }
  let(:files_first) { 20 }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:version_id) { 'v1000000-0000-0000-0000-000000000000' }
  let(:artifact_id) { 'p1000000-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:version_url) { "#{repository_url}/#{format}/versions/#{version_id}" }
  let(:files_url) { "#{version_url}/files" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'settings' => {}
    }
  end

  let(:version_body) do
    { 'id' => version_id, 'version' => '1.10.0', 'package_id' => artifact_id }
  end

  let(:maven_file) do
    {
      'id' => 'f1000000-0000-0000-0000-000000000000',
      'file_name' => 'payment-core-1.10.0.jar',
      'size' => 9_876_543_210,
      'sha256' => 'a' * 64,
      'sha1' => 'b' * 40,
      'sha512' => 'c' * 128,
      'md5' => 'd' * 32,
      'created_at' => '2026-07-03T09:15:00Z'
    }
  end

  # A pom file with a null md5 and an omitted created_at: the two Maven nullables, side by side.
  let(:other_maven_file) do
    { 'id' => 'f2000000-0000-0000-0000-000000000000', 'file_name' => 'payment-core-1.10.0.pom',
      'size' => 4096, 'sha256' => 'e' * 64, 'sha1' => 'f' * 40, 'sha512' => '0' * 128, 'md5' => nil }
  end

  let(:files_body) { [maven_file, other_maven_file] }

  let(:file_fragments) do
    <<~FRAGMENTS
      ... on ArtifactRegistryMavenVersionFile {
        id fileName sizeBytes sha256 sha1 sha512 md5 createdAt
      }
      ... on ArtifactRegistryNpmVersionFile {
        id fileName sizeBytes sha256 createdAt
      }
    FRAGMENTS
  end

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryVersionFiles(
        $id: OrganizationsOrganizationID!
        $name: String!
        $versionId: ID!
        $artifactId: ID!
        $first: Int
        $after: String
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            version(id: $versionId, artifactId: $artifactId) {
              id
              files(first: $first, after: $after) {
                nodes {
                  __typename
                  #{file_fragments}
                }
                pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              }
            }
          }
        }
      }
    QUERY
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end
  end

  subject(:post_query) do
    post_graphql(query, current_user: current_user,
      variables: { id: organization.to_global_id.to_s, name: repository_name,
                   versionId: version_id, artifactId: artifact_id, first: files_first, after: nil })
  end

  context 'when the repository holds Maven files' do
    it 'renders every selected field, with the two Maven nullables resolving null not failing',
      :aggregate_failures do
      stub_repository_read
      stub_version_read
      stub_files_list

      post_query

      expect(files_response['nodes']).to eq(
        [
          {
            '__typename' => 'ArtifactRegistryMavenVersionFile',
            'id' => 'f1000000-0000-0000-0000-000000000000',
            'fileName' => 'payment-core-1.10.0.jar',
            'sizeBytes' => '9876543210',
            'sha256' => 'a' * 64,
            'sha1' => 'b' * 40,
            'sha512' => 'c' * 128,
            'md5' => 'd' * 32,
            'createdAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryMavenVersionFile',
            'id' => 'f2000000-0000-0000-0000-000000000000',
            'fileName' => 'payment-core-1.10.0.pom',
            'sizeBytes' => '4096',
            'sha256' => 'e' * 64,
            'sha1' => 'f' * 40,
            'sha512' => '0' * 128,
            'md5' => nil,
            'createdAt' => nil
          }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    it 'reads the version once and the files once, with no per-row follow-up', :aggregate_failures do
      stub_repository_read
      version = stub_version_read
      files = stub_files_list

      post_query

      expect(version).to have_been_requested.once
      expect(files).to have_been_requested.once
    end

    it 'exposes the Link-header cursors through pageInfo' do
      stub_repository_read
      stub_version_read
      next_cursor = 'eyJpZCI6MjB9'
      prev_cursor = 'eyJpZCI6MTB9'
      stub_files_list(headers: json_headers.merge('Link' =>
        %(<#{files_url}?cursor=#{next_cursor}>; rel="next", <#{files_url}?cursor=#{prev_cursor}>; rel="prev")))

      post_query

      expect(files_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
    end
  end

  context 'when the repository holds npm files' do
    let(:format) { 'npm' }
    let(:repository_name) { 'npm-releases' }
    let(:files_body) do
      [{ 'id' => 'f3000000-0000-0000-0000-000000000000', 'file_name' => 'ui-components-1.10.0.tgz',
         'size' => 54_321, 'sha256' => 'a' * 64, 'created_at' => '2026-07-03T09:15:00Z' }]
    end

    it 'renders the npm file fields, discriminated to the npm type', :aggregate_failures do
      stub_repository_read
      stub_version_read
      stub_files_list

      post_query

      node = files_response['nodes'].first
      expect(node['__typename']).to eq('ArtifactRegistryNpmVersionFile')
      expect(node['fileName']).to eq('ui-components-1.10.0.tgz')
      expect(node['createdAt']).to eq('2026-07-03T09:15:00+00:00')
    end
  end

  context 'when the caller requests a page larger than the monolith maximum' do
    let(:files_first) { ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE + 1 }

    it 'caps the outbound limit at the maximum page size' do
      stub_repository_read
      stub_version_read
      capped = stub_files_list(query: { limit: ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE.to_s })

      post_query

      expect(capped).to have_been_requested.once
    end
  end

  context 'when a forward cursor is supplied' do
    let(:after_cursor) { 'eyJpZCI6MjB9' }

    it 'forwards the cursor to Artifact Registry', :aggregate_failures do
      stub_repository_read
      stub_version_read
      paged = stub_files_list(query: { limit: '20', cursor: after_cursor })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     versionId: version_id, artifactId: artifact_id, first: files_first, after: after_cursor })

      expect(paged).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when paging backward with last and before' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionFilesBackward(
          $id: OrganizationsOrganizationID!, $name: String!, $versionId: ID!, $artifactId: ID!,
          $last: Int, $before: String
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              version(id: $versionId, artifactId: $artifactId) {
                files(last: $last, before: $before) { nodes { __typename } }
              }
            }
          }
        }
      QUERY
    end

    it 'forwards the before cursor and the last limit', :aggregate_failures do
      stub_repository_read
      stub_version_read
      paged = stub_files_list(query: { limit: '5', cursor: 'eyJpZCI6MTB9' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     versionId: version_id, artifactId: artifact_id, last: 5, before: 'eyJpZCI6MTB9' })

      expect(paged).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the version holds no files' do
    let(:files_body) { [] }

    it 'renders an empty connection, not a null one, so no files is distinct from a failed read',
      :aggregate_failures do
      stub_repository_read
      stub_version_read
      stub_files_list

      post_query

      expect(files_response['nodes']).to eq([])
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the files read is rejected' do
    # 404 is swallowed in the client; 401/403 raise AuthorizationError and take a different path.
    # All three resolve the connection null with no error (existence-hiding).
    where(:status) { [404, 401, 403] }

    with_them do
      it 'resolves the connection null with no error', :aggregate_failures do
        stub_repository_read
        stub_version_read
        stub_files_list(status: status, body: error_envelope(code: 'denied').to_json)

        post_query

        expect(files_response).to be_nil
        expect(version_response['id']).to eq(version_id)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the files read is unavailable (5xx)' do
    it 'renders the service-unavailable error beside the loaded version, with request_id preserved',
      :aggregate_failures do
      stub_repository_read
      stub_version_read
      stub_files_list(status: 503, body: error_envelope(code: 'unavailable', request_id: 'req-503').to_json)

      post_query

      expect(files_response).to be_nil
      expect(version_response['id']).to eq(version_id)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
    end
  end

  context 'when the files read fails in transport' do
    it 'renders the service-unavailable error on a connection failure' do
      stub_repository_read
      stub_version_read
      stub_request(:get, files_url).with(query: { limit: '20' }).to_raise(Faraday::ConnectionFailed)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end

    it 'renders the service-unavailable error on a timeout, which the retry middleware handles' do
      stub_repository_read
      stub_version_read
      stub_request(:get, files_url).with(query: { limit: '20' }).to_timeout

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the files read returns a non-404 client error' do
    it 'surfaces a top-level error carrying the request_id, not a bare null', :aggregate_failures do
      stub_repository_read
      stub_version_read
      stub_files_list(status: 422, body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json)

      post_query

      expect(graphql_errors).to be_present
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
    end
  end

  it 'renders the files without leaking the Artifact Registry credential', :aggregate_failures do
    stub_repository_read
    stub_version_read
    stub_files_list

    post_query

    expect(files_response['nodes']).to be_present
    expect(response.body).not_to include(token)
    expect(response.body.downcase).not_to include('bearer')
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      version = stub_version_read
      files = stub_files_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(version).not_to have_been_requested
      expect(files).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { non_member }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the files connection is selected twice in one operation' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionFilesAliased(
          $id: OrganizationsOrganizationID!
          $name: String!
          $versionId: ID!
          $artifactId: ID!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              version(id: $versionId, artifactId: $artifactId) {
                files(first: 5) { nodes { __typename } }
                second: files(first: 5) { nodes { __typename } }
              }
            }
          }
        }
      QUERY
    end

    it 'raises the call-count limit rather than issuing a second files read', :aggregate_failures do
      stub_repository_read
      stub_version_read
      files = stub_files_list(query: { limit: '5' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     versionId: version_id, artifactId: artifact_id })

      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(files).to have_been_requested.once
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_version_read(status: 200, body: version_body.to_json, headers: json_headers)
    stub_request(:get, version_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_files_list(status: 200, body: files_body.to_json, headers: json_headers, query: { limit: '20' })
    stub_request(:get, files_url).with(query: query).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def version_response
    repository_response&.dig('version')
  end

  def files_response
    version_response&.dig('files')
  end
end
