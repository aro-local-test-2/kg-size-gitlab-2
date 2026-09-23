# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reading the organization Artifact Registry', :use_clean_rails_memory_store_caching, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: organization)
  end

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:service_token) { 'ar-service-credential-value' }
  let(:namespace_uuid) { mapping.ar_namespace_id }
  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_uuid}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:status) { 'active' }
  let(:slug) { 'acme' }
  let(:namespace_details_url) { "#{base_url}/api/v1/#{slug}/namespace" }
  let(:namespace_actions) { ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS }
  let(:allowed_actions) { %w[read_repository create_repository] }
  let(:namespace_permissions) { namespace_actions.index_with { |action| allowed_actions.include?(action) } }

  let(:namespace_details_body) do
    {
      'slug' => slug,
      'created_at' => '2026-07-01T10:00:00Z',
      'permissions' => namespace_permissions
    }
  end

  let(:namespace_body) do
    {
      'id' => namespace_uuid,
      'slug' => slug,
      'platform' => 'gitlab',
      'entity_type' => 'group',
      'entity_id' => '42',
      'status' => status,
      'created_at' => '2026-07-01T10:00:00Z'
    }
  end

  let(:fields) { 'id slug status createdAt' }
  let(:fields_with_permissions) { "id slug status createdAt userPermissions { #{permission_fields} }" }

  let(:query) do
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      query_graphql_field(:artifact_registry, {}, fields)
    )
  end

  let(:registry_data) { graphql_data.dig('organization', 'artifactRegistry') }

  before do
    stub_config(artifact_registry: { api_url: base_url })
    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end
  end

  def stub_namespace(status:, body: namespace_body.to_json)
    stub_request(:get, namespace_url)
      .with(headers: { ArtifactRegistry::Client::SERVICE_TOKEN_HEADER => service_token })
      .to_return(status: status, headers: json_headers, body: body)
  end

  def permission_fields
    namespace_actions.map { |action| action.camelize(:lower) }.join(' ')
  end

  def camelize_keys(permissions)
    permissions.transform_keys { |action| action.camelize(:lower) }
  end

  def user_token_for(user)
    "token-for-#{user.id}"
  end

  def stub_namespace_details(status:, body: namespace_details_body.to_json, user: current_user)
    stub_request(:get, namespace_details_url)
      .with(query: { include_permissions: 'true' }, headers: { 'Authorization' => "Bearer #{user_token_for(user)}" })
      .to_return(status: status, headers: json_headers, body: body)
  end

  context 'when the artifact_registry_ui flag is on' do
    context 'when the organization is activated' do
      it 'returns the namespace UUID, slug, status, and creation time from a single AR call',
        :aggregate_failures do
        request = stub_namespace(status: 200)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(request).to have_been_requested.once
        expect(registry_data).to eq(
          'id' => namespace_uuid,
          'slug' => 'acme',
          'status' => 'active',
          'createdAt' => '2026-07-01T10:00:00+00:00'
        )
      end

      context 'when AR returns an unrecognized status' do
        let(:status) { 'newly_added_state' }

        it 'passes the unknown status through without raising', :aggregate_failures do
          stub_namespace(status: 200)

          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(registry_data['status']).to eq('newly_added_state')
        end
      end

      context 'when AR returns a 200 with no status field' do
        it 'resolves the unknown status rather than nulling the non-null field', :aggregate_failures do
          stub_namespace(status: 200, body: namespace_body.except('status').to_json)

          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(registry_data['status']).to eq('unknown')
        end
      end

      context 'when the mapped namespace is unknown to AR (404)' do
        # The UUID reads off the mapping row, so it renders even though AR answered nothing.
        it 'renders the unknown status with the UUID but null slug and creation time, no error',
          :aggregate_failures do
          stub_namespace(status: 404, body: {}.to_json)

          post_graphql(query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(graphql_errors).to be_nil
          expect(registry_data).to eq(
            'id' => namespace_uuid,
            'slug' => nil,
            'status' => 'unknown',
            'createdAt' => nil
          )
        end
      end

      context 'when AR denies the read (403)' do
        it 'renders the registry not-available while a sibling field still resolves', :aggregate_failures do
          stub_namespace(status: 403, body: {}.to_json)

          post_graphql(with_sibling_query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(registry_data).to be_nil
          expect(graphql_errors).to be_nil
          expect(graphql_data.dig('organization', 'name')).to eq(organization.name)
        end
      end

      context 'when AR is unavailable (503)' do
        it 'answers service-unavailable while a sibling field making no AR call still resolves', :aggregate_failures do
          stub_namespace(status: 503, body: {}.to_json)

          post_graphql(with_sibling_query, current_user: current_user)

          expect(registry_data).to be_nil
          expect(graphql_errors).to be_present
          expect(graphql_data.dig('organization', 'name')).to eq(organization.name)
        end
      end
    end

    describe 'the user permissions block' do
      let(:fields) { fields_with_permissions }

      before do
        allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
          allow(token_exchange).to receive(:token_for) { |user, _organization| user_token_for(user) }
        end
      end

      it 'reads the namespace details as the user with include_permissions=true and resolves one Boolean per action',
        :aggregate_failures do
        registry_read = stub_namespace(status: 200)
        details_read = stub_namespace_details(status: 200)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(registry_read).to have_been_requested.once
        expect(details_read).to have_been_requested.once
        expect(a_request(:any, /include_permissions/)).to have_been_made.once
        expect(
          a_request(:get, namespace_details_url)
            .with { |req| req.headers.key?(ArtifactRegistry::Client::SERVICE_TOKEN_HEADER) }
        ).not_to have_been_made
        expect(registry_data).to eq(
          'id' => namespace_uuid,
          'slug' => slug,
          'status' => 'active',
          'createdAt' => '2026-07-01T10:00:00+00:00',
          'userPermissions' => camelize_keys(namespace_permissions)
        )
        expect(graphql_errors).to be_nil
      end

      context 'when the block is not selected' do
        let(:fields) { 'slug status createdAt' }

        it 'makes no namespace details call and sends no include_permissions', :aggregate_failures do
          stub_namespace(status: 200)

          post_graphql(query, current_user: current_user)

          expect(registry_data['slug']).to eq(slug)
          expect(a_request(:get, %r{/api/v1/})).not_to have_been_made
          expect(a_request(:any, /include_permissions/)).not_to have_been_made
        end
      end

      context 'when the namespace details body carries no permissions object' do
        let(:absent_report) do
          [
            instance_of(ArtifactRegistry::Permissions::VerdictReport::AbsentError),
            { read: :namespace_details, slug: slug }
          ]
        end

        before do
          allow(Gitlab::ErrorTracking).to receive(:track_exception)

          stub_namespace(status: 200)
          stub_namespace_details(status: 200, body: namespace_details_body.except('permissions').to_json)
        end

        it 'resolves every permission false, keeps the parent populated, and adds no error', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(registry_data).to include('slug' => slug, 'status' => 'active')
          expect(registry_data['userPermissions'].keys).to match_array(camelize_keys(namespace_permissions).keys)
          expect(registry_data['userPermissions'].values).to all(be(false))
          expect(graphql_errors).to be_nil
        end

        it 'reports the absence once for the namespace details read and the slug, not once per field' do
          post_graphql(query, current_user: current_user)

          expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(*absent_report).once
        end
      end

      context 'when Artifact Registry does not know the slug for this caller (404)' do
        it 'resolves the parent null with no verdict while a sibling field still resolves', :aggregate_failures do
          stub_namespace(status: 200)
          stub_namespace_details(status: 404, body: { code: 'not_found' }.to_json)
          expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:defect)

          post_graphql(with_sibling_query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(registry_data).to be_nil
          expect(graphql_errors).to contain_exactly(
            a_hash_including(
              'message' => Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR,
              'path' => %w[organization artifactRegistry userPermissions]
            )
          )
          expect(graphql_data.dig('organization', 'name')).to eq(organization.name)
        end
      end

      context 'when Artifact Registry denies the namespace details read (403)' do
        it 'resolves the parent null with the same error a 404 renders', :aggregate_failures do
          stub_namespace(status: 200)
          stub_namespace_details(status: 403, body: { code: 'forbidden' }.to_json)
          expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:defect)

          post_graphql(with_sibling_query, current_user: current_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(registry_data).to be_nil
          expect(graphql_errors).to contain_exactly(
            a_hash_including(
              'message' => Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR,
              'path' => %w[organization artifactRegistry userPermissions]
            )
          )
          expect(graphql_data.dig('organization', 'name')).to eq(organization.name)
        end
      end

      context 'when Artifact Registry is unavailable (503) on the namespace details read' do
        it 'answers service-unavailable and reaches no block', :aggregate_failures do
          stub_namespace(status: 200)
          stub_namespace_details(status: 503, body: {}.to_json)
          expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:absent)
          expect(ArtifactRegistry::Permissions::VerdictReport).not_to receive(:defect)

          post_graphql(query, current_user: current_user)

          expect(registry_data).to be_nil
          expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
        end
      end

      context 'when two users of the organization select the block in one process' do
        let_it_be(:other_user) { create(:organization_user, organization: organization).user }

        let(:registry_cache_key) { ['artifact_registry', 'namespace_mapping', 'registry', mapping.id] }

        it 'gives each user their own verdicts and writes none to the registry cache', :aggregate_failures do
          stub_namespace(status: 200)
          stub_namespace_details(status: 200)
          stub_namespace_details(
            status: 200,
            user: other_user,
            body: namespace_details_body.merge('permissions' => namespace_actions.index_with { false }).to_json
          )

          post_graphql(query, current_user: current_user)
          expect(graphql_data_at(:organization, :artifact_registry, :user_permissions))
            .to eq(camelize_keys(namespace_permissions))

          post_graphql(query, current_user: other_user)
          expect(graphql_data_at(:organization, :artifact_registry, :user_permissions).values).to all(be(false))

          expect(Rails.cache.read(registry_cache_key).keys).to contain_exactly(:slug, :status, :created_at)
        end
      end

      context 'when one operation aliases the field twice, both selecting the block' do
        let(:query) do
          <<~QUERY
            query {
              organization(id: "#{organization.to_global_id}") {
                a: artifactRegistry { userPermissions { readRepository } }
                b: artifactRegistry { userPermissions { createRepository } }
              }
            }
          QUERY
        end

        it 'reads the namespace details once and renders both aliases', :aggregate_failures do
          stub_namespace(status: 200)
          details_read = stub_namespace_details(status: 200)

          post_graphql(query, current_user: current_user)

          expect(details_read).to have_been_requested.once
          expect(graphql_dig_at(graphql_data, :organization, :a, :user_permissions, :read_repository)).to be(true)
          expect(graphql_dig_at(graphql_data, :organization, :b, :user_permissions, :create_repository)).to be(true)
        end
      end

      context 'when the viewer lacks read_artifact_registry' do
        it 'resolves null and makes no AR call, so the block is never reached', :aggregate_failures do
          expect(Resolvers::ArtifactRegistry::NamespacePermissionsResolver).not_to receive(:new)

          post_graphql(query, current_user: non_member)

          expect(response).to have_gitlab_http_status(:ok)
          expect(registry_data).to be_nil
          expect(a_request(:get, %r{/api/})).not_to have_been_made
        end
      end
    end

    context 'when the organization has no mapping row' do
      let_it_be(:bare_organization) { create(:organization) }
      let_it_be(:bare_user) { create(:organization_user, organization: bare_organization).user }

      let(:query) do
        graphql_query_for(
          :organization,
          { id: bare_organization.to_global_id.to_s },
          query_graphql_field(:artifact_registry, {}, fields)
        )
      end

      it 'resolves null and makes no AR call', :aggregate_failures do
        request = stub_request(:get, %r{/api/gitlab/v1/namespaces/})

        post_graphql(query, current_user: bare_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(registry_data).to be_nil
        expect(request).not_to have_been_requested
      end
    end

    context 'when the viewer lacks read_artifact_registry' do
      it 'resolves null and makes no AR call', :aggregate_failures do
        request = stub_request(:get, namespace_url)

        post_graphql(query, current_user: non_member)

        expect(response).to have_gitlab_http_status(:ok)
        expect(registry_data).to be_nil
        expect(request).not_to have_been_requested
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    it 'keeps the field in the schema, resolves null, and makes no AR call', :aggregate_failures do
      request = stub_request(:get, namespace_url)
      stub_feature_flags(artifact_registry_ui: false)

      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(GitlabSchema.types['Organization'].fields).to have_key('artifactRegistry')
      expect(registry_data).to be_nil
      expect(request).not_to have_been_requested
    end

    context 'when the user permissions block is selected' do
      let(:fields) { fields_with_permissions }

      it 'keeps the block in the schema, resolves the parent null, and never invokes the block resolver',
        :aggregate_failures do
        stub_feature_flags(artifact_registry_ui: false)
        expect(Resolvers::ArtifactRegistry::NamespacePermissionsResolver).not_to receive(:new)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(registry_data).to be_nil
        expect(graphql_errors).to be_nil
        expect(a_request(:get, %r{/api/})).not_to have_been_made
        expect(a_request(:any, /include_permissions/)).not_to have_been_made

        field = GitlabSchema.types['ArtifactRegistry'].fields['userPermissions']
        expect(field.type).to be_non_null
        expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryNamespacePermissions')
      end
    end
  end

  def with_sibling_query
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      "name #{query_graphql_field(:artifact_registry, {}, fields)}"
    )
  end
end
