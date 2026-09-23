# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry manifest referrers connection', feature_category: :artifact_registry do
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
  let(:referrers_first) { 20 }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:image_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:digest) { 'sha256:aaaa' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:manifest_url) { "#{repository_url}/#{format}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}" }
  let(:referrers_url) { "#{manifest_url}/referrers" }

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

  let(:manifest_body) do
    {
      'id' => 'm1000-0000-0000-0000-000000000000',
      'digest' => digest,
      'media_type' => 'application/vnd.oci.image.index.v1+json'
    }
  end

  # A referrer is an ordinary manifest row: it carries a subject_digest naming the manifest it
  # refers to, which is this manifest's digest.
  let(:referrer_row) do
    {
      'id' => 'r1000-0000-0000-0000-000000000000',
      'digest' => 'sha256:dddd',
      'media_type' => 'application/vnd.oci.image.manifest.v1+json',
      'artifact_type' => 'application/vnd.example.sbom.v1+json',
      'subject_digest' => digest,
      'size' => 2048,
      'created_at' => '2026-07-03T09:15:00Z'
    }
  end

  let(:referrers_body) { [referrer_row] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryManifestReferrers(
        $id: OrganizationsOrganizationID!
        $name: String!
        $artifactId: ID!
        $digest: String!
        $first: Int
        $after: String
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            manifest(artifactId: $artifactId, digest: $digest) {
              digest
              referrers(first: $first, after: $after) {
                nodes { id digest mediaType artifactType subjectDigest size createdAt }
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
                   artifactId: image_id, digest: digest, first: referrers_first, after: nil })
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_manifest_read(status: 200, body: manifest_body.to_json, headers: json_headers)
    stub_request(:get, manifest_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_referrers_list(status: 200, body: referrers_body.to_json, headers: json_headers, query: { limit: '20' })
    stub_request(:get, referrers_url).with(query: query).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def manifest_response
    repository_response&.dig('manifest')
  end

  def referrers_response
    manifest_response&.dig('referrers')
  end

  shared_examples 'listing referrers for the format' do
    it 'renders the referrer rows as the unwidened manifest element type', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list

      post_query

      expect(referrers_response['nodes']).to eq(
        [
          {
            'id' => 'r1000-0000-0000-0000-000000000000',
            'digest' => 'sha256:dddd',
            'mediaType' => 'application/vnd.oci.image.manifest.v1+json',
            'artifactType' => 'application/vnd.example.sbom.v1+json',
            'subjectDigest' => digest,
            'size' => '2048',
            'createdAt' => '2026-07-03T09:15:00+00:00'
          }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    it 'reads the manifest once and the referrers once, with no per-row follow-up', :aggregate_failures do
      stub_repository_read
      manifest = stub_manifest_read
      referrers = stub_referrers_list

      post_query

      expect(manifest).to have_been_requested.once
      expect(referrers).to have_been_requested.once
    end
  end

  context 'when the repository holds Docker images' do
    it_behaves_like 'listing referrers for the format'

    it 'exposes the Link-header cursors through pageInfo' do
      next_cursor = 'eyJpZCI6MjB9'
      prev_cursor = 'eyJpZCI6MTB9'
      stub_repository_read
      stub_manifest_read
      stub_referrers_list(headers: json_headers.merge('Link' =>
        %(<#{referrers_url}?cursor=#{next_cursor}>; rel="next", <#{referrers_url}?cursor=#{prev_cursor}>; rel="prev")))

      post_query

      expect(referrers_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
    end

    it 'renders the referrers without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list

      post_query

      expect(referrers_response['nodes']).to be_present
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-artifacts' }

    it_behaves_like 'listing referrers for the format'
  end

  context 'when the caller requests a page larger than the monolith maximum' do
    let(:referrers_first) { ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE + 1 }

    it 'caps the outbound limit at the maximum page size' do
      stub_repository_read
      stub_manifest_read
      capped = stub_referrers_list(query: { limit: ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE.to_s })

      post_query

      expect(capped).to have_been_requested.once
    end
  end

  context 'when a forward cursor is supplied' do
    let(:after_cursor) { 'eyJpZCI6MjB9' }

    it 'forwards the cursor to Artifact Registry', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      paged = stub_referrers_list(query: { limit: '20', cursor: after_cursor })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     artifactId: image_id, digest: digest, first: referrers_first, after: after_cursor })

      expect(paged).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when paging backward with last and before' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryManifestReferrersBackward(
          $id: OrganizationsOrganizationID!, $name: String!, $artifactId: ID!, $digest: String!,
          $last: Int, $before: String
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              manifest(artifactId: $artifactId, digest: $digest) {
                referrers(last: $last, before: $before) { nodes { id } }
              }
            }
          }
        }
      QUERY
    end

    it 'forwards the before cursor and the last limit', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      paged = stub_referrers_list(query: { limit: '5', cursor: 'eyJpZCI6MTB9' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     artifactId: image_id, digest: digest, last: 5, before: 'eyJpZCI6MTB9' })

      expect(paged).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  # An empty referrers array is the shape a remote repository always serves (its referrers route
  # returns 200 with []), but no resolver branch inspects the repository kind, so an empty body is
  # the faithful stand-in. An empty connection is distinct from a null one (a failed read).
  context 'when the manifest has no referrers' do
    let(:referrers_body) { [] }

    it 'renders an empty connection, not a null one', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list

      post_query

      expect(referrers_response['nodes']).to eq([])
      expect(referrers_response['pageInfo']).to include('hasNextPage' => false, 'hasPreviousPage' => false)
      expect(graphql_errors).to be_nil
    end
  end

  # 404 is swallowed in the client; 401/403 raise AuthorizationError and take a different path.
  # All three resolve the connection null with no error (existence-hiding).
  context 'when the referrers read is rejected with a silent status' do
    where(:status) { [404, 401, 403] }

    with_them do
      it 'resolves the connection null with no error, the manifest still rendering', :aggregate_failures do
        stub_repository_read
        stub_manifest_read
        stub_referrers_list(status: status, body: error_envelope(code: 'denied').to_json)

        post_query

        expect(referrers_response).to be_nil
        expect(manifest_response['digest']).to eq(digest)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the referrers read maps to a service-unavailable error' do
    where(:status, :error_code, :request_id) do
      503 | 'unavailable'  | 'req-503'
      429 | 'rate_limited' | 'req-429'
    end

    with_them do
      it 'renders the service-unavailable error beside the loaded manifest, with request_id preserved',
        :aggregate_failures do
        stub_repository_read
        stub_manifest_read
        stub_referrers_list(status: status, body: error_envelope(code: error_code, request_id: request_id).to_json)

        post_query

        expect(referrers_response).to be_nil
        expect(manifest_response['digest']).to eq(digest)
        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
        expect(graphql_errors.first.dig('extensions', 'request_id')).to eq(request_id)
      end
    end
  end

  context 'when the referrers read returns a non-404 client error' do
    it 'surfaces a top-level error carrying the request_id, and still renders the manifest',
      :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list(status: 422, body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json)

      post_query

      expect(referrers_response).to be_nil
      expect(manifest_response['digest']).to eq(digest)
      expect(graphql_errors).to be_present
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
    end
  end

  # The manifest read is pinned to exactly one request and the manifest is asserted to still
  # render, so the service-unavailable error is tied to the referrers read rather than the manifest
  # read, which would emit the same message.
  context 'when the referrers read fails in transport' do
    it 'renders the service-unavailable error on a connection failure, beside the loaded manifest',
      :aggregate_failures do
      stub_repository_read
      manifest = stub_manifest_read
      stub_request(:get, referrers_url).with(query: { limit: '20' }).to_raise(Faraday::ConnectionFailed)

      post_query

      expect(manifest_response['digest']).to eq(digest)
      expect(manifest).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end

    it 'renders the service-unavailable error on a timeout, which the retry middleware handles',
      :aggregate_failures do
      stub_repository_read
      manifest = stub_manifest_read
      stub_request(:get, referrers_url).with(query: { limit: '20' }).to_timeout

      post_query

      expect(manifest_response['digest']).to eq(digest)
      expect(manifest).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  # ManifestType declares digest non-null, and the row value object passes AR's keys through
  # unvalidated, so a malformed row missing digest nulls that one node and raises a top-level
  # error rather than nulling the whole connection. The frontend table must tolerate a null node.
  # The manifests connection and this one are equally undefended here; ManifestDetails#children is
  # the only referrer-family field that filters, and widening the shared element type is out of
  # this MR's scope. This pins the current blast radius so a change to it is visible.
  context 'when Artifact Registry serves a referrer row missing its non-null digest' do
    let(:referrers_body) do
      [referrer_row, referrer_row.merge('id' => 'r2000-0000-0000-0000-000000000000').except('digest')]
    end

    it 'nulls only the malformed node and raises one error, not the whole connection',
      :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list

      post_query

      nodes = referrers_response['nodes']
      expect(nodes.first['id']).to eq('r1000-0000-0000-0000-000000000000')
      expect(nodes.last).to be_nil
      expect_graphql_errors_to_include(/Cannot return null for non-nullable field/)
    end
  end

  # The manifest detail carries an id but, if AR violated its contract, could omit the digest.
  # The referrers read then raises an argument error at the client's segment guard, which
  # RendersErrors surfaces as a top-level error. Not reachable while AR honors S17; pinned so the
  # behavior is documented rather than discovered.
  context 'when the manifest body carries an id but no digest' do
    let(:manifest_body) { super().except('digest') }

    it 'surfaces a top-level error and resolves the connection null', :aggregate_failures do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(referrers_response).to be_nil
      expect(graphql_errors).to be_present
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      manifest = stub_manifest_read
      referrers = stub_referrers_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(manifest).not_to have_been_requested
      expect(referrers).not_to have_been_requested
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

  context 'when the referrers connection is selected twice in one operation' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryManifestReferrersAliased(
          $id: OrganizationsOrganizationID!, $name: String!, $artifactId: ID!, $digest: String!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              manifest(artifactId: $artifactId, digest: $digest) {
                referrers(first: 5) { nodes { id } }
                second: referrers(first: 5) { nodes { id } }
              }
            }
          }
        }
      QUERY
    end

    it 'raises the call-count limit rather than issuing a second referrers read', :aggregate_failures do
      stub_repository_read
      stub_manifest_read
      referrers = stub_referrers_list(query: { limit: '5' })

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     artifactId: image_id, digest: digest })

      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(referrers).to have_been_requested.once
    end
  end

  describe 'granular PAT authorization' do
    before do
      stub_repository_read
      stub_manifest_read
      stub_referrers_list
    end

    # The manifest types skip their own granular check; Organization authorizes `read_organization`
    # at the instance boundary for the whole subtree. `read_artifact_registry` has no assignable
    # permission, so it cannot gate a granular token.
    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_organization do
      let(:user) { current_user }
      let(:boundary_object) { :instance }
      let(:request) do
        post_graphql(query, current_user: user, token: { personal_access_token: pat },
          variables: { id: organization.to_global_id.to_s, name: repository_name,
                       artifactId: image_id, digest: digest, first: referrers_first, after: nil })
      end

      let(:skipped_data_path) { %i[organization artifact_registry_repository manifest referrers] }
    end
  end
end
