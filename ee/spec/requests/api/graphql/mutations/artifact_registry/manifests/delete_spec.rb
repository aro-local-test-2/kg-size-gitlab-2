# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting one container manifest of an Artifact Registry repository',
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

  let(:format) { 'docker' }
  let(:repository_name) { 'docker-remote' }
  let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:digest) { "sha256:#{'1' * 64}" }
  let(:parents) { ["sha256:#{'a' * 64}", "sha256:#{'b' * 64}"] }

  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:manifest_url) do
    "#{repository_url}/#{format}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}"
  end

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

  let(:input) { { 'name' => repository_name, 'imageId' => image_id, 'digest' => digest } }

  let(:mutation) do
    graphql_mutation(:artifact_registry_manifest_delete, input, <<~FIELDS)
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
      'docker' | 'docker-remote'
      'oci'    | 'oci-remote'
    end

    with_them do
      it 'deletes the manifest addressed by digest, and resolves', :aggregate_failures do
        read = stub_repository_read
        deletion = stub_request(:delete, manifest_url).to_return(status: 202, body: '', headers: json_headers)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(read).to have_been_requested.once
        expect(deletion).to have_been_requested.once
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
      deletion = stub_request(:delete, manifest_url).to_return(status: 202, body: '', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
    end
  end

  context 'when the repository is virtual' do
    let(:repository_body) { super().merge('kind' => 'virtual') }

    it 'issues the same route, leaving the outcome to Artifact Registry', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, manifest_url).to_return(status: 202, body: '', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to be_empty
    end
  end

  context 'when another manifest indexes the target (409)' do
    it 'reports a mutation error naming the blocking digests', :aggregate_failures do
      stub_repository_read
      stub_manifest_conflict(parents: parents)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors'].join).to include(digest, *parents)
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end

    it 'reports the refusal without inventing digests when the response carries none',
      :aggregate_failures do
      stub_repository_read
      stub_manifest_conflict({})

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to include('the manifest is indexed by another manifest')
      expect(mutation_response['errors'].join).not_to include('sha256:')
      expect(mutation_response['repository']).to be_nil
    end

    it 'drops the whole list and logs when one blocking digest is malformed', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:log_exception)
        .with(an_object_having_attributes(message: /2 parent digests, not all of the digest shape/), anything)

      stub_repository_read
      stub_manifest_conflict(parents: [parents.first, "SHA256:#{'a' * 64}"])

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to include('the manifest is indexed by another manifest')
      expect(mutation_response['errors'].join).not_to include('sha256:')
      expect(mutation_response['repository']).to be_nil
    end

    it 'caps the rendered digests and reports the total when the list is long', :aggregate_failures do
      many = Array.new(12) { |i| "sha256:#{i.to_s(16).rjust(64, '0')}" }

      stub_repository_read
      stub_manifest_conflict(parents: many)

      post_graphql_mutation(mutation, current_user: current_user)

      message = mutation_response['errors'].join
      expect(message).to include('indexed by 12 other manifests')
      expect(message).to include(*many.first(10))
      many.last(2).each { |omitted| expect(message).not_to include(omitted) }
    end
  end

  context 'when a non-409 response carries blocking digests' do
    it 'takes the generic mapping rather than reporting a refusal', :aggregate_failures do
      stub_repository_read
      stub_request(:delete, manifest_url).to_return(
        status: 404,
        body: { error: { code: 'not_found', message: 'manifest not found', details: { parents: parents } } }.to_json,
        headers: json_headers
      )

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to include('manifest not found')
      expect(mutation_response['errors'].join).not_to include('indexed by')
      expect(mutation_response['repository']).to be_nil
    end
  end

  context 'when the digest exceeds the length bound' do
    let(:digest) { "sha256:#{'1' * 600}" }

    it 'rejects the argument before any request leaves the monolith', :aggregate_failures do
      read = stub_repository_read
      deletion = stub_request(:delete, manifest_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(read).not_to have_been_requested
      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /too long/))
    end
  end

  context 'when the manifest is already gone (404)' do
    it 'reports a mutation error rather than resolving as a success', :aggregate_failures do
      stub_repository_read
      stub_request(:delete, manifest_url)
        .to_return(status: 404, body: { error: { code: 'not_found', message: 'manifest not found' } }.to_json,
          headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to include('manifest not found')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when authorization could not be evaluated (503)' do
    it 'surfaces the service-unavailable error rather than a refusal', :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_repository_read
      deletion = stub_request(:delete, manifest_url).to_return(status: 503, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when Artifact Registry denies the request (403)' do
    it 'reports the refusal after the attempt rather than hiding the repository', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, manifest_url).to_return(status: 403, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the repository holds packages rather than container images' do
    let(:format) { 'maven' }
    let(:repository_name) { 'maven-hosted' }

    it 'rejects the request before issuing a delete', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:delete, manifest_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect_graphql_errors_to_include('Only Docker and OCI repositories have manifests and container tags.')
    end
  end

  context 'when the repository does not exist' do
    it 'hides its absence and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 404, body: { error: { code: 'not_found' } }.to_json)
      deletion = stub_request(:delete, manifest_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
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

  def stub_manifest_conflict(details)
    body = {
      error: {
        code: 'conflict',
        message: 'the manifest is indexed by another manifest',
        details: details
      }
    }

    stub_request(:delete, manifest_url).to_return(status: 409, body: body.to_json, headers: json_headers)
  end

  def mutation_response
    graphql_mutation_response(:artifact_registry_manifest_delete)
  end
end
