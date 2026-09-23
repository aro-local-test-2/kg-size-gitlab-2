# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Testing a submitted Artifact Registry upstream connection',
  feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }

  let(:slug) { 'resolved-handle' }
  let(:namespace) do
    ArtifactRegistry::Namespace.new('id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active')
  end

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:verdict_attributes) { { 'passed' => true, 'http_status' => 200 } }
  let(:verdict) { ArtifactRegistry::NamespaceConnectionTestResult.new(verdict_attributes) }

  let(:input) { { 'format' => 'MAVEN', 'url' => 'https://upstream.example.test' } }

  let(:mutation) { graphql_mutation(:artifact_registry_upstream_test_connection, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_upstream_test_connection)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      current_organization.clear_memoization(:artifact_registry_client)
      allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive(:namespace).with(uuid: namespace_mapping.ar_namespace_id).and_return(namespace)
    end

    it 'probes the submitted upstream and returns the verdict', :aggregate_failures do
      expect(client).to receive(:test_namespace_upstream_connection).with(
        slug: slug,
        format: 'maven',
        url: 'https://upstream.example.test',
        credentials: nil
      ).and_return(verdict)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['passed']).to be(true)
      expect(mutation_response['httpStatus']).to eq(200)
    end

    context 'with credentials supplied' do
      let(:input) do
        super().merge('credentials' => { 'username' => 'octocat', 'password' => 's3cret' })
      end

      it 'forwards them to the client as a hash', :aggregate_failures do
        expect(client).to receive(:test_namespace_upstream_connection).with(
          slug: slug,
          format: 'maven',
          url: 'https://upstream.example.test',
          credentials: { username: 'octocat', password: 's3cret' }
        ).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
      end
    end

    context 'when the upstream is unreachable' do
      let(:verdict_attributes) { { 'passed' => false, 'http_status' => nil } }

      it 'is a successful mutation carrying a not-reachable verdict', :aggregate_failures do
        allow(client).to receive(:test_namespace_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['passed']).to be(false)
        expect(mutation_response['httpStatus']).to be_nil
      end
    end

    context 'when the upstream answered with a failing status' do
      let(:verdict_attributes) { { 'passed' => true, 'http_status' => 401 } }

      it 'reports reachability rather than credential validity', :aggregate_failures do
        allow(client).to receive(:test_namespace_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['passed']).to be(true)
        expect(mutation_response['httpStatus']).to eq(401)
      end
    end

    context 'when Artifact Registry rejects the url or body (400)' do
      it 'surfaces a payload error rather than a top-level error', :aggregate_failures do
        allow(client).to receive(:test_namespace_upstream_connection)
          .and_raise(ArtifactRegistry::Client::ApiError.new('url invalid', status: 400, code: 'bad_request'))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/url invalid/))
        expect(mutation_response['passed']).to be_nil
      end
    end

    context 'when the slug did not resolve (404)' do
      it 'surfaces a payload not-found error', :aggregate_failures do
        allow(client).to receive(:test_namespace_upstream_connection)
          .and_raise(ArtifactRegistry::Client::ApiError.new('namespace not found', status: 404, code: 'not_found'))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to include(a_string_matching(/not found/))
        expect(mutation_response['passed']).to be_nil
      end
    end

    context 'when Artifact Registry is unavailable (500)' do
      it 'raises a top-level service-unavailable error', :aggregate_failures do
        allow(client).to receive(:test_namespace_upstream_connection)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('probe failed', status: 500))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => a_string_matching(/unavailable/)))
        expect(mutation_response).to be_nil
      end
    end

    context 'when Artifact Registry denies the test (403)' do
      it 'renders a top-level ResourceNotAvailable' do
        allow(client).to receive(:test_namespace_upstream_connection)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end
  end

  it 'exposes the submitted-upstream arguments and no identity argument' do
    input_type = GitlabSchema.types['ArtifactRegistryUpstreamTestConnectionInput']

    expect(input_type.arguments.keys).to match_array(%w[clientMutationId format url credentials])
  end

  it 'exposes a verdict-only payload with no stored-health fields' do
    payload_type = GitlabSchema.types['ArtifactRegistryUpstreamTestConnectionPayload']

    expect(payload_type.fields.keys).to match_array(%w[clientMutationId errors passed httpStatus])
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
