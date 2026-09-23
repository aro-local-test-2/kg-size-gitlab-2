# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting every artifact of an Artifact Registry repository',
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
  let(:collection) { 'packages' }
  let(:repository_name) { 'maven-remote' }

  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:bulk_delete_url) { "#{repository_url}/#{format}/#{collection}/bulk_delete" }

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

  let(:input) { { 'name' => repository_name } }

  # Selected explicitly: the default selection stops before a nested object, so the payload
  # repository would otherwise never be requested and every assertion on it would read nil.
  let(:mutation) do
    graphql_mutation(:artifact_registry_repository_artifacts_delete, input, <<~FIELDS)
      errors
      repository {
        name
        format
      }
    FIELDS
  end

  before do
    # The organization is a let_it_be record that memoizes its client, so the memo can carry one
    # example's client into the next.
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
    # Every format gets its own positive hit: the format selects the collection segment, so a
    # wrong one would still answer 202 against a stub of its own route.
    where(:format, :collection, :repository_name) do
      'maven'  | 'packages' | 'maven-remote'
      'npm'    | 'packages' | 'npm-remote'
      'docker' | 'images'   | 'docker-remote'
      'oci'    | 'images'   | 'oci-remote'
    end

    with_them do
      it 'posts the whole-collection selector to the route the format selects, and resolves',
        :aggregate_failures do
        read = stub_repository_read
        deletion = stub_request(:post, bulk_delete_url)
          .with(body: '{"delete_all":true}')
          .to_return(status: 202, body: '', headers: json_headers)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(read).to have_been_requested.once
        expect(deletion).to have_been_requested.once
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
      end
    end
  end

  context 'when the name is a repository other than the one being viewed' do
    let(:other_name) { 'upstream-oci-remote' }
    let(:other_url) { "#{base_url}/api/v1/#{slug}/repositories/#{other_name}" }
    let(:input) { { 'name' => other_name } }

    it 'issues the route against that repository name and its own format', :aggregate_failures do
      stub_request(:get, other_url).to_return(
        status: 200, headers: json_headers,
        body: repository_body.merge('name' => other_name, 'format' => 'oci').to_json
      )
      deletion = stub_request(:post, "#{other_url}/oci/images/bulk_delete")
        .with(body: '{"delete_all":true}')
        .to_return(status: 202, body: '', headers: json_headers)
      viewed = stub_request(:post, bulk_delete_url)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(viewed).not_to have_been_requested
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to eq('name' => other_name, 'format' => 'OCI')
    end
  end

  # Artifact Registry picks the semantics from the repository's own kind, so the request is
  # identical either way. Asserted because a kind check added here would strand one of the callers.
  context 'when the repository is hosted rather than remote' do
    let(:repository_body) { super().merge('kind' => 'hosted') }

    it 'issues the same route, leaving the delete-or-evict choice to Artifact Registry',
      :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:post, bulk_delete_url)
        .with(body: '{"delete_all":true}')
        .to_return(status: 202, body: '', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
    end
  end

  # A virtual repository owns no artifact rows, so Artifact Registry answers the route with a 404.
  # Reported rather than pre-empted: the refusal is the service's to make, and it already makes it.
  context 'when the repository is virtual' do
    let(:repository_body) { super().merge('kind' => 'virtual') }

    it 'surfaces the not-found Artifact Registry answers as a mutation error', :aggregate_failures do
      stub_repository_read
      stub_request(:post, bulk_delete_url).to_return(
        status: 404, headers: json_headers,
        body: { error: { code: 'not_found', message: 'repository does not hold artifacts' } }.to_json
      )

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to include('repository does not hold artifacts')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the job backend cannot take the enqueue (503)' do
    it 'surfaces the service-unavailable error, so the caller may retry the whole request',
      :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_repository_read
      stub_request(:post, bulk_delete_url).to_return(status: 503, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when Artifact Registry denies the request (403)' do
    it 'reports the refusal after the attempt rather than hiding the repository', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:post, bulk_delete_url).to_return(status: 403, body: '{}', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      # The attempt is what separates this from the missing-repository case, which deletes nothing.
      expect(deletion).to have_been_requested.once
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the repository does not exist' do
    it 'hides its absence and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 404, body: { error: { code: 'not_found' } }.to_json)
      deletion = stub_request(:post, bulk_delete_url)

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
      # Base raises before AcquiresClient runs, so the flag gate is provably ahead of the client.
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def mutation_response
    graphql_mutation_response(:artifact_registry_repository_artifacts_delete)
  end
end
