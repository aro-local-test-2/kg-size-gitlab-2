# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization artifactRegistryRepositories', feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:repositories_url) { "#{base_url}/api/v1/#{slug}/repositories" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:page_size) { 20 }
  let(:current_user) { organization_user }

  let(:maven_repository) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'maven-releases',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'artifacts_count' => 12,
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'created_at' => '2026-07-01T10:00:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'created_by' => '101',
      'updated_by' => '202'
    }
  end

  let(:oci_repository) do
    {
      'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
      'name' => 'oci-mirror',
      'format' => 'oci',
      'kind' => 'remote',
      'visibility' => 'internal',
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'created_at' => '2026-07-03T09:00:00Z',
      'last_updated_at' => nil
    }
  end

  let(:page_body) { { 'repositories' => [maven_repository, oci_repository] } }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositories($id: OrganizationsOrganizationID!, $first: Int) {
        organization(id: $id) {
          id
          artifactRegistryRepositories(first: $first) {
            nodes {
              id
              name
              format
              kind
              visibility
              downloadsCount
              sizeBytes
              lastUpdatedAt
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
      variables: { id: organization.to_global_id.to_s, first: page_size })
  end

  context 'with the real per-user credential minted through the seam' do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }

    before do
      # This one example proves the end-to-end path the sibling suites stub past
      # (grep allow_next_instance_of(ArtifactRegistry::TokenExchange)): a real
      # minted Bearer header reaches AR. The others keep the fast stub.
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
      allow(ArtifactRegistry::TokenExchange).to receive(:new).and_call_original
    end

    it 'sends a minted user JWT AR would accept as the Bearer credential', :aggregate_failures do
      captured_authorization = nil
      list = stub_request(:get, repositories_url)
        .with(query: default_query) { |request| captured_authorization = request.headers['Authorization'] }
        .to_return(status: 200, body: page_body.to_json, headers: json_headers)

      post_query

      expect(list).to have_been_requested.once
      expect(graphql_errors).to be_nil

      bearer = captured_authorization.to_s.delete_prefix('Bearer ')
      payload, = JWT.decode(bearer, cloud_connector_key.public_key, true, algorithm: 'RS256')
      expect(payload['aud']).to eq(%w[gitlab-artifact-registry gitlab-iam-data-access])
      expect(payload['sub']).to eq(current_user.to_global_id.to_s)
      expect(payload['ver']).to eq(1)
    end

    context 'when the token cannot be minted' do
      before do
        allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_raise(RuntimeError, 'no key')
        allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'renders the service-unavailable error and reaches no AR request', :aggregate_failures do
        request = stub_repositories_list

        post_query

        expect(repositories_response).to be_nil
        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
        expect(request).not_to have_been_requested
      end
    end
  end

  shared_examples 'hiding the connection without reaching Artifact Registry' do
    it 'renders a null connection and no error, and builds no client', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repositories_response).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error' do
    it 'renders the service-unavailable error and no connection', :aggregate_failures do
      post_query

      expect(repositories_response).to be_nil
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when Artifact Registry returns a page of repositories' do
    let(:next_cursor) { 'eyJpZCI6MjB9' }
    let(:prev_cursor) { 'eyJpZCI6MTB9' }

    let(:link_header) do
      %(<#{repositories_url}?cursor=#{next_cursor}>; rel="next", ) +
        %(<#{repositories_url}?cursor=#{prev_cursor}>; rel="prev")
    end

    it 'issues one list request for the whole page, with no per-element follow-up', :aggregate_failures do
      list = stub_repositories_list
      detail = stub_request(:get, "#{repositories_url}/maven-releases")

      post_query

      expect(list).to have_been_requested.once
      expect(detail).not_to have_been_requested
    end

    it 'renders every list field of every repository' do
      stub_repositories_list

      post_query

      expect(repositories_response['nodes']).to eq(
        [
          {
            'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
            'name' => 'maven-releases',
            'format' => 'MAVEN',
            'kind' => 'HOSTED',
            'visibility' => 'PRIVATE',
            'downloadsCount' => '340',
            'sizeBytes' => '9876543210',
            'lastUpdatedAt' => '2026-07-02T11:30:00+00:00'
          },
          {
            'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
            'name' => 'oci-mirror',
            'format' => 'OCI',
            'kind' => 'REMOTE',
            'visibility' => 'INTERNAL',
            'downloadsCount' => '0',
            'sizeBytes' => '0',
            'lastUpdatedAt' => nil
          }
        ]
      )
    end

    it 'exposes the Link-header cursors through pageInfo' do
      stub_repositories_list(headers: json_headers.merge('Link' => link_header))

      post_query

      expect(repositories_response['pageInfo']).to eq(
        'hasNextPage' => true,
        'hasPreviousPage' => true,
        'startCursor' => prev_cursor,
        'endCursor' => next_cursor
      )
    end

    it 'renders the page without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repositories_list

      post_query

      expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when Artifact Registry returns no repositories for the user' do
    it 'renders an empty connection rather than a null one or an error', :aggregate_failures do
      stub_repositories_list(body: { 'repositories' => [] }.to_json)

      post_query

      expect(repositories_response['nodes']).to eq([])
      expect(repositories_response['pageInfo']).to eq(
        'hasNextPage' => false,
        'hasPreviousPage' => false,
        'startCursor' => nil,
        'endCursor' => nil
      )
      expect(graphql_errors).to be_nil
    end
  end

  [401, 403].each do |status|
    context "when Artifact Registry rejects the read with #{status}" do
      it 'renders a null connection and no error', :aggregate_failures do
        stub_repositories_list(status: status, body: error_envelope(code: 'forbidden').to_json)

        post_query

        expect(repositories_response).to be_nil
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when Artifact Registry answers with a server error' do
    before do
      stub_repositories_list(status: 503, body: error_envelope(code: 'service_unavailable').to_json)
    end

    it_behaves_like 'rendering the service-unavailable error'
  end

  context 'when the Artifact Registry connection fails' do
    before do
      stub_request(:get, repositories_url).with(query: default_query).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error'
  end

  context 'when the Artifact Registry request times out' do
    before do
      stub_request(:get, repositories_url).with(query: default_query).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error'
  end

  context 'when Artifact Registry cannot find the namespace' do
    let(:not_found_body) { error_envelope(code: 'not_found', message: 'namespace not found').to_json }

    # Artifact Registry answers 404 both for a namespace that does not exist and for one the
    # caller may not see, so this lands on the same existence-hiding outcome as a rejected read
    # rather than on an error the view would word as a service outage.
    it 'renders a null connection and no error', :aggregate_failures do
      stub_repositories_list(status: 404, body: not_found_body)

      post_query

      expect(repositories_response).to be_nil
      expect(graphql_errors).to be_nil
    end

    it 'logs the absence, so a slug that drifted from Artifact Registry stays visible' do
      stub_repositories_list(status: 404, body: not_found_body)

      expect(Gitlab::ErrorTracking).to receive(:log_exception)
        .with(an_instance_of(ArtifactRegistry::Client::ApiError), hash_including(slug: slug))

      post_query
    end
  end

  describe 'the user permissions blocks' do
    let(:namespace_actions) { ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS }
    let(:repository_actions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS }
    let(:namespace_permissions) { namespace_actions.index_with { |action| action == 'create_repository' } }
    let(:maven_permissions) { repository_actions.index_with { |action| action == 'update_repository' } }
    let(:oci_permissions) { repository_actions.index_with { |action| action == 'read_artifact' } }

    let(:page_body_with_permissions) do
      {
        'repositories' => [
          maven_repository.merge('permissions' => maven_permissions),
          oci_repository.merge('permissions' => oci_permissions)
        ],
        'permissions' => namespace_permissions
      }
    end

    let(:connection_fields) { "userPermissions { #{fields_for(namespace_actions)} }" }
    let(:row_fields) { "name userPermissions { #{fields_for(repository_actions)} }" }
    let(:query) { query_selecting("#{connection_fields} nodes { #{row_fields} }") }

    def fields_for(actions)
      actions.map { |action| action.camelize(:lower) }.join(' ')
    end

    def camelize_keys(permissions)
      permissions.transform_keys { |action| action.camelize(:lower) }
    end

    def query_selecting(selection)
      graphql_query_for(
        :organization,
        { id: organization.to_global_id.to_s },
        query_graphql_field(:artifact_registry_repositories, { first: page_size }, selection)
      )
    end

    def stub_repositories_list_with_permissions(body: page_body_with_permissions)
      stub_repositories_list(body: body.to_json, query: default_query.merge(include_permissions: 'true'))
    end

    subject(:post_query) { post_graphql(query, current_user: current_user) }

    it 'costs one read carrying include_permissions=true and resolves each block from its own object',
      :aggregate_failures do
      list = stub_repositories_list_with_permissions

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(list).to have_been_requested.once
      expect(a_request(:any, /include_permissions/)).to have_been_made.once
      expect(repositories_response['userPermissions']).to eq(camelize_keys(namespace_permissions))
      expect(repositories_response['nodes']).to eq(
        [
          { 'name' => 'maven-releases', 'userPermissions' => camelize_keys(maven_permissions) },
          { 'name' => 'oci-mirror', 'userPermissions' => camelize_keys(oci_permissions) }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    describe 'granular PAT authorization' do
      before do
        stub_repositories_list_with_permissions
      end

      # The block skips its own granular check; Organization authorizes `read_organization`
      # at the instance boundary for it. `read_artifact_registry` has no assignable
      # permission, so it cannot gate a granular token.
      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        :read_organization do
        let(:user) { current_user }
        let(:boundary_object) { :instance }
        let(:request) do
          post_graphql(query, current_user: user, token: { personal_access_token: pat })
        end

        let(:skipped_data_path) { %i[organization artifact_registry_repositories user_permissions] }
      end
    end

    context 'when only the connection block is selected' do
      let(:query) { query_selecting("#{connection_fields} nodes { name }") }

      it 'still asks for verdicts, because the envelope carries the namespace verdicts', :aggregate_failures do
        list = stub_repositories_list_with_permissions

        post_query

        expect(list).to have_been_requested.once
        expect(repositories_response['userPermissions']).to eq(camelize_keys(namespace_permissions))
      end
    end

    context 'when only the rows select the block under nodes' do
      let(:query) { query_selecting("nodes { #{row_fields} }") }

      it 'asks for verdicts and resolves each row from its own object', :aggregate_failures do
        list = stub_repositories_list_with_permissions

        post_query

        expect(list).to have_been_requested.once
        expect(repositories_response['nodes'].pluck('userPermissions'))
          .to eq([camelize_keys(maven_permissions), camelize_keys(oci_permissions)])
      end
    end

    context 'when only the rows select the block under edges' do
      let(:query) { query_selecting("edges { node { #{row_fields} } }") }

      it 'asks for verdicts and resolves each row from its own object', :aggregate_failures do
        list = stub_repositories_list_with_permissions

        post_query

        expect(list).to have_been_requested.once
        expect(repositories_response['edges'].map { |edge| edge.dig('node', 'userPermissions') })
          .to eq([camelize_keys(maven_permissions), camelize_keys(oci_permissions)])
      end
    end

    context 'when neither block is selected' do
      let(:query) { query_selecting('nodes { name }') }

      it 'sends no include_permissions', :aggregate_failures do
        list = stub_repositories_list

        post_query

        expect(list).to have_been_requested.once
        expect(a_request(:any, /include_permissions/)).not_to have_been_made
        expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
      end
    end

    context 'when the connection block is selected through a fragment spread' do
      let(:connection_fragment) do
        <<~FRAGMENT
          fragment ConnectionPermissions on ArtifactRegistryRepositoryConnection {
            #{connection_fields}
          }
        FRAGMENT
      end

      let(:query) { "#{connection_fragment}#{query_selecting('...ConnectionPermissions nodes { name }')}" }

      it 'asks for verdicts, so the lookahead traverses the fragment to find the selection',
        :aggregate_failures do
        list = stub_repositories_list_with_permissions

        post_query

        expect(list).to have_been_requested.once
        expect(a_request(:any, /include_permissions/)).to have_been_made.once
        expect(repositories_response['userPermissions']).to eq(camelize_keys(namespace_permissions))
      end
    end

    context 'when the envelope carries no permissions object' do
      let(:absent_report) do
        [instance_of(ArtifactRegistry::Permissions::VerdictReport::AbsentError), { read: :repositories, slug: slug }]
      end

      before do
        allow(Gitlab::ErrorTracking).to receive(:track_exception)

        stub_repositories_list_with_permissions(body: { 'repositories' => [maven_repository, oci_repository] })
      end

      it 'resolves both blocks all false, renders the rows, and adds no error', :aggregate_failures do
        post_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(repositories_response['userPermissions'].keys).to match_array(camelize_keys(namespace_permissions).keys)
        expect(repositories_response['userPermissions'].values).to all(be(false))
        expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
        expect(repositories_response['nodes'].pluck('userPermissions')).to all(satisfy do |block|
          block.keys == camelize_keys(maven_permissions).keys && block.values.all?(false)
        end)
        expect(graphql_errors).to be_nil
      end

      it 'reports the absence once for the connection block and every row block together' do
        post_query

        expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(*absent_report).once
      end
    end

    context 'when Artifact Registry answers a bare array' do
      it 'renders the service-unavailable error and reaches neither block', :aggregate_failures do
        stub_repositories_list_with_permissions(body: [maven_repository])
        expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:absent)
        expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:defect)

        post_query

        expect(repositories_response).to be_nil
        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      end
    end

    context 'when the artifact_registry_ui feature flag is disabled' do
      before do
        stub_feature_flags(artifact_registry_ui: false)
      end

      it 'keeps both blocks in the schema, resolves the connection null, and sends no include_permissions',
        :aggregate_failures do
        expect(ArtifactRegistry::Client).not_to receive(:new)

        post_query

        expect(repositories_response).to be_nil
        expect(graphql_errors).to be_nil
        expect(a_request(:any, /include_permissions/)).not_to have_been_made
      end
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it_behaves_like 'hiding the connection without reaching Artifact Registry'
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { non_member }

    it_behaves_like 'hiding the connection without reaching Artifact Registry'

    it 'still resolves the public organization the field hangs off' do
      post_query

      expect(graphql_data_at(:organization, :id)).to eq(organization.to_global_id.to_s)
    end
  end

  context 'when the instance never configured an Artifact Registry URL' do
    before do
      stub_config(artifact_registry: {})
    end

    it 'fails this field alone rather than the whole query', :aggregate_failures do
      post_query

      expect(repositories_response).to be_nil
      expect(graphql_data_at(:organization, :id)).to eq(organization.to_global_id.to_s)
    end
  end

  context 'when the query filters by format and kind' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryRepositories(
          $id: OrganizationsOrganizationID!
          $first: Int
          $format: ArtifactRegistryRepositoryFormat
          $kind: ArtifactRegistryRepositoryKind
          $sort: ArtifactRegistryRepositorySort
        ) {
          organization(id: $id) {
            artifactRegistryRepositories(first: $first, format: $format, kind: $kind, sort: $sort) {
              nodes {
                name
              }
            }
          }
        }
      QUERY
    end

    subject(:post_query) do
      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: page_size, format: 'MAVEN', kind: 'HOSTED' })
    end

    it 'sends the lowercase wire values the contract expects' do
      list = stub_request(:get, repositories_url)
        .with(query: default_query.merge(format: 'maven', kind: 'hosted'))
        .to_return(status: 200, body: page_body.to_json, headers: json_headers)

      post_query

      expect(list).to have_been_requested.once
    end

    it 'sends the sort alongside both filters' do
      list = stub_request(:get, repositories_url)
        .with(query: default_query.merge(format: 'maven', kind: 'hosted', sort: 'size_bytes', order: 'desc'))
        .to_return(status: 200, body: page_body.to_json, headers: json_headers)

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: page_size, format: 'MAVEN', kind: 'HOSTED',
                     sort: 'SIZE_BYTES_DESC' })

      expect(list).to have_been_requested.once
    end
  end

  context 'when the query filters by format and kind lists' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryRepositories(
          $id: OrganizationsOrganizationID!
          $first: Int
          $formats: [ArtifactRegistryRepositoryFormat!]
          $kinds: [ArtifactRegistryRepositoryKind!]
        ) {
          organization(id: $id) {
            artifactRegistryRepositories(first: $first, formats: $formats, kinds: $kinds) {
              nodes {
                name
              }
            }
          }
        }
      QUERY
    end

    let(:expected_query_string) do
      'format=docker&format=oci&kind=hosted&kind=remote&limit=20&order=desc&sort=last_updated_at'
    end

    around do |example|
      notation = WebMock::Config.instance.query_values_notation
      WebMock::Config.instance.query_values_notation = :flat_array
      example.run
    ensure
      WebMock::Config.instance.query_values_notation = notation
    end

    it 'sends each list value as its own repeated query parameter', :aggregate_failures do
      list = stub_request(:get, "#{repositories_url}?#{expected_query_string}")
        .to_return(status: 200, body: page_body.to_json, headers: json_headers)

      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: page_size, formats: %w[DOCKER OCI],
                     kinds: %w[HOSTED REMOTE] })

      expect(list).to have_been_requested.once
      expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the query declares a sort variable' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryRepositories(
          $id: OrganizationsOrganizationID!
          $first: Int
          $sort: ArtifactRegistryRepositorySort
          $after: String
        ) {
          organization(id: $id) {
            artifactRegistryRepositories(first: $first, sort: $sort, after: $after) {
              nodes {
                name
              }
              pageInfo {
                endCursor
              }
            }
          }
        }
      QUERY
    end

    subject(:post_query) { post_sorted_query }

    context 'when the sort variable names a column' do
      let(:sort_variable) { 'DOWNLOADS_COUNT_ASC' }
      let(:sorted_query) { default_query.merge(sort: 'downloads_count', order: 'asc') }

      it 'sends the column and direction the contract expects in place of the default pair' do
        list = stub_request(:get, repositories_url)
          .with(query: sorted_query)
          .to_return(status: 200, body: page_body.to_json, headers: json_headers)

        post_query

        expect(list).to have_been_requested.once
      end

      it 'carries the sort alongside the cursor the Link header handed back', :aggregate_failures do
        next_cursor = 'eyJpZCI6MjB9'
        first_page = stub_request(:get, repositories_url)
          .with(query: sorted_query)
          .to_return(
            status: 200,
            body: page_body.to_json,
            headers: json_headers.merge('Link' => %(<#{repositories_url}?cursor=#{next_cursor}>; rel="next"))
          )
        next_page = stub_request(:get, repositories_url)
          .with(query: sorted_query.merge(cursor: next_cursor))
          .to_return(status: 200, body: page_body.to_json, headers: json_headers)

        post_query

        expect(repositories_response['pageInfo']).to eq('endCursor' => next_cursor)

        post_sorted_query(after: next_cursor)

        expect(first_page).to have_been_requested.once
        expect(next_page).to have_been_requested.once
        expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the sort variable is an explicit null' do
      let(:sort_variable) { nil }

      it 'sends the default pair and renders the page', :aggregate_failures do
        list = stub_repositories_list

        post_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(list).to have_been_requested.once
        expect(repositories_response['nodes'].pluck('name')).to eq(%w[maven-releases oci-mirror])
        expect(graphql_errors).to be_nil
      end
    end

    def post_sorted_query(after: nil)
      post_graphql(query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: page_size, sort: sort_variable, after: after })
    end
  end

  def default_query
    { limit: page_size.to_s, sort: 'last_updated_at', order: 'desc' }
  end

  def stub_repositories_list(status: 200, body: page_body.to_json, headers: json_headers, query: default_query)
    stub_request(:get, repositories_url)
      .with(query: query)
      .to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repositories_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repositories)
  end
end
