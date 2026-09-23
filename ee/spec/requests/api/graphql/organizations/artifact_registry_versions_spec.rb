# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry versions connection', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }
  let(:packages_page_size) { 20 }
  let(:versions_first) { 20 }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:package_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:packages_url) { "#{repository_url}/#{format}/packages" }
  let(:versions_url) { "#{packages_url}/#{package_id}/versions" }

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

  let(:package_row) { { 'id' => package_id, 'group_id' => 'com.example.tools', 'artifact_id' => 'payment-core' } }
  let(:packages_body) { [package_row] }

  let(:version_row) do
    {
      'id' => 'v1000-0000-0000-0000-000000000000',
      'version' => '1.10.0',
      'created_at' => '2026-07-03T09:15:00Z',
      'created_by' => '101',
      'project_id' => '202',
      'git_commit_sha' => 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      'size' => 4_294_967_296,
      'dist_tags' => []
    }
  end

  let(:other_version_row) do
    version_row.merge('id' => 'v0900-0000-0000-0000-000000000000', 'version' => '1.9.0', 'dist_tags' => [])
  end

  let(:versions_body) { [version_row, other_version_row] }

  let(:package_fragment) { 'ArtifactRegistryMavenPackage' }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryVersions($id: OrganizationsOrganizationID!, $name: String!, $pkgFirst: Int, $verFirst: Int) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            packages(first: $pkgFirst) {
              nodes {
                __typename
                ... on #{package_fragment} {
                  id
                  versions(first: $verFirst) {
                    nodes { id version createdAt sizeBytes distTags }
                    pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
                  }
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
      variables: {
        id: organization.to_global_id.to_s, name: repository_name,
        pkgFirst: packages_page_size, verFirst: versions_first
      })
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_packages_list(status: 200, body: packages_body.to_json, query: { limit: '20' })
    stub_request(:get, packages_url).with(query: query).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_versions_list(
    status: 200, body: versions_body.to_json, headers: json_headers,
    query: { limit: '20', sort: 'created_at', order: 'desc' })
    stub_request(:get, versions_url).with(query: query).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def package_node
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository, :packages, :nodes).first
  end

  def versions_response
    package_node&.dig('versions')
  end

  shared_examples 'listing versions for the format' do
    it 'renders the version rows the endpoint returned, with createdAt, size, and distTags',
      :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list

      post_query

      expect(versions_response['nodes']).to eq(
        [
          { 'id' => 'v1000-0000-0000-0000-000000000000', 'version' => '1.10.0',
            'createdAt' => '2026-07-03T09:15:00+00:00', 'sizeBytes' => '4294967296',
            'distTags' => version_row['dist_tags'] },
          { 'id' => 'v0900-0000-0000-0000-000000000000', 'version' => '1.9.0',
            'createdAt' => '2026-07-03T09:15:00+00:00', 'sizeBytes' => '4294967296', 'distTags' => [] }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    context 'when a row omits dist_tags' do
      let(:version_row) { super().except('dist_tags') }

      it 'resolves an empty list without an extra Artifact Registry request', :aggregate_failures do
        stub_repository_read
        stub_packages_list
        versions = stub_versions_list

        post_query

        expect(versions_response['nodes'].first['distTags']).to eq([])
        expect(versions).to have_been_requested.once
        expect(a_request(:get, %r{#{Regexp.escape(packages_url)}/.*/tags})).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository holds Maven packages' do
    it_behaves_like 'listing versions for the format'

    it 'resolves distTags empty on every row' do
      stub_repository_read
      stub_packages_list
      stub_versions_list

      post_query

      expect(versions_response['nodes'].pluck('distTags')).to all(eq([]))
    end

    it 'issues one packages read then one versions read for the single row, with no follow-up',
      :aggregate_failures do
      stub_repository_read
      list = stub_packages_list
      versions = stub_versions_list

      post_query

      expect(list).to have_been_requested.once
      expect(versions).to have_been_requested.once
    end

    it 'exposes the Link-header cursors through pageInfo' do
      next_cursor = 'eyJpZCI6MjB9'
      prev_cursor = 'eyJpZCI6MTB9'
      link = %(<#{versions_url}?cursor=#{next_cursor}>; rel="next", <#{versions_url}?cursor=#{prev_cursor}>; rel="prev")
      stub_repository_read
      stub_packages_list
      stub_versions_list(headers: json_headers.merge('Link' => link))

      post_query

      expect(versions_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
    end

    it 'never leaks the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list

      post_query

      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end

    # Criterion 5's publication-date-descending default: with no `sort` argument the connection
    # falls back to the enum default, so the outbound read carries `sort=created_at&order=desc`.
    # Asserted as `created_at`/`desc` literally, not via the helper default, so the default is
    # pinned even if that helper changes.
    it 'defaults the outbound sort to publication date descending on the first page', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list

      post_query

      expect(graphql_errors).to be_nil
      expect(
        a_request(:get, versions_url).with(query: hash_including('sort' => 'created_at', 'order' => 'desc'))
      ).to have_been_requested
      expect(
        a_request(:get, versions_url).with(query: hash_including('sort' => 'version'))
      ).not_to have_been_requested
    end

    # One resolution per row of the parent page stays within the `FieldCallCount` budget of 20,
    # so a page of two packages resolves versions on both rather than raising on the second.
    context 'when the page holds more than one package' do
      let(:other_package_id) { 'a7b8c9d0-0000-0000-0000-000000000000' }
      let(:other_package_row) do
        { 'id' => other_package_id, 'group_id' => 'com.example.tools', 'artifact_id' => 'billing' }
      end

      let(:packages_body) { [package_row, other_package_row] }

      it 'resolves the versions connection on every package row without a budget error', :aggregate_failures do
        stub_repository_read
        stub_packages_list
        first_row = stub_versions_list
        second_row = stub_request(:get, "#{packages_url}/#{other_package_id}/versions")
          .with(query: { limit: '20', sort: 'created_at', order: 'desc' })
          .to_return(status: 200, body: [].to_json, headers: json_headers)

        post_query

        expect(graphql_errors).to be_nil
        expect(first_row).to have_been_requested.once
        expect(second_row).to have_been_requested.once
      end
    end

    # `FieldCallCount` keys on the Field instance, so aliasing `versions` on one package row past
    # 20 exhausts the budget: the 21st resolution raises before its body runs, and the whole
    # operation issues at most 20 versions reads rather than one per alias.
    context 'when one operation aliases the versions connection past the budget on one row' do
      let(:query) do
        aliases = (1..21).map { |i| "v#{i}: versions(first: 1) { nodes { id } }" }.join("\n")

        <<~QUERY
          query {
            organization(id: "#{organization.to_global_id}") {
              id
              artifactRegistryRepository(name: "#{repository_name}") {
                packages(first: 1) {
                  nodes {
                    __typename
                    ... on #{package_fragment} {
                      id
                      #{aliases}
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

      it 'rejects the 21st selection and issues at most 20 versions reads', :aggregate_failures do
        stub_repository_read
        stub_packages_list(query: { limit: '1' })
        versions = stub_versions_list(query: { limit: '1', sort: 'created_at', order: 'desc' })

        post_aliased_query

        expect_graphql_errors_to_include(/can be requested only for 20/)
        expect(versions).to have_been_requested.times(20)
      end
    end
  end

  context 'when the repository holds npm packages' do
    let(:format) { 'npm' }
    let(:repository_name) { 'npm-releases' }
    let(:package_row) { { 'id' => package_id, 'name' => '@acme/ui-components', 'scope' => '@acme' } }
    let(:package_fragment) { 'ArtifactRegistryNpmPackage' }
    let(:version_row) { super().merge('dist_tags' => %w[latest next]) }

    it_behaves_like 'listing versions for the format'

    it 'renders the dist-tag names per row from the list response alone', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      versions = stub_versions_list

      post_query

      expect(versions_response['nodes'].pluck('distTags')).to eq([%w[latest next], []])
      expect(versions).to have_been_requested.once
      expect(a_request(:get, %r{#{Regexp.escape(packages_url)}/.*/tags})).not_to have_been_requested
    end
  end

  context 'with an explicit sort argument' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionsSorted($id: OrganizationsOrganizationID!, $name: String!, $sort: ArtifactRegistryVersionSort) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              packages(first: 20) {
                nodes {
                  __typename
                  ... on #{package_fragment} {
                    versions(first: 20, sort: $sort) { nodes { id } }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    # Every enum value reaches the client as its `sort`/`order` pair, not just the default and
    # one other; the exact-match stub fails the example if the wrong pair (or none) goes out.
    where(:sort_value, :outbound_sort, :outbound_order) do
      'CREATED_AT_ASC'  | 'created_at' | 'asc'
      'CREATED_AT_DESC' | 'created_at' | 'desc'
      'VERSION_ASC'     | 'version'    | 'asc'
      'VERSION_DESC'    | 'version'    | 'desc'
    end

    with_them do
      it 'forwards the enum value as the client sort column and order', :aggregate_failures do
        stub_repository_read
        stub_packages_list
        sorted = stub_versions_list(query: { limit: '20', sort: outbound_sort, order: outbound_order })

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
        stub_packages_list
        default_sorted = stub_versions_list(query: { limit: '20', sort: 'created_at', order: 'desc' })

        post_graphql(query, current_user: current_user,
          variables: { id: organization.to_global_id.to_s, name: repository_name, sort: nil })

        expect(default_sorted).to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the parent packages connection caps the page at 20' do
    let(:packages_page_size) { GitlabSchema.default_max_page_size }

    it 'caps the outbound packages limit at 20, bounding the versions fan-out' do
      stub_repository_read
      capped = stub_packages_list(query: { limit: '20' }, body: [].to_json)

      post_query

      expect(capped).to have_been_requested
    end
  end

  # Over the wire, through the real field, so this proves the field's `max_page_size: 20` rather
  # than the schema default of 100. `ArtifactRegistry::PaginatesLists` reads the cap off the
  # field, and the resolver unit spec cannot see it: its synthetic field carries no cap.
  context 'when the caller requests more version rows than the field allows' do
    let(:versions_first) { GitlabSchema.default_max_page_size + 1 }

    it 'caps the outbound versions limit at 20' do
      stub_repository_read
      stub_packages_list
      capped = stub_versions_list(query: { limit: '20', sort: 'created_at', order: 'desc' })

      post_query

      expect(capped).to have_been_requested
    end
  end

  context 'when Artifact Registry answers the versions read with a server error' do
    it 'renders the service-unavailable error, with request_id preserved', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list(status: 503, body: error_envelope(code: 'service_unavailable', request_id: 'req-503').to_json)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      # `request_id` rides the error extensions, not the message, so assert it there.
      expect(graphql_errors.first['extensions']['request_id']).to eq('req-503')
    end
  end

  context 'when the repository holds no versions yet' do
    it 'renders an empty connection rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list(body: [].to_json)

      post_query

      expect(versions_response['nodes']).to eq([])
      expect(versions_response['pageInfo']).to eq(
        'hasNextPage' => false, 'hasPreviousPage' => false,
        'startCursor' => nil, 'endCursor' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  # A 404, 401, or 403 on the versions read resolves the connection null while the package it
  # hangs off still renders -- a package deleted or hidden between the two reads keeps its row.
  shared_examples 'resolving the versions connection null while the package still renders' do |status:, code:|
    it 'renders a null connection, no error, and the package around it', :aggregate_failures do
      stub_repository_read
      stub_packages_list
      stub_versions_list(status: status, body: error_envelope(code: code).to_json)

      post_query

      # `fetch`, not `&.dig`: the `versions` key must be present and its value null, so a query
      # that never selected `versions` could not pass this by omission.
      expect(package_node.fetch('versions')).to be_nil
      expect(package_node['id']).to eq(package_id)
      expect(graphql_errors).to be_nil
    end
  end

  # A 429, a 5xx, or any other 4xx on the versions read surfaces a top-level error rather than a
  # silent null, so a transient outage is distinguishable from an empty or missing collection.
  shared_examples 'rendering the service-unavailable error beside the loaded package' do
    it 'renders the service-unavailable error and keeps the package rendered', :aggregate_failures do
      stub_repository_read
      stub_packages_list

      post_query

      expect(package_node['id']).to eq(package_id)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the package was deleted between the reads (404 on the versions read)' do
    it_behaves_like 'resolving the versions connection null while the package still renders',
      status: 404, code: 'not_found'
  end

  [401, 403].each do |rejection_status|
    context "when Artifact Registry rejects the versions read with #{rejection_status}" do
      it_behaves_like 'resolving the versions connection null while the package still renders',
        status: rejection_status, code: 'forbidden'
    end
  end

  context 'when the versions read fails in transport' do
    before do
      stub_request(:get, versions_url)
        .with(query: { limit: '20', sort: 'created_at', order: 'desc' }).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded package'
  end

  context 'when the versions read times out' do
    before do
      stub_request(:get, versions_url)
        .with(query: { limit: '20', sort: 'created_at', order: 'desc' }).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded package'
  end

  # Forward paging is the primary direction for the keyed-pagination UI, so this pins the
  # `after` connection argument to the outbound `cursor` and the returned page info end to end.
  context 'when paging versions forward' do
    let(:next_cursor) { 'eyJpZCI6MjB9' }

    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              packages(first: 1) {
                nodes {
                  __typename
                  ... on #{package_fragment} {
                    id
                    versions(first: 5, after: "#{next_cursor}") {
                      nodes { id }
                      pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
                    }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_forward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the forward cursor and renders the page info it returns', :aggregate_failures do
      prev_cursor = 'eyJpZCI6MTB9'
      link = %(<#{versions_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{versions_url}?cursor=#{prev_cursor}>; rel="prev")
      stub_repository_read
      stub_packages_list(query: { limit: '1' })
      forward = stub_versions_list(
        query: { limit: '5', cursor: next_cursor, sort: 'created_at', order: 'desc' },
        headers: json_headers.merge('Link' => link)
      )

      post_forward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(forward).to have_been_requested.once
      expect(versions_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
      expect(graphql_errors).to be_nil
    end
  end

  # `first`/`after` are covered by the forward case above; `last`/`before` reach the field only
  # here, so the connection extension, the outbound cursor, and the page info are covered too.
  context 'when paging versions backward' do
    let(:prev_cursor) { 'eyJpZCI6MTB9' }

    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              packages(first: 1) {
                nodes {
                  __typename
                  ... on #{package_fragment} {
                    id
                    versions(last: 5, before: "#{prev_cursor}") {
                      nodes { id }
                      pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
                    }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_backward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the backward cursor and renders the page info it returns', :aggregate_failures do
      next_cursor = 'eyJpZCI6MjB9'
      link = %(<#{versions_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{versions_url}?cursor=#{prev_cursor}>; rel="prev")
      stub_repository_read
      stub_packages_list(query: { limit: '1' })
      backward = stub_versions_list(
        query: { limit: '5', cursor: prev_cursor, sort: 'created_at', order: 'desc' },
        headers: json_headers.merge('Link' => link)
      )

      post_backward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(backward).to have_been_requested.once
      expect(versions_response['pageInfo']).to eq(
        'hasNextPage' => true, 'hasPreviousPage' => true,
        'startCursor' => prev_cursor, 'endCursor' => next_cursor
      )
      expect(graphql_errors).to be_nil
    end
  end

  # The explicit-sort cases send no cursor and the cursor cases use the default sort, so this
  # pins that a selected non-default sort and a continuation cursor reach Artifact Registry in
  # the same outbound read.
  context 'when paging forward under an explicit non-default sort' do
    let(:next_cursor) { 'eyJpZCI6MjB9' }

    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionsSortedPage($id: OrganizationsOrganizationID!, $name: String!) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              packages(first: 1) {
                nodes {
                  __typename
                  ... on #{package_fragment} {
                    versions(first: 5, sort: VERSION_ASC, after: "#{next_cursor}") { nodes { id } }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_sorted_page_query) do
      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name })
    end

    it 'forwards the selected sort, order, and cursor together', :aggregate_failures do
      stub_repository_read
      stub_packages_list(query: { limit: '1' })
      sorted_page = stub_versions_list(
        query: { limit: '5', cursor: next_cursor, sort: 'version', order: 'asc' }
      )

      post_sorted_page_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(sorted_page).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      list = stub_packages_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)).to be_nil
      expect(detail).not_to have_been_requested
      expect(list).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the caller is not a member of the organization' do
    let(:current_user) { create(:user) }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end
end
