# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting one version of an Artifact Registry package',
  feature_category: :artifact_registry do
  include GraphqlHelpers

  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:service_token) { 'ar-service-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-remote' }
  let(:version_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }

  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:version_url) { "#{repository_url}/#{format}/versions/#{version_id}" }

  let(:namespace_body) do
    { 'id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active' }
  end

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'remote',
      'visibility' => 'private',
      'downloads_count' => 0,
      'size_bytes' => 0
    }
  end

  let(:input) { { 'name' => repository_name, 'id' => version_id } }

  let(:mutation) do
    graphql_mutation(:artifact_registry_version_delete, input, <<~FIELDS)
      errors
      repository {
        name
        format
      }
    FIELDS
  end

  before do
    current_organization.clear_memoization(:artifact_registry_client)

    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end

    stub_request(:get, namespace_url).to_return(status: 200, headers: json_headers, body: namespace_body.to_json)
  end

  context 'when Artifact Registry accepts the request' do
    where(:format, :repository_name) do
      'maven' | 'maven-remote'
      'npm'   | 'npm-remote'
    end

    with_them do
      it 'deletes the version id under the route the format selects, and resolves', :aggregate_failures do
        read = stub_repository_read
        deletion = stub_request(:delete, version_url).to_return(status: 202, body: '', headers: json_headers)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(read).to have_been_requested.once
        expect(deletion).to have_been_requested.once
        expect(a_request(:delete, version_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_made.once
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
      end
    end
  end

  context 'when the repository is hosted rather than remote' do
    let(:repository_body) { super().merge('kind' => 'hosted') }

    it 'issues the same route, leaving the delete-or-evict choice to Artifact Registry',
      :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, version_url).to_return(status: 202, body: '', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
    end
  end

  context 'when the repository holds container images rather than packages' do
    let(:format) { 'docker' }
    let(:repository_name) { 'docker-remote' }

    it 'refuses before any deletion is attempted with a payload error', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, version_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(deletion).not_to have_been_requested
      expect(mutation_response['errors']).to include('Only Maven and npm repositories have versions.')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the version is already gone (404)' do
    it 'reports a mutation error rather than resolving as a success', :aggregate_failures do
      stub_repository_read
      stub_request(:delete, version_url)
        .to_return(status: 404, body: { error: { code: 'not_found', message: 'version not found' } }.to_json,
          headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to include('version not found')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when authorization could not be evaluated (503)' do
    it 'surfaces the service-unavailable error rather than a refusal', :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_repository_read
      deletion = stub_request(:delete, version_url).to_return(status: 503, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when Artifact Registry denies the request (403)' do
    it 'reports the refusal after the attempt rather than hiding the repository', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, version_url).to_return(status: 403, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the repository does not exist' do
    it 'hides its absence and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 404, body: { error: { code: 'not_found' } }.to_json)
      deletion = stub_request(:delete, version_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the repository read is denied (403)' do
    it 'is indistinguishable from a missing repository and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 403, body: '{}')
      deletion = stub_request(:delete, version_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the version id is blank' do
    let(:version_id) { '' }

    it 'raises the client guard before any deletion is attempted', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, version_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      # The message names the client keyword, not this mutation's `id` argument.
      expect_graphql_errors_to_include('version_id is required')
    end
  end

  context 'when the user cannot read the organization registry' do
    it 'raises a top-level ResourceNotAvailable and acquires no client', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: non_member)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'raises a top-level ResourceNotAvailable and acquires no client', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def mutation_response
    graphql_mutation_response(:artifact_registry_version_delete)
  end
end
