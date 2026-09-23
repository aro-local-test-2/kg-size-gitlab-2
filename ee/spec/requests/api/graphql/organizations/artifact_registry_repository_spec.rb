# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reading a single Artifact Registry repository', feature_category: :artifact_registry do
  include GraphqlHelpers

  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:repository_name) { 'my-repo' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:upstream_url) { 'https://upstream.example.test/root' }
  let(:checked_at) { '2026-07-02T12:00:00Z' }
  let(:resolved_checked_at) { '2026-07-02T12:00:00+00:00' }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'settings' => {}
    }
  end

  let(:settings_fields) do
    'url cacheValidityHours metadataCacheValidityHours snapshotMetadataAlwaysRevalidate ' \
      'hasCredentials lastHealthStatus lastHealthCheckedAt'
  end

  let(:query) do
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      query_graphql_field(
        :artifact_registry_repository,
        { name: repository_name },
        'id name format kind visibility description downloadsCount sizeBytes lastUpdatedAt ' \
          "settings { #{settings_fields} }"
      )
    )
  end

  let(:repository_data) { graphql_data.dig('organization', 'artifactRegistryRepository') }
  let(:settings_data) { repository_data['settings'] }

  let(:allowed_actions) { %w[read_repository read_artifact] }

  def repository_actions
    ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS
  end

  def permission_fields
    repository_actions.map { |action| action.camelize(:lower) }.join(' ')
  end

  def permissions_body
    repository_actions.index_with { |action| allowed_actions.include?(action) }
  end

  def permissions_data
    permissions_body.transform_keys { |action| action.camelize(:lower) }
  end

  def include_permissions_query
    { include_permissions: 'true' }
  end

  def query_with_permissions
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      query_graphql_field(
        :artifact_registry_repository,
        { name: repository_name },
        "name userPermissions { #{permission_fields} }"
      )
    )
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end
  end

  context 'when the artifact_registry_ui flag is on' do
    it 'reads the repository over HTTP and returns its fields', :aggregate_failures do
      request = stub_request(:get, repository_url)
        .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(request).to have_been_requested
      expect(repository_data).to include(
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => repository_name,
        'format' => 'MAVEN',
        'kind' => 'HOSTED',
        'visibility' => 'PRIVATE',
        'description' => 'A hosted Maven repository',
        'settings' => nil,
        'downloadsCount' => '340',
        'sizeBytes' => '9876543210'
      )
    end

    describe 'the settings of a remote repository' do
      let(:remote_settings) do
        {
          'url' => upstream_url,
          'cache_validity_hours' => 24,
          'has_credentials' => true,
          'last_health_status' => 'healthy',
          'last_health_checked_at' => checked_at
        }
      end

      let(:resolved_remote_settings) do
        {
          'url' => upstream_url,
          'cacheValidityHours' => 24,
          'hasCredentials' => true,
          'lastHealthStatus' => 'HEALTHY',
          'lastHealthCheckedAt' => resolved_checked_at
        }
      end

      let(:format_settings) do
        {
          'metadata_cache_validity_hours' => metadata_cache_validity_hours,
          'snapshot_metadata_always_revalidate' => snapshot_metadata_always_revalidate
        }.compact
      end

      let(:repository_body) do
        super().merge(
          'format' => repository_format,
          'kind' => 'remote',
          'settings' => remote_settings.merge(format_settings)
        )
      end

      before do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)
      end

      where(:repository_format, :metadata_cache_validity_hours, :snapshot_metadata_always_revalidate) do
        'maven'  | 6   | true
        'npm'    | 12  | nil
        'docker' | nil | nil
        'oci'    | nil | nil
      end

      with_them do
        it 'returns every field the format serializes, and null for the ones it omits', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(settings_data).to eq(
            resolved_remote_settings.merge(
              'metadataCacheValidityHours' => metadata_cache_validity_hours,
              'snapshotMetadataAlwaysRevalidate' => snapshot_metadata_always_revalidate
            )
          )
          expect(graphql_errors).to be_nil
        end
      end
    end

    context 'when the repository is virtual' do
      let(:repository_body) { super().except('settings').merge('kind' => 'virtual') }

      it 'resolves settings to null, because a virtual repository defines none', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to include('kind' => 'VIRTUAL', 'settings' => nil)
        expect(graphql_errors).to be_nil
      end
    end

    context 'when Artifact Registry returns settings that are not an object' do
      let(:repository_body) { super().merge('kind' => 'remote', 'settings' => 'not-an-object') }

      it 'resolves settings to null rather than erroring', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to include('kind' => 'REMOTE', 'settings' => nil)
        expect(graphql_errors).to be_nil
      end
    end

    context 'when Artifact Registry reports a health status the enum does not define' do
      let(:repository_body) do
        super().merge(
          'kind' => 'remote',
          'settings' => {
            'url' => upstream_url,
            'cache_validity_hours' => 24,
            'metadata_cache_validity_hours' => 6,
            'snapshot_metadata_always_revalidate' => false,
            'has_credentials' => false,
            'last_health_status' => 'degraded',
            'last_health_checked_at' => checked_at
          }
        )
      end

      it 'reads the status as UNKNOWN and still returns the other fields', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(settings_data).to eq(
          'url' => upstream_url,
          'cacheValidityHours' => 24,
          'metadataCacheValidityHours' => 6,
          'snapshotMetadataAlwaysRevalidate' => false,
          'hasCredentials' => false,
          'lastHealthStatus' => 'UNKNOWN',
          'lastHealthCheckedAt' => resolved_checked_at
        )
        expect(graphql_errors).to be_nil
      end
    end

    context 'when a remote repository stores upstream credentials' do
      let(:credential_values) { %w[ar-upstream-user ar-upstream-secret ar-upstream-auth-token] }

      let(:repository_body) do
        super().merge(
          'kind' => 'remote',
          'settings' => {
            'url' => upstream_url,
            'cache_validity_hours' => 24,
            'metadata_cache_validity_hours' => 6,
            'snapshot_metadata_always_revalidate' => true,
            'has_credentials' => true,
            'last_health_status' => 'healthy',
            'last_health_checked_at' => checked_at,
            'username' => credential_values[0],
            'password' => credential_values[1],
            'auth_token' => credential_values[2]
          }
        )
      end

      it 'reports hasCredentials and puts no credential value in the response body', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(settings_data).to include('hasCredentials' => true)
        credential_values.each { |credential_value| expect(response.body).not_to include(credential_value) }
      end
    end

    describe 'selecting a credential field under settings' do
      where(credential_field: %w[username password authToken credentials])

      with_them do
        let(:settings_fields) { credential_field }

        it 'fails schema validation and makes no HTTP call', :aggregate_failures do
          request = stub_request(:get, repository_url)

          post_graphql(query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect_graphql_errors_to_include(
            "Field '#{credential_field}' doesn't exist on type 'ArtifactRegistryRemoteSettings'"
          )
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the repository is not found (AR returns 404)' do
      it 'resolves to null rather than erroring', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 404, headers: json_headers, body: { code: 'not_found' }.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to be_nil
        expect(graphql_errors).to be_nil
      end
    end

    context 'when AR is unavailable (5xx)' do
      it 'surfaces a top-level error' do
        stub_request(:get, repository_url)
          .to_return(status: 503, headers: json_headers, body: {}.to_json)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_present
      end
    end

    context 'when AR denies the read (401)' do
      it 'resolves to null rather than erroring', :aggregate_failures do
        # Artifact Registry hides existence: a denial reads as not-found, so the field
        # resolves null with no top-level error. The mutation slices rely on this.
        stub_request(:get, repository_url)
          .to_return(status: 401, headers: json_headers, body: {}.to_json)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to be_nil
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the current user cannot read the organization' do
      it 'resolves to null and makes no HTTP call', :aggregate_failures do
        # The field is authorized read_artifact_registry against the organization, so a
        # user with no access to it never reaches Artifact Registry.
        request = stub_request(:get, repository_url)

        post_graphql(query, current_user: non_member)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to be_nil
        expect(request).not_to have_been_requested
      end
    end

    describe 'the user permissions block' do
      def body_with_permissions
        repository_body.merge('permissions' => permissions_body)
      end

      it 'sends include_permissions=true on the repository read alone and resolves one Boolean per action',
        :aggregate_failures do
        request = stub_request(:get, repository_url).with(query: include_permissions_query)
          .to_return(status: 200, headers: json_headers, body: body_with_permissions.to_json)

        post_graphql(query_with_permissions, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(request).to have_been_requested.once
        expect(a_request(:any, /include_permissions/)).to have_been_made.once
        expect(repository_data).to eq('name' => repository_name, 'userPermissions' => permissions_data)
        expect(graphql_errors).to be_nil
      end

      it 'sends no include_permissions when the block is not selected', :aggregate_failures do
        request = stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

        post_graphql(query, current_user: current_user)

        expect(request).to have_been_requested.once
        expect(a_request(:any, /include_permissions/)).not_to have_been_made
      end

      describe 'granular PAT authorization' do
        before do
          stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 200, headers: json_headers, body: body_with_permissions.to_json)
        end

        # The block skips its own granular check; Organization authorizes `read_organization`
        # at the instance boundary for it. `read_artifact_registry` has no assignable
        # permission, so it cannot gate a granular token.
        it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
          :read_organization do
          let(:user) { current_user }
          let(:boundary_object) { :instance }
          let(:request) do
            post_graphql(query_with_permissions, current_user: user, token: { personal_access_token: pat })
          end

          let(:skipped_data_path) { %i[organization artifact_registry_repository user_permissions] }
        end
      end

      context 'when the response carries no permissions object' do
        let(:absent_report) do
          [instance_of(ArtifactRegistry::Permissions::VerdictReport::AbsentError), { read: :repository, slug: slug }]
        end

        before do
          allow(Gitlab::ErrorTracking).to receive(:track_exception)

          stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 200, headers: json_headers, body: repository_body.to_json)
        end

        it 'resolves every permission false, keeps the parent populated, and adds no error',
          :aggregate_failures do
          post_graphql(query_with_permissions, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(repository_data['name']).to eq(repository_name)
          expect(repository_data['userPermissions'].values).to all(be(false))
          expect(repository_data['userPermissions'].keys).to match_array(permissions_data.keys)
          expect(graphql_errors).to be_nil
        end

        it 'reports the absence once for the read and the slug, not once per field' do
          post_graphql(query_with_permissions, current_user: current_user)

          expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(*absent_report).once
        end
      end

      describe 'a verdict never derived from a Rails ability' do
        where(:allowed_actions) do
          [
            [[]],
            [ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS]
          ]
        end

        with_them do
          it "resolves what Artifact Registry answered for a user who holds the Rails read ability",
            :aggregate_failures do
            stub_request(:get, repository_url).with(query: include_permissions_query)
              .to_return(status: 200, headers: json_headers, body: body_with_permissions.to_json)

            expect(Ability.allowed?(current_user, :read_artifact_registry, organization)).to be(true)

            post_graphql(query_with_permissions, current_user: current_user)

            expect(repository_data['userPermissions']).to eq(permissions_data)
            expect(Ability.allowed?(current_user, :read_artifact_registry, organization)).to be(true)
          end
        end
      end

      context 'when Artifact Registry is unavailable (5xx) with the block selected' do
        it 'surfaces a top-level error and reaches no block', :aggregate_failures do
          stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 503, headers: json_headers, body: {}.to_json)

          post_graphql(query_with_permissions, current_user: current_user)

          expect(graphql_errors).to be_present
          expect(repository_data).to be_nil
        end
      end

      context 'when the repository is not found (404) with the block selected' do
        it 'resolves the parent null with no block and no error', :aggregate_failures do
          stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 404, headers: json_headers, body: { code: 'not_found' }.to_json)

          post_graphql(query_with_permissions, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(repository_data).to be_nil
          expect(graphql_errors).to be_nil
        end
      end

      context 'when two users of the organization read the same repository in one process' do
        let_it_be(:other_user) { create(:organization_user, organization: organization).user }

        let(:registry_cache_key) { ['artifact_registry', 'namespace_mapping', 'registry', namespace_mapping.id] }

        def stub_read_as(user, body)
          stub_request(:get, repository_url)
            .with(query: include_permissions_query, headers: { 'Authorization' => "Bearer token-for-#{user.id}" })
            .to_return(status: 200, headers: json_headers, body: body.to_json)
        end

        before do
          allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
            allow(token_exchange).to receive(:token_for) { |user, _organization| "token-for-#{user.id}" }
          end

          stub_read_as(current_user, body_with_permissions)
          stub_read_as(other_user, repository_body.merge('permissions' => repository_actions.index_with { false }))
        end

        it 'gives each user their own verdicts and writes none to the registry cache',
          :aggregate_failures, :use_clean_rails_memory_store_caching do
          post_graphql(query_with_permissions, current_user: current_user)
          expect(graphql_data_at(:organization, :artifact_registry_repository, :user_permissions))
            .to eq(permissions_data)

          post_graphql(query_with_permissions, current_user: other_user)
          expect(graphql_data_at(:organization, :artifact_registry_repository, :user_permissions).values)
            .to all(be(false))

          expect(Rails.cache.read(registry_cache_key).keys).to contain_exactly(:slug, :status, :created_at)
        end
      end

      context 'when one operation aliases the field with and without the block' do
        let(:query) do
          <<~QUERY
            query {
              organization(id: "#{organization.to_global_id}") {
                withBlock: artifactRegistryRepository(name: "#{repository_name}") {
                  name userPermissions { #{permission_fields} }
                }
                withoutBlock: artifactRegistryRepository(name: "#{repository_name}") { name }
              }
            }
          QUERY
        end

        it 'issues two reads, one with the parameter and one without', :aggregate_failures do
          with_permissions = stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 200, headers: json_headers, body: body_with_permissions.to_json)
          without_permissions = stub_request(:get, repository_url)
            .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

          post_graphql(query, current_user: current_user)

          expect(with_permissions).to have_been_requested.once
          expect(without_permissions).to have_been_requested.once
          expect(graphql_dig_at(graphql_data, :organization, :with_block, :user_permissions)).to eq(permissions_data)
          expect(graphql_dig_at(graphql_data, :organization, :without_block, :name)).to eq(repository_name)
        end
      end

      context 'when one operation aliases the field twice, both selecting the block' do
        let(:query) do
          <<~QUERY
            query {
              organization(id: "#{organization.to_global_id}") {
                a: artifactRegistryRepository(name: "#{repository_name}") { userPermissions { readRepository } }
                b: artifactRegistryRepository(name: "#{repository_name}") { userPermissions { readArtifact } }
              }
            }
          QUERY
        end

        it 'issues one read carrying the parameter', :aggregate_failures do
          with_permissions = stub_request(:get, repository_url).with(query: include_permissions_query)
            .to_return(status: 200, headers: json_headers, body: body_with_permissions.to_json)

          post_graphql(query, current_user: current_user)

          expect(with_permissions).to have_been_requested.once
          expect(a_request(:get, repository_url)).not_to have_been_made
          expect(graphql_dig_at(graphql_data, :organization, :a, :user_permissions, :read_repository)).to be(true)
          expect(graphql_dig_at(graphql_data, :organization, :b, :user_permissions, :read_artifact)).to be(true)
        end
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    it 'resolves to null and makes no HTTP call', :aggregate_failures do
      request = stub_request(:get, repository_url)

      stub_feature_flags(artifact_registry_ui: false)

      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_data).to be_nil
      expect(request).not_to have_been_requested
    end

    it 'keeps the permissions block in the schema, resolves the parent null, and sends no include_permissions',
      :aggregate_failures do
      stub_feature_flags(artifact_registry_ui: false)

      post_graphql(query_with_permissions, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_data).to be_nil
      expect(graphql_errors).to be_nil
      expect(a_request(:any, /include_permissions/)).not_to have_been_made
      expect(a_request(:get, repository_url)).not_to have_been_made
      expect(GitlabSchema.types['ArtifactRegistryRepositoryPermissions']).to be_present
      expect(GitlabSchema.types['ArtifactRegistryRepositoryDetails'].fields['userPermissions'].type.unwrap.graphql_name)
        .to eq('ArtifactRegistryRepositoryPermissions')
    end
  end
end
