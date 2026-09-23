# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dissociating an upstream repository from an Artifact Registry virtual repository',
  feature_category: :artifact_registry do
  include GraphqlHelpers

  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }

  let(:slug) { 'resolved-handle' }
  let(:namespace) do
    ArtifactRegistry::Namespace.new('id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active')
  end

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:repository_name) { 'maven-virtual' }
  let(:graphql_format) { 'MAVEN' }
  let(:wire_format) { 'maven' }
  let(:association_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }

  let(:input) do
    {
      'name' => repository_name,
      'format' => graphql_format,
      'associationId' => association_id
    }
  end

  let(:mutation) { graphql_mutation(:artifact_registry_upstream_repository_dissociate, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_upstream_repository_dissociate)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      current_organization.clear_memoization(:artifact_registry_client)
      allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive(:namespace).with(uuid: namespace_mapping.ar_namespace_id).and_return(namespace)
    end

    context 'when Artifact Registry removes the association' do
      where(:graphql_format, :wire_format) do
        'MAVEN'  | 'maven'
        'NPM'    | 'npm'
        'DOCKER' | 'docker'
        'OCI'    | 'oci'
      end

      with_them do
        it 'calls the client once with the format the argument names, and returns no errors',
          :aggregate_failures do
          expect(client).to receive(:dissociate_upstream_repository).once.with(
            slug: slug,
            repository_name: repository_name,
            format: wire_format,
            association_id: association_id
          ).and_return(true)

          post_graphql_mutation(mutation, current_user: current_user)

          expect(response).to have_gitlab_http_status(:success)
          expect(mutation_response['errors']).to be_empty
          expect(graphql_errors).to be_nil
        end
      end
    end

    context 'when Artifact Registry denies the removal (403)' do
      it 'raises a top-level ResourceNotAvailable', :aggregate_failures do
        allow(client).to receive(:dissociate_upstream_repository)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end

    context 'when Artifact Registry cannot answer the removal (503)' do
      it 'raises the service-unavailable error rather than a refusal' do
        allow(client).to receive(:dissociate_upstream_repository)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('upstream down', status: 503))

        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      end
    end

    context 'when Artifact Registry refuses the removal with an API error' do
      it 'surfaces the message in the payload errors', :aggregate_failures do
        allow(client).to receive(:dissociate_upstream_repository).and_raise(
          ArtifactRegistry::Client::ApiError.new('association is not removable', status: 409, code: 'conflict')
        )

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include('association is not removable')
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the real client reaches Artifact Registry over HTTP' do
    let(:base_url) { 'https://artifact-registry.example.test' }
    let(:token) { 'ar-request-spec-credential' }
    let(:service_token) { 'ar-service-credential' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }
    let(:dissociate_url) do
      "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}/#{wire_format}/" \
        "upstream_repositories/#{association_id}"
    end

    let(:namespace_body) do
      { 'id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active' }
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

    context 'when Artifact Registry removes the association' do
      it 'returns no errors', :aggregate_failures do
        removal = stub_request(:delete, dissociate_url).to_return(status: 204, body: '', headers: json_headers)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(removal).to have_been_requested.once
        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the association is already gone (404)' do
      it 'returns no errors, the same as a removal', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        removal = stub_request(:delete, dissociate_url).to_return(
          status: 404,
          body: { error: { code: 'not_found', message: 'upstream association not found' } }.to_json,
          headers: json_headers
        )

        post_graphql_mutation(mutation, current_user: current_user)

        expect(removal).to have_been_requested.once
        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the association id is blank' do
      let(:association_id) { '' }

      it 'raises the client guard before any request reaches Artifact Registry', :aggregate_failures do
        removal = stub_request(:delete, dissociate_url)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(removal).not_to have_been_requested
        expect_graphql_errors_to_include('association_id is required')
      end
    end
  end

  context 'when the user cannot read the organization registry' do
    it 'raises a top-level ResourceNotAvailable and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: non_member)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'raises a top-level ResourceNotAvailable and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end
end
