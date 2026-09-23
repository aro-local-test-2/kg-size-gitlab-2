# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry manifests connection', feature_category: :artifact_registry do
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
  let(:manifests_first) { 20 }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:image_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:other_image_id) { 'f6a7b8c9-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:images_url) { "#{repository_url}/#{format}/images" }
  let(:manifests_url) { "#{images_url}/#{image_id}/manifests" }
  let(:other_manifests_url) { "#{images_url}/#{other_image_id}/manifests" }

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

  let(:image_body) { { 'id' => image_id, 'name' => 'api-gateway' } }
  let(:images_body) { [image_body, { 'id' => other_image_id, 'name' => 'payment-core' }] }

  # A non-referrer row: this is the only shape the read this MR opens can return, because it
  # leaves Artifact Registry on its `include_referrers=false` default, which filters out every
  # row carrying a subject_digest.
  let(:manifest_row) do
    {
      'id' => 'm1000-0000-0000-0000-000000000000',
      'digest' => 'sha256:aaaa',
      'media_type' => 'application/vnd.oci.image.manifest.v1+json',
      'artifact_type' => nil,
      'subject_digest' => nil,
      'size' => 2048,
      'created_at' => '2026-07-03T09:15:00Z',
      'tags_preview' => %w[latest v1],
      'parents_preview' => ['sha256:parent'],
      'children_preview' => [
        { 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
      ]
    }
  end

  let(:manifests_body) { [manifest_row] }
  let(:other_manifests_body) do
    [manifest_row.merge('id' => 'm2000-0000-0000-0000-000000000000', 'digest' => 'sha256:cccc', 'size' => 4096)]
  end

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryManifests($id: OrganizationsOrganizationID!, $name: String!, $first: Int) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            images(first: 20) {
              nodes {
                id
                manifests(first: $first) {
                  nodes {
                    id digest mediaType artifactType subjectDigest size createdAt
                    tagsPreview parentsPreview
                    childrenPreview { digest architecture os osVariant }
                  }
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
      variables: { id: organization.to_global_id.to_s, name: repository_name, first: manifests_first })
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  # The manifests connection hangs off an image element, reached through the images list.
  def stub_image_read(status: 200, body: images_body.to_json, query: { limit: '20' })
    stub_request(:get, images_url).with(query: query)
      .to_return(status: status, body: body, headers: json_headers)
  end

  def stub_manifests_list(
    url: manifests_url, status: 200, body: manifests_body.to_json, headers: json_headers,
    query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
    stub_request(:get, url).with(query: query).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def image_nodes
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository, :images, :nodes)
  end

  def manifests_response
    image_nodes&.first&.dig('manifests')
  end

  shared_examples 'listing manifests for the format' do
    it 'renders every contract-backed manifest field, including the nullable ones', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(manifests_response['nodes']).to eq(
        [
          {
            'id' => 'm1000-0000-0000-0000-000000000000', 'digest' => 'sha256:aaaa',
            'mediaType' => 'application/vnd.oci.image.manifest.v1+json', 'artifactType' => nil,
            'subjectDigest' => nil, 'size' => '2048', 'createdAt' => '2026-07-03T09:15:00+00:00',
            'tagsPreview' => %w[latest v1], 'parentsPreview' => ['sha256:parent'],
            'childrenPreview' => [
              { 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'osVariant' => nil }
            ]
          }
        ]
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds Docker images' do
    it_behaves_like 'listing manifests for the format'

    it 'resolves the manifests once per image row, one request per image', :aggregate_failures do
      stub_repository_read
      stub_image_read
      first_image = stub_manifests_list
      second_image = stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(first_image).to have_been_requested.once
      expect(second_image).to have_been_requested.once
      expect(image_nodes.pluck('id')).to eq([image_id, other_image_id])
      expect(image_nodes.map { |node| node.dig('manifests', 'nodes').pluck('id') })
        .to eq([['m1000-0000-0000-0000-000000000000'], ['m2000-0000-0000-0000-000000000000']])
      expect(graphql_errors).to be_nil
    end

    it 'defaults include_referrers to false on the outbound read, matching the endpoint' do
      stub_repository_read
      stub_image_read
      list = stub_manifests_list(
        query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(list).to have_been_requested
    end

    it 'exposes the Link-header cursors through pageInfo' do
      next_cursor = 'eyJpZCI6MjB9'
      prev_cursor = 'eyJpZCI6MTB9'
      link = %(<#{manifests_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{manifests_url}?cursor=#{prev_cursor}>; rel="prev")
      stub_repository_read
      stub_image_read
      stub_manifests_list(headers: json_headers.merge('Link' => link))
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(manifests_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
    end

    it 'never leaks the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-artifacts' }

    it_behaves_like 'listing manifests for the format'
  end

  context 'when the image holds no manifests yet' do
    it 'renders an empty connection rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list(body: [].to_json)
      stub_manifests_list(url: other_manifests_url, body: [].to_json)

      post_query

      expect(manifests_response['nodes']).to eq([])
      expect(manifests_response['pageInfo']).to eq(
        'hasNextPage' => false, 'hasPreviousPage' => false, 'startCursor' => nil, 'endCursor' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a childrenPreview entry is missing its digest' do
    let(:manifest_row) do
      super().merge('children_preview' => [
        { 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil },
        { 'architecture' => 'arm64', 'os' => 'linux', 'os_variant' => nil }
      ])
    end

    it 'drops the malformed child rather than nulling the whole list', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json)

      post_query

      expect(manifests_response['nodes'].first['childrenPreview']).to eq(
        [{ 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'osVariant' => nil }]
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'with an explicit sort argument' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryManifestsSorted($id: OrganizationsOrganizationID!, $name: String!, $sort: ArtifactRegistryManifestSort) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              images(first: 20) {
                nodes { id manifests(first: 20, sort: $sort) { nodes { id } } }
              }
            }
          }
        }
      QUERY
    end

    # Every enum value reaches the client as its `sort`/`order` pair; the exact-match stub fails
    # the example if the wrong pair (or none) goes out.
    where(:sort_value, :outbound_order) do
      'CREATED_AT_ASC'  | 'asc'
      'CREATED_AT_DESC' | 'desc'
    end

    with_them do
      it 'forwards the enum value as the client sort column and order', :aggregate_failures do
        stub_repository_read
        stub_image_read
        sorted = stub_manifests_list(
          query: { limit: '20', sort: 'created_at', order: outbound_order, include_referrers: 'false' })
        stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
          query: { limit: '20', sort: 'created_at', order: outbound_order, include_referrers: 'false' })

        post_graphql(query, current_user: current_user,
          variables: { id: organization.to_global_id.to_s, name: repository_name, sort: sort_value })

        expect(sorted).to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the sort argument is explicitly null' do
      # `replace_null_with_default: true` turns an explicit `sort: null` into the default pair,
      # so the outbound read still carries `created_at`/`desc` rather than omitting sort.
      it 'falls back to the default publication-date-descending pair', :aggregate_failures do
        stub_repository_read
        stub_image_read
        default_sorted = stub_manifests_list(
          query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
        stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
          query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })

        post_graphql(query, current_user: current_user,
          variables: { id: organization.to_global_id.to_s, name: repository_name, sort: nil })

        expect(default_sorted).to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'with an explicit referrer-inclusion argument' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 20) {
                nodes { id manifests(first: 20, includeReferrers: true) { nodes { id } } }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_referrers_query) { post_graphql(query, current_user: current_user) }

    it 'forwards include_referrers=true to Artifact Registry when the caller asks for it' do
      stub_repository_read
      stub_image_read
      with_referrers = stub_manifests_list(
        query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'true' })
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
        query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'true' })

      post_referrers_query

      expect(with_referrers).to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the caller requests more rows than the field allows' do
    let(:manifests_first) { ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE + 1 }

    it 'caps the outbound manifests limit at the field max page size of 20' do
      stub_repository_read
      stub_image_read
      capped = stub_manifests_list(
        query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
        query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })

      post_query

      expect(capped).to have_been_requested
    end
  end

  context 'when Artifact Registry rejects the manifests read with a silent status' do
    where(:status, :code) do
      [[401, 'unauthorized'], [403, 'forbidden'], [404, 'not_found']]
    end

    with_them do
      it 'resolves the connection null while the image still renders', :aggregate_failures do
        stub_repository_read
        stub_image_read
        stub_manifests_list(status: status, body: error_envelope(code: code).to_json)
        stub_manifests_list(url: other_manifests_url, status: status, body: error_envelope(code: code).to_json)

        post_query

        expect(manifests_response).to be_nil
        expect(image_nodes.first['id']).to eq(image_id)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when Artifact Registry answers the manifests read with a server error' do
    it 'renders the service-unavailable error, with request_id preserved', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list(status: 503, body: error_envelope(code: 'service_unavailable', request_id: 'req-503').to_json)
      stub_manifests_list(url: other_manifests_url, status: 503,
        body: error_envelope(code: 'service_unavailable', request_id: 'req-503').to_json)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      # `request_id` rides the error extensions, not the message, so assert it there.
      expect(graphql_errors.first['extensions']['request_id']).to eq('req-503')
    end
  end

  context 'when the manifests read fails in transport' do
    it 'renders the service-unavailable error beside the loaded image', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_request(:get,
        manifests_url).with(query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
        .to_raise(Faraday::ConnectionFailed)
      stub_request(:get,
        other_manifests_url).with(query: { limit: '20', sort: 'created_at', order: 'desc', include_referrers: 'false' })
        .to_raise(Faraday::ConnectionFailed)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the manifests read times out' do
    it 'renders the service-unavailable error beside the loaded image' do
      stub_repository_read
      stub_image_read
      stub_request(:get,
        manifests_url).with(query: { limit: '20', sort: 'created_at', order: 'desc',
                                     include_referrers: 'false' }).to_timeout
      stub_request(:get,
        other_manifests_url).with(query: { limit: '20', sort: 'created_at', order: 'desc',
                                           include_referrers: 'false' }).to_timeout

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the image was deleted between the reads (404 on the list)' do
    it 'resolves the connection null while the image still renders', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stub_manifests_list(status: 404, body: error_envelope(code: 'not_found').to_json)
      stub_manifests_list(url: other_manifests_url, status: 404, body: error_envelope(code: 'not_found').to_json)

      post_query

      expect(manifests_response).to be_nil
      expect(image_nodes.first['id']).to eq(image_id)
      expect(graphql_errors).to be_nil
    end
  end

  # `FieldCallCount` allows the field for up to 20 images and raises on the 21st before its
  # resolve body runs. An alias selecting manifests a second time on the same image row counts
  # against that budget too, so a two-image list with the field aliased twice per row costs four
  # of the twenty and still resolves.
  context 'when one operation selects the connection twice under aliases on each image row' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 20) {
                nodes {
                  id
                  a: manifests(first: 1) { nodes { id } }
                  b: manifests(first: 1) { nodes { id } }
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

    it 'resolves each alias, one request per alias per row, within the budget', :aggregate_failures do
      stub_repository_read
      stub_image_read
      first_image = stub_manifests_list(query: { limit: '1', sort: 'created_at', order: 'desc',
                                                 include_referrers: 'false' })
      second_image = stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
        query: { limit: '1', sort: 'created_at', order: 'desc', include_referrers: 'false' })

      post_aliased_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil
      expect(first_image).to have_been_requested.twice
      expect(second_image).to have_been_requested.twice
    end
  end

  # The budget spans the whole operation, so aliasing the field past the parent page count
  # raises before the excess reads. A single image row with 21 aliases exceeds the limit of 20.
  context 'when one operation aliases the connection past the budget' do
    let(:aliases) { (1..21).map { |n| "a#{n}: manifests(first: 1) { nodes { id } }" }.join("\n") }
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 20) {
                nodes {
                  id
                  #{aliases}
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_over_budget_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the operation once the field is selected past twenty times' do
      stub_repository_read
      stub_image_read
      stub_manifests_list(query: { limit: '1', sort: 'created_at', order: 'desc', include_referrers: 'false' })
      stub_manifests_list(url: other_manifests_url, body: other_manifests_body.to_json,
        query: { limit: '1', sort: 'created_at', order: 'desc', include_referrers: 'false' })

      post_over_budget_query

      expect_graphql_errors_to_include(/can be requested only for 20/)
    end
  end

  # The budget counts every selection of the field regardless of its arguments, so 21 selections
  # that each vary the paging arguments still exceed the limit. This pins that the counter keys
  # on the field, not on `[field, arguments]`, which would let one row drive many reads.
  context 'when one operation aliases the connection past the budget with varied arguments' do
    let(:aliases) do
      forward = (1..10).map { |n| "f#{n}: manifests(first: #{n}) { nodes { id } }" }
      backward = (1..11).map { |n| %(b#{n}: manifests(last: #{n}, before: "cur#{n}") { nodes { id } }) }
      (forward + backward).join("\n")
    end

    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 20) {
                nodes {
                  id
                  #{aliases}
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_varied_over_budget_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the operation even though every selection carries different arguments' do
      stub_repository_read
      stub_image_read
      # The aliases resolving before the 21st raises each issue a distinct outbound query, so
      # match any manifests query rather than pinning one.
      stub_request(:get, manifests_url).with(query: hash_including({}))
        .to_return(status: 200, body: manifests_body.to_json, headers: json_headers)

      post_varied_over_budget_query

      expect_graphql_errors_to_include(/can be requested only for 20/)
    end
  end

  # `after`/`before` reach the outbound read as `cursor`. WebMock query matching is a subset
  # match, so these pin the exact outbound query and would catch a dropped cursor.
  context 'when paging the manifests connection forward' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 1) {
                nodes {
                  id
                  manifests(first: 10, after: "NEXT_CURSOR") { nodes { id } }
                }
              }
            }
          }
        }
      QUERY
    end

    let(:images_body) { [image_body] }

    subject(:post_forward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the after cursor and requested size to the outbound read' do
      stub_repository_read
      stub_image_read(body: [image_body].to_json, query: { limit: '1' })
      forward = stub_manifests_list(query: { limit: '10', sort: 'created_at', order: 'desc',
                                             include_referrers: 'false', cursor: 'NEXT_CURSOR' })

      post_forward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(forward).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when paging the manifests connection backward' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              images(first: 1) {
                nodes {
                  id
                  manifests(last: 5, before: "PREV_CURSOR") { nodes { id } }
                }
              }
            }
          }
        }
      QUERY
    end

    let(:images_body) { [image_body] }

    subject(:post_backward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the before cursor and requested size to the outbound read' do
      stub_repository_read
      stub_image_read(body: [image_body].to_json, query: { limit: '1' })
      backward = stub_manifests_list(query: { limit: '5', sort: 'created_at', order: 'desc',
                                              include_referrers: 'false', cursor: 'PREV_CURSOR' })

      post_backward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(backward).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  # The explicit-sort cases send no cursor and the cursor cases use the default sort, so this
  # pins that a selected non-default sort and a continuation cursor reach Artifact Registry in
  # the same outbound read.
  context 'when paging forward under an explicit non-default sort' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryManifestsSortedPage($id: OrganizationsOrganizationID!, $name: String!) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              images(first: 1) {
                nodes {
                  id
                  manifests(first: 5, sort: CREATED_AT_ASC, after: "NEXT_CURSOR") { nodes { id } }
                }
              }
            }
          }
        }
      QUERY
    end

    let(:images_body) { [image_body] }

    subject(:post_sorted_page_query) do
      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name })
    end

    it 'forwards the selected sort, order, and cursor together', :aggregate_failures do
      stub_repository_read
      stub_image_read(body: [image_body].to_json, query: { limit: '1' })
      sorted_page = stub_manifests_list(
        query: { limit: '5', sort: 'created_at', order: 'asc', include_referrers: 'false', cursor: 'NEXT_CURSOR' })

      post_sorted_page_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(sorted_page).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  # A full images page resolves the field exactly at the budget: 20 rows x one read each = 20
  # calls. This pins the inclusive boundary, so an off-by-one (rejecting at count == limit
  # rather than count > limit) would break a legitimate full page and fail here.
  context 'when a full page of twenty images each selects the connection once' do
    let(:twenty_image_ids) { (1..20).map { |n| "a0000000-0000-0000-0000-0000000000#{n.to_s.rjust(2, '0')}" } }
    let(:images_body) { twenty_image_ids.map { |id| { 'id' => id, 'name' => "image-#{id}" } } }

    it 'resolves the manifests on all twenty rows, one request per image', :aggregate_failures do
      stub_repository_read
      stub_image_read
      stubs = twenty_image_ids.map { |id| stub_manifests_list(url: "#{images_url}/#{id}/manifests") }

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil
      expect(image_nodes.pluck('id')).to eq(twenty_image_ids)
      expect(stubs).to all(have_been_requested.once)
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      image = stub_image_read
      list = stub_manifests_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)).to be_nil
      expect(detail).not_to have_been_requested
      expect(image).not_to have_been_requested
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
end
