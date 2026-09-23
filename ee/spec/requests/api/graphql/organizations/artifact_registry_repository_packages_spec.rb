# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository packages connection', feature_category: :artifact_registry do
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

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:packages_url) { "#{repository_url}/#{format}/packages" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'settings' => {}
    }
  end

  let(:maven_package) do
    {
      'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
      'group_id' => 'com.example.tools',
      'artifact_id' => 'payment-core',
      'last_downloaded_at' => '2026-07-03T09:15:00Z'
    }
  end

  let(:other_maven_package) do
    maven_package.merge('id' => 'f6a7b8c9-0000-0000-0000-000000000000', 'artifact_id' => 'payment-api')
  end

  let(:packages_body) { [maven_package, other_maven_package] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositoryPackages(
        $id: OrganizationsOrganizationID!
        $name: String!
        $first: Int
        $after: String
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            packages(first: $first, after: $after) {
              nodes {
                __typename
                ... on ArtifactRegistryMavenPackage {
                  id
                  groupId
                  artifactId
                  lastDownloadedAt
                }
                ... on ArtifactRegistryNpmPackage {
                  id
                  name
                  scope
                  versionsCount
                  lastDownloadedAt
                }
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
      expect(packages_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error beside the loaded repository' do
    it 'renders the service-unavailable error and keeps the repository rendered', :aggregate_failures do
      stub_repository_read

      post_query

      expect(packages_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the repository holds Maven packages' do
    let(:next_cursor) { 'eyJpZCI6MjB9' }
    let(:prev_cursor) { 'eyJpZCI6MTB9' }

    let(:link_header) do
      %(<#{packages_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{packages_url}?cursor=#{prev_cursor}>; rel="prev")
    end

    it 'renders every selected field of every package, discriminated by format' do
      stub_repository_read
      stub_packages_list

      post_query

      expect(packages_response['nodes']).to eq(
        [
          {
            '__typename' => 'ArtifactRegistryMavenPackage',
            'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
            'groupId' => 'com.example.tools',
            'artifactId' => 'payment-core',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryMavenPackage',
            'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
            'groupId' => 'com.example.tools',
            'artifactId' => 'payment-api',
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          }
        ]
      )
    end

    it 'issues one packages request under the repository format segment, with no per-row follow-up',
      :aggregate_failures do
      stub_repository_read
      list = stub_packages_list
      row = stub_request(:get, "#{packages_url}/e5f6a7b8-0000-0000-0000-000000000000")

      post_query

      expect(list).to have_been_requested.once
      expect(row).not_to have_been_requested
    end

    it 'exposes the Link-header cursors through pageInfo' do
      stub_repository_read
      stub_packages_list(headers: json_headers.merge('Link' => link_header))

      post_query

      expect(packages_response['pageInfo']).to eq(
        'hasNextPage' => true,
        'hasPreviousPage' => true,
        'startCursor' => prev_cursor,
        'endCursor' => next_cursor
      )
    end

    it 'carries the forward cursor the Link header handed back into the next read', :aggregate_failures do
      stub_repository_read
      first_page = stub_packages_list(headers: json_headers.merge('Link' => link_header))
      next_page = stub_packages_list(query: default_query.merge(cursor: next_cursor))

      post_query

      expect(packages_response['pageInfo']['endCursor']).to eq(next_cursor)

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name, first: page_size,
                     after: next_cursor })

      expect(first_page).to have_been_requested.once
      expect(next_page).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end

    it 'renders the page without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_packages_list

      post_query

      expect(packages_response['nodes'].pluck('artifactId')).to eq(%w[payment-core payment-api])
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds npm packages' do
    let(:format) { 'npm' }
    let(:repository_name) { 'npm-releases' }

    let(:scoped_npm_package) do
      {
        'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
        'name' => '@acme/ui-components',
        'scope' => '@acme',
        'versions_count' => 7,
        'tags_count' => 2,
        'last_downloaded_at' => '2026-07-03T09:15:00Z'
      }
    end

    let(:unscoped_npm_package) do
      scoped_npm_package.merge(
        'id' => 'd4e5f6a7-0000-0000-0000-000000000000',
        'name' => 'design-tokens',
        'scope' => nil,
        'versions_count' => 1,
        'last_downloaded_at' => nil
      )
    end

    let(:packages_body) { [scoped_npm_package, unscoped_npm_package] }

    it 'renders the name, the scope, the version count, and the pull timestamp, with a null scope ' \
      'for an unscoped package and a null timestamp for a package nothing pulled' do
      stub_repository_read
      stub_packages_list

      post_query

      expect(packages_response['nodes']).to eq(
        [
          {
            '__typename' => 'ArtifactRegistryNpmPackage',
            'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
            'name' => '@acme/ui-components',
            'scope' => '@acme',
            'versionsCount' => 7,
            'lastDownloadedAt' => '2026-07-03T09:15:00+00:00'
          },
          {
            '__typename' => 'ArtifactRegistryNpmPackage',
            'id' => 'd4e5f6a7-0000-0000-0000-000000000000',
            'name' => 'design-tokens',
            'scope' => nil,
            'versionsCount' => 1,
            'lastDownloadedAt' => nil
          }
        ]
      )
    end

    context 'when Artifact Registry supplies no version count, as it does for a remote repository' do
      let(:scoped_npm_package) { super().except('versions_count') }
      let(:unscoped_npm_package) { super().except('versions_count') }

      it 'renders the packages with a null count rather than nulling the nodes away',
        :aggregate_failures do
        stub_repository_read
        stub_packages_list

        post_query

        expect(packages_response['nodes'].pluck('versionsCount')).to match_array([nil, nil])
        expect(packages_response['nodes'].pluck('name')).to eq(%w[@acme/ui-components design-tokens])
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository holds no packages yet' do
    it 'renders an empty connection rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_packages_list(body: [].to_json)

      post_query

      expect(packages_response['nodes']).to eq([])
      expect(packages_response['pageInfo']).to eq(
        'hasNextPage' => false,
        'hasPreviousPage' => false,
        'startCursor' => nil,
        'endCursor' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds images rather than packages' do
    let(:format) { 'docker' }
    let(:repository_name) { 'container-images' }

    it 'resolves the connection null without asking Artifact Registry for packages', :aggregate_failures do
      stub_repository_read
      list = stub_packages_list

      post_query

      expect(packages_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(list).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository is virtual' do
    let(:repository_body) { super().merge('kind' => 'virtual') }

    where(:format, :repository_name) do
      [%w[maven maven-virtual], %w[npm npm-virtual]]
    end

    with_them do
      it 'resolves the connection null without asking Artifact Registry for packages', :aggregate_failures do
        stub_repository_read
        list = stub_packages_list

        post_query

        expect(packages_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(list).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository was deleted between the two reads (404 on the list)' do
    before do
      stub_packages_list(status: 404, body: error_envelope(code: 'not_found').to_json)
    end

    it_behaves_like 'resolving the connection null while the repository still renders'
  end

  [401, 403].each do |status|
    context "when Artifact Registry rejects the list read with #{status}" do
      before do
        stub_packages_list(status: status, body: error_envelope(code: 'forbidden').to_json)
      end

      it_behaves_like 'resolving the connection null while the repository still renders'
    end
  end

  context 'when Artifact Registry answers the list read with a server error' do
    before do
      stub_packages_list(status: 503, body: error_envelope(code: 'service_unavailable').to_json)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read fails in transport' do
    before do
      stub_request(:get, packages_url).with(query: default_query).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read times out' do
    before do
      stub_request(:get, packages_url).with(query: default_query).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      list = stub_packages_list

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

  # The third actor. A member and a signed-in non-member were covered; an anonymous caller has
  # its own path to the same outcome, and the no-existence-leak guarantee has to hold for all
  # three.
  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  # `first`/`after` are exercised throughout; `last`/`before` were reachable only through the
  # resolver unit path, which builds a synthetic field. This runs them through the real field,
  # so the connection extension, the outbound cursor, and the returned page info are all
  # covered end to end.
  context 'when paging backward' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              packages(last: 5, before: "#{prev_cursor}") {
                nodes { __typename }
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
      %(<#{packages_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{packages_url}?cursor=#{prev_cursor}>; rel="prev")
    end

    subject(:post_backward_query) { post_graphql(query, current_user: current_user) }

    it 'forwards the backward cursor and renders the page it returns', :aggregate_failures do
      stub_repository_read
      backward = stub_packages_list(
        query: { limit: '5', cursor: prev_cursor },
        headers: json_headers.merge('Link' => link_header)
      )

      post_backward_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(backward).to have_been_requested.once
      expect(graphql_errors).to be_nil

      expect(packages_response['nodes']).to eq(
        [
          { '__typename' => 'ArtifactRegistryMavenPackage' },
          { '__typename' => 'ArtifactRegistryMavenPackage' }
        ]
      )
      expect(packages_response['pageInfo']).to eq(
        'hasNextPage' => true,
        'hasPreviousPage' => true,
        'startCursor' => prev_cursor,
        'endCursor' => next_cursor
      )
    end
  end

  # The parent field is aliasable too, and each alias resolves its own repository read. The
  # per-field package budget does not bound it, so the read is cached for the request instead:
  # two aliases naming the same repository cost one detail request, and the second `packages`
  # selection is what the budget rejects.
  context 'when one operation aliases the parent field twice for the same repository' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            a: artifactRegistryRepository(name: "#{repository_name}") { name }
            b: artifactRegistryRepository(name: "#{repository_name}") { name }
          }
        }
      QUERY
    end

    subject(:post_aliased_parent_query) { post_graphql(query, current_user: current_user) }

    it 'reads the repository once and renders both aliases', :aggregate_failures do
      detail = stub_repository_read

      post_aliased_parent_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(detail).to have_been_requested.once
      expect(graphql_dig_at(graphql_data, :organization, :a, :name)).to eq(repository_name)
      expect(graphql_dig_at(graphql_data, :organization, :b, :name)).to eq(repository_name)
    end
  end

  # The negative half of the cache, which the resolver's comment relies on: `fetch` stores
  # whatever the block returns, so a nil stays cached and a second alias does not re-ask.
  context 'when the aliased repository does not exist' do
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            a: artifactRegistryRepository(name: "#{repository_name}") { name }
            b: artifactRegistryRepository(name: "#{repository_name}") { name }
          }
        }
      QUERY
    end

    subject(:post_missing_aliases) { post_graphql(query, current_user: current_user) }

    it 'reads once and resolves both aliases null', :aggregate_failures do
      missing = stub_repository_read(status: 404, body: error_envelope(code: 'not_found').to_json)

      post_missing_aliases

      expect(response).to have_gitlab_http_status(:ok)
      expect(missing).to have_been_requested.once
      expect(graphql_dig_at(graphql_data, :organization, :a)).to be_nil
      expect(graphql_dig_at(graphql_data, :organization, :b)).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a multiplex reads the same repository name under two organizations' do
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:other_organization_user) do
      create(:organization_user, organization: other_organization, user: organization_user).user
    end

    let_it_be(:other_namespace_mapping) do
      create(:artifact_registry_namespace_mapping, organization: other_organization)
    end

    let(:other_slug) { 'other-handle' }
    let(:other_namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{other_namespace_mapping.ar_namespace_id}" }
    let(:other_repository_url) { "#{base_url}/api/v1/#{other_slug}/repositories/#{repository_name}" }

    let(:multiplex_query) do
      <<~QUERY
        query OPERATION_NAME {
          organization(id: "ORGANIZATION_GID") {
            id
            artifactRegistryRepository(name: "#{repository_name}") { name description }
          }
        }
      QUERY
    end

    it 'reads each organization under its own handle', :aggregate_failures do
      namespace = stub_request(:get, other_namespace_url).to_return(
        status: 200,
        headers: json_headers,
        body: namespace_body.merge('id' => other_namespace_mapping.ar_namespace_id, 'slug' => other_slug).to_json
      )
      detail = stub_repository_read
      other_detail = stub_request(:get, other_repository_url)
        .to_return(status: 200, body: repository_body.to_json, headers: json_headers)

      post_multiplex(
        [
          { query: multiplex_query.sub('OPERATION_NAME', 'first_org')
                                  .sub('ORGANIZATION_GID', organization.to_global_id.to_s) },
          { query: multiplex_query.sub('OPERATION_NAME', 'second_org')
                                  .sub('ORGANIZATION_GID', other_organization.to_global_id.to_s) }
        ],
        current_user: current_user
      )

      expect(response).to have_gitlab_http_status(:ok)
      expect(namespace).to have_been_requested
      expect(detail).to have_been_requested.once
      expect(other_detail).to have_been_requested.once
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
              packages(first: 5) { nodes { __typename } }
            }
          }
        }
      QUERY
    end

    it 'budgets packages per operation and reads the repository once', :aggregate_failures do
      detail = stub_repository_read
      list = stub_packages_list(query: { limit: '5' })

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

  # Over the wire, through the real field, so this is what proves the field's `max_page_size: 20`
  # rather than the schema default of 100. `ArtifactRegistry::PaginatesLists` reads the cap off
  # the field, and the resolver unit spec cannot see it: its synthetic field carries no cap.
  context 'when the caller requests more rows than the field allows' do
    let(:page_size) { GitlabSchema.default_max_page_size }

    it 'caps the outbound Artifact Registry limit at 20' do
      stub_repository_read
      capped = stub_packages_list(query: { limit: '20' })

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
              a: packages(first: 5) { nodes { __typename } }
              b: packages(first: 5) { nodes { __typename } }
            }
          }
        }
      QUERY
    end

    subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the second selection and issues one list request, not two', :aggregate_failures do
      stub_repository_read
      list = stub_packages_list(query: { limit: '5' })

      post_aliased_query

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(list).to have_been_requested.once
    end
  end

  def default_query
    { limit: page_size.to_s }
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_packages_list(status: 200, body: packages_body.to_json, headers: json_headers, query: default_query)
    stub_request(:get, packages_url)
      .with(query: query)
      .to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def packages_response
    repository_response&.dig('packages')
  end
end
