# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry npm dist-tags connection', feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'npm' }
  let(:kind) { 'hosted' }
  let(:repository_name) { 'npm-releases' }
  let(:package_id) { 'p1000000-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:package_url) { "#{repository_url}/#{format}/packages/#{package_id}" }
  let(:dist_tags_url) { "#{repository_url}/npm/packages/#{package_id}/tags" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => kind,
      'visibility' => 'private',
      'settings' => {}
    }
  end

  let(:package_body) { { 'id' => package_id, 'name' => '@acme/ui', 'scope' => '@acme' } }

  let(:latest_tag) do
    { 'id' => 't1000000-0000-0000-0000-000000000000', 'name' => 'latest',
      'version_id' => 'v1000000-0000-0000-0000-000000000000', 'version' => '1.10.0' }
  end

  let(:beta_tag) do
    { 'id' => 't2000000-0000-0000-0000-000000000000', 'name' => 'beta',
      'version_id' => 'v2000000-0000-0000-0000-000000000000', 'version' => '1.11.0-beta' }
  end

  let(:dist_tags_body) { [latest_tag, beta_tag] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryDistTags(
        $id: OrganizationsOrganizationID!
        $name: String!
        $artifactId: ID!
        $first: Int
        $after: String
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            package(id: $artifactId) {
              ... on ArtifactRegistryNpmPackageDetails {
                id
                distTags(first: $first, after: $after) {
                  nodes { id name versionId version }
                  pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
                }
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
                   artifactId: package_id, first: 100, after: nil })
  end

  context 'when the repository holds the npm package' do
    it 'renders the dist-tags the endpoint returned', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list

      post_query

      expect(dist_tags_response['nodes']).to eq(
        [
          { 'id' => 't1000000-0000-0000-0000-000000000000', 'name' => 'latest',
            'versionId' => 'v1000000-0000-0000-0000-000000000000', 'version' => '1.10.0' },
          { 'id' => 't2000000-0000-0000-0000-000000000000', 'name' => 'beta',
            'versionId' => 'v2000000-0000-0000-0000-000000000000', 'version' => '1.11.0-beta' }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    it 'requests the maximum page so truncation is rare' do
      stub_repository_read
      stub_package_read
      capped = stub_dist_tags_list(query: { limit: '100' })

      post_query

      expect(capped).to have_been_requested.once
    end

    it 'exposes the Link-header cursors through pageInfo' do
      stub_repository_read
      stub_package_read
      next_cursor = 'eyJpZCI6MjB9'
      prev_cursor = 'eyJpZCI6MTB9'
      stub_dist_tags_list(headers: json_headers.merge('Link' =>
        %(<#{dist_tags_url}?cursor=#{next_cursor}>; rel="next", <#{dist_tags_url}?cursor=#{prev_cursor}>; rel="prev")))

      post_query

      expect(dist_tags_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
    end

    it 'renders the dist-tags without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list

      post_query

      expect(dist_tags_response['nodes']).to be_present
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'on a remote repository (dist-tags are hosted-only)' do
    let(:kind) { 'remote' }

    it 'resolves the connection null without reading dist-tags from Artifact Registry',
      :aggregate_failures do
      stub_repository_read
      stub_package_read
      tags = stub_request(:get, dist_tags_url)

      post_query

      expect(dist_tags_response).to be_nil
      expect(tags).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'on a virtual repository (reads dist-tags like the delete mutation)' do
    let(:kind) { 'virtual' }

    it 'reads and renders the dist-tags rather than refusing the repository', :aggregate_failures do
      stub_repository_read
      stub_package_read
      tags = stub_dist_tags_list

      post_query

      expect(dist_tags_response['nodes']).to eq(
        [
          { 'id' => 't1000000-0000-0000-0000-000000000000', 'name' => 'latest',
            'versionId' => 'v1000000-0000-0000-0000-000000000000', 'version' => '1.10.0' },
          { 'id' => 't2000000-0000-0000-0000-000000000000', 'name' => 'beta',
            'versionId' => 'v2000000-0000-0000-0000-000000000000', 'version' => '1.11.0-beta' }
        ]
      )
      expect(tags).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  # distTags mounts on the detail arm, not the plain list element, so selecting it under the
  # packages list connection is a schema validation error that short-circuits before any AR read.
  context 'when dist-tags are selected under the packages list connection' do
    let(:query) do
      <<~QUERY
        query($id: OrganizationsOrganizationID!, $name: String!) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              packages(first: 20) {
                nodes {
                  ... on ArtifactRegistryNpmPackage {
                    distTags { nodes { name } }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    it 'fails schema validation without issuing a dist-tags read', :aggregate_failures do
      tags = stub_request(:get, dist_tags_url)

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name })

      expect_graphql_errors_to_include(/Field 'distTags' doesn't exist on type 'ArtifactRegistryNpmPackage'/)
      expect(tags).not_to have_been_requested
    end
  end

  context 'when first exceeds the page cap' do
    it 'reduces the outbound read to the maximum page size', :aggregate_failures do
      stub_repository_read
      stub_package_read
      capped = stub_dist_tags_list(query: { limit: '100' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     artifactId: package_id, first: 500, after: nil })

      expect(capped).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the dist-tags read is rate-limited (429)' do
    it 'surfaces a top-level error beside the loaded package', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list(status: 429, body: error_envelope(code: 'rate_limited').to_json)

      post_query

      expect(dist_tags_response).to be_nil
      expect(package_response['id']).to eq(package_id)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the dist-tags read 404s under a loaded package' do
    it 'resolves the connection null without failing the package sibling fields', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list(status: 404, body: error_envelope(code: 'not_found').to_json)

      post_query

      expect(package_response['id']).to eq(package_id)
      expect(dist_tags_response).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the dist-tags read is unavailable (5xx)' do
    it 'renders the service-unavailable error beside the loaded package', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list(status: 503, body: error_envelope(code: 'unavailable').to_json)

      post_query

      expect(dist_tags_response).to be_nil
      expect(package_response['id']).to eq(package_id)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the dist-tags connection is selected twice in one operation' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryDistTagsAliased(
          $id: OrganizationsOrganizationID!, $name: String!, $artifactId: ID!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              package(id: $artifactId) {
                ... on ArtifactRegistryNpmPackageDetails {
                  distTags(first: 5) { nodes { id } }
                  second: distTags(first: 5) { nodes { id } }
                }
              }
            }
          }
        }
      QUERY
    end

    it 'raises the call-count limit rather than issuing a second dist-tags read', :aggregate_failures do
      stub_repository_read
      stub_package_read
      tags = stub_dist_tags_list(query: { limit: '5' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name, artifactId: package_id })

      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(tags).to have_been_requested.once
    end
  end

  # FieldCallCount keys per operation, so a multiplex gets the budget per operation while the
  # repository read still coalesces across the request (criterion 31, dist-tag half).
  context 'when a multiplex carries the same dist-tags selection in two operations' do
    let(:multiplex_query) do
      <<~QUERY
        query OPERATION_NAME {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              package(id: "#{package_id}") {
                ... on ArtifactRegistryNpmPackageDetails { distTags(first: 5) { nodes { id } } }
              }
            }
          }
        }
      QUERY
    end

    it 'budgets the dist-tags field per operation and reads the repository once', :aggregate_failures do
      detail = stub_repository_read
      stub_package_read
      tags = stub_dist_tags_list(query: { limit: '5' })

      post_multiplex(
        [
          { query: multiplex_query.sub('OPERATION_NAME', 'first_operation') },
          { query: multiplex_query.sub('OPERATION_NAME', 'second_operation') }
        ],
        current_user: current_user
      )

      expect(response).to have_gitlab_http_status(:ok)
      expect(detail).to have_been_requested.once
      expect(tags).to have_been_requested.twice
      expect(json_response.pluck('errors').flatten.compact).to be_empty
    end
  end

  # Criterion 10, dist-tag part: 401/403 resolve the connection null silently; a 5xx surfaces the
  # service-unavailable error with request_id preserved.
  context 'when the dist-tags read is rejected with 401 or 403' do
    using RSpec::Parameterized::TableSyntax

    where(:status) { [401, 403] }

    with_them do
      it 'resolves the connection null silently, beside the rendered package', :aggregate_failures do
        stub_repository_read
        stub_package_read
        stub_dist_tags_list(status: status, body: error_envelope(code: 'denied').to_json)

        post_query

        expect(package_response['id']).to eq(package_id)
        expect(dist_tags_response).to be_nil
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the dist-tags read is unavailable (5xx), asserting request_id' do
    it 'preserves the request_id in the error extensions', :aggregate_failures do
      stub_repository_read
      stub_package_read
      stub_dist_tags_list(status: 503, body: error_envelope(code: 'unavailable', request_id: 'req-503').to_json)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
    end
  end

  context 'when a forward cursor is supplied' do
    let(:after_cursor) { 'eyJpZCI6MjB9' }

    it 'forwards the cursor to Artifact Registry', :aggregate_failures do
      stub_repository_read
      stub_package_read
      paged = stub_dist_tags_list(query: { limit: '100', cursor: after_cursor })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     artifactId: package_id, first: 100, after: after_cursor })

      expect(paged).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      package = stub_package_read
      tags = stub_dist_tags_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(package).not_to have_been_requested
      expect(tags).not_to have_been_requested
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

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_package_read(status: 200, body: package_body.to_json, headers: json_headers)
    stub_request(:get, package_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_dist_tags_list(status: 200, body: dist_tags_body.to_json, headers: json_headers, query: { limit: '100' })
    stub_request(:get, dist_tags_url).with(query: query).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def package_response
    repository_response&.dig('package')
  end

  def dist_tags_response
    package_response&.dig('distTags')
  end
end
