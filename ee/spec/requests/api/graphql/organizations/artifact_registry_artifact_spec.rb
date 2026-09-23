# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry single-artifact fields', feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:artifact_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:package_url) { "#{repository_url}/#{format}/packages/#{artifact_id}" }
  let(:image_url) { "#{repository_url}/#{format}/images/#{artifact_id}" }

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

  let(:maven_package_body) do
    {
      'id' => artifact_id,
      'group_id' => 'com.example.tools',
      'artifact_id' => 'payment-core',
      'last_downloaded_at' => '2026-07-03T09:15:00Z'
    }
  end

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryArtifact($id: OrganizationsOrganizationID!, $name: String!, $artifactId: ID!) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            package(id: $artifactId) {
              __typename
              ... on ArtifactRegistryMavenPackageDetails { id groupId artifactId }
              ... on ArtifactRegistryNpmPackageDetails { id name scope versionsCount }
            }
            image(id: $artifactId) {
              __typename
              id
              name
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
      variables: { id: organization.to_global_id.to_s, name: repository_name, artifactId: artifact_id })
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  context 'when the repository holds Maven packages' do
    it 'returns the package on the package field and null on the image field, with one AR read',
      :aggregate_failures do
      stub_repository_read
      package = stub_request(:get, package_url).to_return(
        status: 200, body: maven_package_body.to_json, headers: json_headers)
      image = stub_request(:get, image_url)

      post_query

      expect(repository_response['package']).to eq(
        '__typename' => 'ArtifactRegistryMavenPackageDetails',
        'id' => artifact_id,
        'groupId' => 'com.example.tools',
        'artifactId' => 'payment-core'
      )
      expect(repository_response['image']).to be_nil
      expect(package).to have_been_requested.once
      expect(image).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end

    it 'never leaks the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_request(:get, package_url).to_return(
        status: 200, body: maven_package_body.to_json, headers: json_headers)

      post_query

      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the repository holds npm packages' do
    let(:format) { 'npm' }
    let(:repository_name) { 'npm-releases' }
    let(:npm_package_body) do
      { 'id' => artifact_id, 'name' => '@acme/ui-components', 'scope' => '@acme', 'versions_count' => 7 }
    end

    it 'returns the npm package on the package field', :aggregate_failures do
      stub_repository_read
      stub_request(:get, package_url).to_return(status: 200, body: npm_package_body.to_json, headers: json_headers)

      post_query

      expect(repository_response['package']).to eq(
        '__typename' => 'ArtifactRegistryNpmPackageDetails',
        'id' => artifact_id,
        'name' => '@acme/ui-components',
        'scope' => '@acme',
        'versionsCount' => 7
      )
    end
  end

  context 'when the repository holds Docker images' do
    let(:format) { 'docker' }
    let(:repository_name) { 'container-images' }
    let(:image_body) { { 'id' => artifact_id, 'name' => 'api-gateway' } }

    it 'returns the image on the image field and null on the package field, with one AR read',
      :aggregate_failures do
      stub_repository_read
      package = stub_request(:get, package_url)
      image = stub_request(:get, image_url).to_return(status: 200, body: image_body.to_json, headers: json_headers)

      post_query

      expect(repository_response['image']).to eq(
        '__typename' => 'ArtifactRegistryImage',
        'id' => artifact_id,
        'name' => 'api-gateway'
      )
      expect(repository_response['package']).to be_nil
      expect(image).to have_been_requested.once
      expect(package).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-artifacts' }
    let(:image_body) { { 'id' => artifact_id, 'name' => 'payment-service' } }

    it 'returns the image for an OCI repository too' do
      stub_repository_read
      stub_request(:get, image_url).to_return(status: 200, body: image_body.to_json, headers: json_headers)

      post_query

      expect(repository_response['image']['name']).to eq('payment-service')
    end
  end

  # 404, 401, and 403 all take the existence-hiding arm: the field resolves null and the
  # repository still renders, so a missing artifact and a forbidden one are indistinguishable.
  [404, 401, 403].each do |status|
    context "when Artifact Registry answers the artifact read with #{status}" do
      it 'resolves the field null while the repository still renders', :aggregate_failures do
        stub_repository_read
        stub_request(:get, package_url).to_return(
          status: status, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        post_query

        expect(repository_response['package']).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when Artifact Registry answers the artifact read with a server error' do
    it 'renders the service-unavailable error beside the loaded repository, with request_id preserved',
      :aggregate_failures do
      stub_repository_read
      stub_request(:get, package_url).to_return(
        status: 503, body: error_envelope(code: 'service_unavailable', request_id: 'req-503').to_json,
        headers: json_headers)

      post_query

      expect(repository_response['package']).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
    end
  end

  context 'when Artifact Registry answers the artifact read with a non-404 client error' do
    it 'surfaces a top-level error carrying the code and request_id, not a bare null',
      :aggregate_failures do
      stub_repository_read
      stub_request(:get, package_url).to_return(
        status: 422, body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json,
        headers: json_headers)

      post_query

      expect(graphql_errors).to be_present
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
    end
  end

  context 'when the artifact read fails in transport' do
    it 'renders the service-unavailable error on a connection failure' do
      stub_repository_read
      stub_request(:get, package_url).to_raise(Faraday::ConnectionFailed)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end

    it 'renders the service-unavailable error on a timeout, which the retry middleware handles' do
      stub_repository_read
      stub_request(:get, package_url).to_timeout

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      package = stub_request(:get, package_url)

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(package).not_to have_been_requested
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

  # The per-field `FieldCallCount` budget of 1 stops a second aliased selection of the same field
  # before its resolve body runs, so the operation issues one artifact read rather than two.
  shared_examples 'rejecting a second aliased selection of the field' do |field:|
    let(:query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              a: #{field}(id: "#{artifact_id}") { __typename }
              b: #{field}(id: "#{artifact_id}") { __typename }
            }
          }
        }
      QUERY
    end

    subject(:post_aliased_query) { post_graphql(query, current_user: current_user) }

    it 'rejects the second selection and issues one artifact read, not two', :aggregate_failures do
      stub_repository_read
      artifact = stub_request(:get, artifact_url).to_return(
        status: 200, body: artifact_body.to_json, headers: json_headers)

      post_aliased_query

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(artifact).to have_been_requested.once
    end
  end

  context 'when one operation selects the package field twice under aliases' do
    let(:artifact_url) { package_url }
    let(:artifact_body) { maven_package_body }

    it_behaves_like 'rejecting a second aliased selection of the field', field: 'package'
  end

  context 'when one operation selects the image field twice under aliases' do
    let(:format) { 'docker' }
    let(:repository_name) { 'container-images' }
    let(:artifact_url) { image_url }
    let(:artifact_body) { { 'id' => artifact_id, 'name' => 'api-gateway' } }

    it_behaves_like 'rejecting a second aliased selection of the field', field: 'image'
  end
end
