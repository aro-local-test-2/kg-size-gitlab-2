# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry single manifest field', feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:image_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:digest) { 'sha256:aaaa' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:manifest_url) { "#{repository_url}/#{format}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'settings' => {}
    }
  end

  # An index: its children carry the platform triple, and its own triple is null.
  let(:manifest_body) do
    {
      'id' => 'm1000-0000-0000-0000-000000000000',
      'digest' => digest,
      'media_type' => 'application/vnd.oci.image.index.v1+json',
      'artifact_type' => nil,
      'subject_digest' => nil,
      'size' => 3_221_225_472,
      'created_at' => '2026-07-03T09:15:00Z',
      'architecture' => nil,
      'os' => nil,
      'os_variant' => nil,
      'tags' => %w[latest v1.2.0],
      'tags_count' => 2,
      'children' => [
        {
          'digest' => 'sha256:bbbb',
          'architecture' => 'amd64',
          'os' => 'linux',
          'os_variant' => nil
        }
      ],
      'children_count' => 1,
      'parent_digests' => [],
      'parents_count' => 0,
      'referrers_count' => 0,
      'annotations' => { 'org.opencontainers.image.source' => 'https://example.test/repo' }
    }
  end

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryManifest($id: OrganizationsOrganizationID!, $name: String!, $artifactId: ID!, $digest: String!) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            manifest(artifactId: $artifactId, digest: $digest) {
              id
              digest
              mediaType
              artifactType
              subjectDigest
              size
              createdAt
              architecture
              os
              osVariant
              tags
              tagsCount
              children { digest architecture os osVariant }
              childrenCount
              parentDigests
              parentsCount
              referrersCount
              annotations { key value }
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
      variables: { id: organization.to_global_id.to_s, name: repository_name, artifactId: image_id, digest: digest })
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_manifest_read(status: 200, body: manifest_body.to_json, headers: json_headers)
    stub_request(:get, manifest_url).to_return(status: status, body: body, headers: headers)
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

  shared_examples 'reading the manifest for the format' do
    it 'renders every contract-backed detail field, including the nullable ones', :aggregate_failures do
      stub_repository_read
      read = stub_manifest_read

      post_query

      expect(manifest_response).to eq(
        'id' => 'm1000-0000-0000-0000-000000000000',
        'digest' => digest,
        'mediaType' => 'application/vnd.oci.image.index.v1+json',
        'artifactType' => nil,
        'subjectDigest' => nil,
        'size' => '3221225472',
        'createdAt' => '2026-07-03T09:15:00+00:00',
        'architecture' => nil,
        'os' => nil,
        'osVariant' => nil,
        'tags' => %w[latest v1.2.0],
        'tagsCount' => 2,
        'children' => [
          { 'digest' => 'sha256:bbbb', 'architecture' => 'amd64', 'os' => 'linux', 'osVariant' => nil }
        ],
        'childrenCount' => 1,
        'parentDigests' => [],
        'parentsCount' => 0,
        'referrersCount' => 0,
        'annotations' => [{ 'key' => 'org.opencontainers.image.source', 'value' => 'https://example.test/repo' }]
      )
      expect(read).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end

    it 'never leaks the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds Docker images' do
    it_behaves_like 'reading the manifest for the format'
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-artifacts' }

    it_behaves_like 'reading the manifest for the format'
  end

  # An empty annotations map and an absent one mean different things and the contract keeps them
  # apart: the resolver serializes empty to an empty list and absent to null.
  context 'when the manifest annotations are empty rather than absent' do
    let(:manifest_body) { super().merge('annotations' => {}) }

    it 'renders an empty annotations list, distinct from null' do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(manifest_response['annotations']).to eq([])
    end
  end

  context 'when the manifest carried no annotations key' do
    let(:manifest_body) { super().merge('annotations' => nil) }

    it 'renders null annotations rather than an empty list' do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(manifest_response['annotations']).to be_nil
    end
  end

  # A single-image child carries its own platform triple and no children; parentDigests names the
  # indexes that reference it.
  context 'when the manifest is a single-image child' do
    let(:digest) { 'sha256:bbbb' }
    let(:manifest_body) do
      {
        'id' => 'm2000-0000-0000-0000-000000000000',
        'digest' => digest,
        'media_type' => 'application/vnd.oci.image.manifest.v1+json',
        'artifact_type' => nil,
        'subject_digest' => nil,
        'size' => 2048,
        'created_at' => '2026-07-03T09:15:00Z',
        'architecture' => 'amd64',
        'os' => 'linux',
        'os_variant' => 'v8',
        'tags' => [],
        'tags_count' => 0,
        'children' => [],
        'children_count' => 0,
        'parent_digests' => ['sha256:aaaa'],
        'parents_count' => 1,
        'referrers_count' => 0,
        'annotations' => nil
      }
    end

    it 'renders the platform triple and the parent digests, with no children', :aggregate_failures do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(manifest_response).to include(
        'architecture' => 'amd64', 'os' => 'linux', 'osVariant' => 'v8',
        'children' => [], 'childrenCount' => 0,
        'parentDigests' => ['sha256:aaaa'], 'parentsCount' => 1
      )
    end
  end

  # A referrer read by its own digest carries its subjectDigest, unlike the manifests list, which
  # is the behavior the detail type's subjectDigest field promises over the list element's.
  context 'when the manifest is itself a referrer' do
    let(:digest) { 'sha256:cccc' }
    let(:manifest_body) do
      super().merge(
        'digest' => digest,
        'media_type' => 'application/vnd.oci.image.manifest.v1+json',
        'artifact_type' => 'application/vnd.example.sbom.v1+json',
        'subject_digest' => 'sha256:aaaa'
      )
    end

    it 'renders the subject digest and the artifact type', :aggregate_failures do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(manifest_response).to include(
        'subjectDigest' => 'sha256:aaaa',
        'artifactType' => 'application/vnd.example.sbom.v1+json'
      )
    end
  end

  # The response Artifact Registry serves today omits parentDigests and parentsCount entirely, and
  # tags and children on a deployment predating those fields. An omitted key is absent rather than
  # null, so the value object reads nil and the field renders null rather than an empty array.
  context 'when Artifact Registry omits the not-yet-served and deployment-gated keys' do
    let(:manifest_body) do
      super().except('tags', 'children', 'parent_digests', 'parents_count')
    end

    it 'renders the four fields null rather than as empty arrays or zero counts', :aggregate_failures do
      stub_repository_read
      stub_manifest_read

      post_query

      expect(manifest_response).to include(
        'tags' => nil, 'children' => nil, 'parentDigests' => nil, 'parentsCount' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  # The children digest and annotation value feed non-null schema fields. A malformed row served
  # for either would otherwise raise a coercion error that propagates up the non-null list element
  # and nulls the whole array plus a top-level error, emptying the block on one bad row. The type
  # drops the bad row instead, matching the value object's shape defense.
  context 'when Artifact Registry serves a malformed row in an otherwise valid array' do
    it 'drops a child missing a string digest rather than nulling the whole children array',
      :aggregate_failures do
      body = manifest_body.merge('children' => [
        { 'digest' => 'sha256:bbbb', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil },
        { 'architecture' => 'arm64', 'os' => 'linux', 'os_variant' => nil }
      ])
      stub_repository_read
      stub_manifest_read(body: body.to_json)

      post_query

      expect(manifest_response['children']).to eq(
        [{ 'digest' => 'sha256:bbbb', 'architecture' => 'amd64', 'os' => 'linux', 'osVariant' => nil }]
      )
      expect(graphql_errors).to be_nil
    end

    it 'drops an annotation whose value is not a string rather than nulling the whole array',
      :aggregate_failures do
      body = manifest_body.merge('annotations' => {
        'org.opencontainers.image.source' => 'https://example.test/repo',
        'org.opencontainers.image.created' => nil
      })
      stub_repository_read
      stub_manifest_read(body: body.to_json)

      post_query

      expect(manifest_response['annotations']).to eq(
        [{ 'key' => 'org.opencontainers.image.source', 'value' => 'https://example.test/repo' }]
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds packages rather than images' do
    let(:format) { 'maven' }
    let(:repository_name) { 'maven-releases' }

    it 'resolves the field null without reaching Artifact Registry', :aggregate_failures do
      stub_repository_read
      read = stub_manifest_read

      post_query

      expect(manifest_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(read).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  # The field promises a blank or dot-segment digest resolves without a read; this pins that
  # promise end to end, where the client_spec covers it only at the unit level.
  context 'when the digest is blank' do
    let(:digest) { '' }

    it 'resolves the field null without reaching Artifact Registry, and still renders the repository',
      :aggregate_failures do
      stub_repository_read
      read = stub_manifest_read

      post_query

      expect(manifest_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(read).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  # 404, 401, and 403 all take the existence-hiding arm: the field resolves null and the
  # repository still renders, so a missing manifest and a forbidden one are indistinguishable.
  [404, 401, 403].each do |status|
    context "when Artifact Registry answers the manifest read with #{status}" do
      it 'resolves the field null while the repository still renders', :aggregate_failures do
        stub_repository_read
        stub_manifest_read(status: status, body: error_envelope(code: 'not_found').to_json)

        post_query

        expect(manifest_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when Artifact Registry answers the manifest read with a server error' do
    it 'renders the service-unavailable error beside the loaded repository, with request_id preserved',
      :aggregate_failures do
      stub_repository_read
      stub_manifest_read(
        status: 503, body: error_envelope(code: 'service_unavailable', request_id: 'req-503').to_json)

      post_query

      expect(manifest_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
    end
  end

  context 'when Artifact Registry answers the manifest read with a non-404 client error' do
    it 'surfaces a top-level error carrying the request_id, and still renders the repository',
      :aggregate_failures do
      stub_repository_read
      stub_manifest_read(
        status: 422, body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json)

      post_query

      expect(manifest_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(graphql_errors).to be_present
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
    end
  end

  # The repository read is pinned to exactly one request and the repository is asserted to still
  # render, so the service-unavailable error is tied to the manifest read rather than a failed
  # repository read, which would emit the same message.
  context 'when the manifest read fails in transport' do
    it 'renders the service-unavailable error on a connection failure, beside the loaded repository',
      :aggregate_failures do
      repository = stub_repository_read
      stub_request(:get, manifest_url).to_raise(Faraday::ConnectionFailed)

      post_query

      expect(repository_response['name']).to eq(repository_name)
      expect(repository).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end

    it 'renders the service-unavailable error on a timeout, which the retry middleware handles',
      :aggregate_failures do
      repository = stub_repository_read
      stub_request(:get, manifest_url).to_timeout

      post_query

      expect(repository_response['name']).to eq(repository_name)
      expect(repository).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      manifest = stub_manifest_read

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(manifest).not_to have_been_requested
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

  # The anonymous caller takes a distinct path through the client's service-credential branch
  # and CachesClient memoization; the no-existence-leak guarantee must hold for it too.
  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  # The per-field `FieldCallCount` budget of 1 stops a second aliased selection of the manifest
  # field before its resolve body runs, so the operation issues one manifest read rather than two.
  context 'when one operation selects the manifest field twice under aliases' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              a: manifest(artifactId: "#{image_id}", digest: "#{digest}") { __typename }
              b: manifest(artifactId: "#{image_id}", digest: "#{digest}") { __typename }
            }
          }
        }
      QUERY
    end

    subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the second selection and issues one manifest read, not two', :aggregate_failures do
      stub_repository_read
      read = stub_manifest_read

      post_aliased_query

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(read).to have_been_requested.once
    end
  end

  describe 'granular PAT authorization' do
    before do
      stub_repository_read
      stub_manifest_read
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
          variables: { id: organization.to_global_id.to_s, name: repository_name, artifactId: image_id,
                       digest: digest })
      end

      let(:skipped_data_path) { %i[organization artifact_registry_repository manifest] }
    end
  end
end
