# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository images connection', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:page_size) { 20 }
  let(:current_user) { organization_user }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:images_url) { "#{repository_url}/#{format}/images" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Docker repository',
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'settings' => {}
    }
  end

  # `digest` rides the stub to stand in for a field the payload carries but no type exposes, so
  # it never reaches the response.
  let(:image) do
    {
      'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
      'name' => 'payment-core',
      'last_downloaded_at' => '2026-07-03T09:15:00Z',
      'digest' => 'sha256:aaaa'
    }
  end

  let(:other_image) do
    image.merge(
      'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
      'name' => 'payment-api',
      'last_downloaded_at' => nil
    )
  end

  let(:images_body) { [image, other_image] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositoryImages(
        $id: OrganizationsOrganizationID!
        $name: String!
        $first: Int
        $after: String
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            images(first: $first, after: $after) {
              nodes {
                id
                name
                lastDownloadedAt
              }
              pageInfo {
                hasNextPage
                hasPreviousPage
                startCursor
                endCursor
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
      variables: { id: organization.to_global_id.to_s, name: repository_name, first: page_size, after: nil })
  end

  shared_examples 'resolving the connection null while the repository still renders' do
    it 'renders a null connection, no error, and the repository around it', :aggregate_failures do
      stub_repository_read

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(images_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error beside the loaded repository' do
    it 'renders the service-unavailable error and keeps the repository rendered', :aggregate_failures do
      stub_repository_read

      post_query

      expect(images_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the repository holds Docker images' do
    let(:next_cursor) { 'eyJpZCI6MjB9' }
    let(:prev_cursor) { 'eyJpZCI6MTB9' }

    let(:link_header) do
      %(<#{images_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{images_url}?cursor=#{prev_cursor}>; rel="prev")
    end

    it 'renders the id, the name, and the pull timestamp of every image' do
      stub_repository_read
      stub_images_list

      post_query

      expect(images_response['nodes']).to eq(
        [
          { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000', 'name' => 'payment-core',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00' },
          { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'name' => 'payment-api',
            'lastDownloadedAt' => nil }
        ]
      )
    end

    it 'issues one images request under the repository format segment, with no per-row follow-up',
      :aggregate_failures do
      stub_repository_read
      list = stub_images_list
      row = stub_request(:get, "#{images_url}/e5f6a7b8-0000-0000-0000-000000000000")

      post_query

      expect(list).to have_been_requested.once
      expect(row).not_to have_been_requested
    end

    it 'exposes the Link-header cursors through pageInfo' do
      stub_repository_read
      stub_images_list(headers: json_headers.merge('Link' => link_header))

      post_query

      expect(images_response['pageInfo']).to eq(
        'hasNextPage' => true,
        'hasPreviousPage' => true,
        'startCursor' => prev_cursor,
        'endCursor' => next_cursor
      )
    end

    it 'carries the forward cursor the Link header handed back into the next read', :aggregate_failures do
      stub_repository_read
      first_page = stub_images_list(headers: json_headers.merge('Link' => link_header))
      next_page = stub_images_list(query: default_query.merge(cursor: next_cursor))

      post_query

      expect(images_response['pageInfo']['endCursor']).to eq(next_cursor)

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name, first: page_size,
                     after: next_cursor })

      expect(first_page).to have_been_requested.once
      expect(next_page).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end

    it 'renders the page without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_images_list

      post_query

      expect(images_response['nodes'].pluck('name')).to eq(%w[payment-core payment-api])
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-images' }

    it 'renders every selected image field under the oci format segment' do
      stub_repository_read
      stub_images_list

      post_query

      expect(images_response['nodes']).to eq(
        [
          { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000', 'name' => 'payment-core',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00' },
          { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'name' => 'payment-api',
            'lastDownloadedAt' => nil }
        ]
      )
    end
  end

  context 'when the repository holds no images yet' do
    it 'renders an empty connection rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_images_list(body: [].to_json)

      post_query

      expect(images_response['nodes']).to eq([])
      expect(images_response['pageInfo']).to eq(
        'hasNextPage' => false,
        'hasPreviousPage' => false,
        'startCursor' => nil,
        'endCursor' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds packages rather than images' do
    where(:format, :repository_name) do
      [%w[maven maven-releases], %w[npm npm-releases]]
    end

    with_them do
      it 'resolves the connection null without asking Artifact Registry for images', :aggregate_failures do
        stub_repository_read
        list = stub_images_list

        post_query

        expect(images_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(list).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository is virtual' do
    let(:repository_body) { super().merge('kind' => 'virtual') }

    where(:format, :repository_name) do
      [%w[docker docker-virtual], %w[oci oci-virtual]]
    end

    with_them do
      it 'resolves the connection null without asking Artifact Registry for images', :aggregate_failures do
        stub_repository_read
        list = stub_images_list

        post_query

        expect(images_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(list).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository was deleted between the two reads (404 on the list)' do
    before do
      stub_images_list(status: 404, body: error_envelope(code: 'not_found').to_json)
    end

    it_behaves_like 'resolving the connection null while the repository still renders'
  end

  [401, 403].each do |status|
    context "when Artifact Registry rejects the list read with #{status}" do
      before do
        stub_images_list(status: status, body: error_envelope(code: 'forbidden').to_json)
      end

      it_behaves_like 'resolving the connection null while the repository still renders'
    end
  end

  context 'when Artifact Registry answers the list read with a server error' do
    before do
      stub_images_list(status: 503, body: error_envelope(code: 'service_unavailable').to_json)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read fails in transport' do
    before do
      stub_request(:get, images_url).with(query: default_query).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read times out' do
    before do
      stub_request(:get, images_url).with(query: default_query).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      list = stub_images_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(list).not_to have_been_requested
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

  # Over the wire, through the real field, so this is what proves the field's `max_page_size: 20`
  # rather than the schema default of 100. `ArtifactRegistry::PaginatesLists` reads the cap off
  # the field, and the resolver unit spec cannot see it: its synthetic field carries no cap.
  context 'when the caller requests more rows than the field allows' do
    let(:page_size) { GitlabSchema.default_max_page_size }

    it 'caps the outbound Artifact Registry limit at 20' do
      stub_repository_read
      capped = stub_images_list(query: { limit: '20' })

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(capped).to have_been_requested
    end
  end

  # The detail type keeps this connection off a repository list, but aliases would otherwise let
  # one operation resolve it repeatedly on the same repository, each resolution its own Artifact
  # Registry request. `FieldCallCount` allows the first and raises on the second before its
  # resolve body runs, so the whole operation costs one list request rather than two.
  context 'when one operation selects the connection twice under aliases' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              name
              a: images(first: 5) { nodes { id } }
              b: images(first: 5) { nodes { id } }
            }
          }
        }
      QUERY
    end

    subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the second selection and issues one list request, not two', :aggregate_failures do
      stub_repository_read
      list = stub_images_list(query: { limit: '5' })

      post_aliased_query

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(list).to have_been_requested.once
    end
  end

  # `first`/`after` are exercised throughout; `last`/`before` were reachable only through the
  # resolver unit path, which builds a synthetic field. This runs them through the real field, so
  # the connection extension, the outbound cursor, and the returned page info are covered end to
  # end.
  context 'when paging backward' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(last: 5, before: "#{prev_cursor}") {
                nodes { id }
                pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              }
            }
          }
        }
      QUERY
    end

    let(:prev_cursor) { 'eyJpZCI6MTB9' }

    let(:next_cursor) { 'eyJpZCI6MjB9' }

    let(:link_header) do
      %(<#{images_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{images_url}?cursor=#{prev_cursor}>; rel="prev")
    end

    subject(:post_backward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the backward cursor and renders the page it returns', :aggregate_failures do
      stub_repository_read
      backward = stub_images_list(
        query: { limit: '5', cursor: prev_cursor },
        headers: json_headers.merge('Link' => link_header)
      )

      post_backward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(backward).to have_been_requested.once
      expect(graphql_errors).to be_nil

      expect(images_response['nodes']).to eq(
        [
          { 'id' => 'e5f6a7b8-0000-0000-0000-000000000000' },
          { 'id' => 'f6a7b8c9-0000-0000-0000-000000000000' }
        ]
      )
      expect(images_response['pageInfo']).to eq(
        'hasNextPage' => true,
        'hasPreviousPage' => true,
        'startCursor' => prev_cursor,
        'endCursor' => next_cursor
      )
    end
  end

  # The natural query shape for a detail view. `FieldCallCount` keys on the Field instance, so the
  # two connections carry independent budgets: selecting both in one operation is legal and reads
  # each once.
  context 'when one operation selects packages and images together' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 5) { nodes { id } }
              packages(first: 5) { nodes { __typename } }
            }
          }
        }
      QUERY
    end

    subject(:post_both_query) { post_graphql(query, current_user: current_user) }

    it 'reads the image page and nulls packages for a container repository', :aggregate_failures do
      stub_repository_read
      images = stub_images_list(query: { limit: '5' })
      packages = stub_request(:get, "#{repository_url}/#{format}/packages")

      post_both_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(images).to have_been_requested.once
      expect(packages).not_to have_been_requested
      expect(images_response['nodes'].pluck('id')).to eq(
        %w[e5f6a7b8-0000-0000-0000-000000000000 f6a7b8c9-0000-0000-0000-000000000000]
      )
      expect(repository_response['packages']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  # The budget keys on the field, not the repository, so it spans repository aliases too:
  # selecting images under a second repository in the same operation raises before its read,
  # and the operation issues one list request rather than two.
  context 'when one operation selects images under two repository aliases' do
    let(:other_repository_name) { 'other-container-images' }
    let(:other_repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{other_repository_name}" }
    let(:other_images_url) { "#{other_repository_url}/#{format}/images" }

    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            a: artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 5) { nodes { id } }
            }
            b: artifactRegistryRepository(name: "#{other_repository_name}") {
              images(first: 5) { nodes { id } }
            }
          }
        }
      QUERY
    end

    subject(:post_two_alias_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the second repository selection and issues one list request, not two', :aggregate_failures do
      stub_repository_read
      stub_request(:get, other_repository_url)
        .to_return(status: 200, body: repository_body.merge('name' => other_repository_name).to_json,
          headers: json_headers)
      first_list = stub_images_list(query: { limit: '5' })
      second_list = stub_request(:get, other_images_url)
        .with(query: { limit: '5' })
        .to_return(status: 200, body: images_body.to_json, headers: json_headers)

      post_two_alias_query

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(first_list).to have_been_requested.once
      expect(second_list).not_to have_been_requested
    end
  end

  # `FieldCallCount` keys on the operation fingerprint, so a multiplex gets the budget per
  # operation rather than once overall. The repository read is still coalesced across the whole
  # request, which is what keeps the external cost bounded here.
  context 'when a multiplex carries the same selection in two operations' do
    let(:multiplex_query) do
      <<~QUERY
        query OPERATION_NAME {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 5) { nodes { id } }
            }
          }
        }
      QUERY
    end

    it 'budgets images per operation and reads the repository once', :aggregate_failures do
      detail = stub_repository_read
      list = stub_images_list(query: { limit: '5' })

      post_multiplex(
        [
          { query: multiplex_query.sub('OPERATION_NAME', 'first_operation') },
          { query: multiplex_query.sub('OPERATION_NAME', 'second_operation') }
        ],
        current_user: current_user
      )

      expect(response).to have_gitlab_http_status(:ok)
      expect(detail).to have_been_requested.once
      expect(list).to have_been_requested.twice
      expect(json_response.pluck('errors').flatten.compact).to be_empty
    end
  end

  def default_query
    { limit: page_size.to_s }
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_images_list(status: 200, body: images_body.to_json, headers: json_headers, query: default_query)
    stub_request(:get, images_url)
      .with(query: query)
      .to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def images_response
    repository_response&.dig('images')
  end
end
