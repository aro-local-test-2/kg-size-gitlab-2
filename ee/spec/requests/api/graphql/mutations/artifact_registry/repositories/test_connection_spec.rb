# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Testing an Artifact Registry repository upstream connection',
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

  let(:verdict_attributes) do
    {
      'passed' => true,
      'http_status' => 200,
      'last_health_status' => 'healthy',
      'last_health_checked_at' => '2026-08-20T10:00:00Z'
    }
  end

  let(:verdict) { ArtifactRegistry::ConnectionTestResult.new(verdict_attributes) }

  let(:input) { { 'name' => 'my-repo' } }

  let(:mutation) { graphql_mutation(:artifact_registry_repository_test_connection, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_repository_test_connection)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      # The organization is a let_it_be record that memoizes its client, so the
      # memo can carry a double from one example into the next. Clear it, then
      # stub Client.new to return this example's double.
      current_organization.clear_memoization(:artifact_registry_client)
      allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive(:namespace).with(uuid: namespace_mapping.ar_namespace_id).and_return(namespace)
    end

    it 'returns the probe verdict beside the stored health fields', :aggregate_failures do
      expect(client).to receive(:test_upstream_connection).with(
        slug: slug,
        name: 'my-repo'
      ).and_return(verdict)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['passed']).to be(true)
      expect(mutation_response['httpStatus']).to eq(200)
      expect(mutation_response['lastHealthStatus']).to eq('HEALTHY')
      expect(mutation_response['lastHealthCheckedAt']).to be_present
    end

    context 'when the upstream is unreachable' do
      let(:verdict_attributes) do
        super().merge('passed' => false, 'http_status' => nil)
      end

      it 'is a successful mutation carrying a not-reachable verdict', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        # The probe ran, so its verdict is the payload. An empty errors array alone
        # would still pass if the verdict were dropped, so assert both halves.
        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['passed']).to be(false)
        expect(mutation_response['httpStatus']).to be_nil
      end
    end

    context 'when the upstream answered with a failing status' do
      let(:verdict_attributes) { super().merge('http_status' => 401) }

      it 'reports reachability rather than credential validity', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['passed']).to be(true)
        expect(mutation_response['httpStatus']).to eq(401)
      end
    end

    context 'when the probe and the stored verdict disagree' do
      let(:verdict_attributes) do
        super().merge('passed' => false, 'last_health_status' => 'healthy')
      end

      it 'returns both without treating either as an error', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        # One failure sits below Artifact Registry's consecutive-failure threshold.
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['passed']).to be(false)
        expect(mutation_response['lastHealthStatus']).to eq('HEALTHY')
      end
    end

    context 'when Artifact Registry reports an unrecognized stored status' do
      let(:verdict_attributes) { super().merge('last_health_status' => 'degraded') }

      it 'resolves UNKNOWN with the rest of the payload intact', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection).and_return(verdict)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['lastHealthStatus']).to eq('UNKNOWN')
        expect(mutation_response['passed']).to be(true)
      end
    end

    context 'when the repository is missing, hosted, or virtual (404)' do
      it 'surfaces a payload not-found error rather than a top-level error', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection)
          .and_raise(ArtifactRegistry::Client::ApiError.new('repository not found', status: 404, code: 'not_found'))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/not found/))
        expect(mutation_response['passed']).to be_nil
      end
    end

    context 'when the verdict could not be recorded (500)' do
      it 'raises a top-level service-unavailable error', :aggregate_failures do
        allow(client).to receive(:test_upstream_connection)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('verdict write failed', status: 500))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => a_string_matching(/unavailable/)))
        expect(mutation_response).to be_nil
      end
    end

    context 'when Artifact Registry denies the test (403)' do
      it 'renders a top-level ResourceNotAvailable' do
        allow(client).to receive(:test_upstream_connection)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end
  end

  # No client stub needed: these assert the schema shape, independent of any request.
  # The probe of a supplied URL is a separate mutation, so this one takes identity only.
  it 'exposes only the identity argument' do
    input_type = GitlabSchema.types['ArtifactRegistryRepositoryTestConnectionInput']

    expect(input_type.arguments.keys).to match_array(%w[clientMutationId name])
  end

  # Upstream credentials are write-only, so no read path may materialize one.
  it 'exposes no credential field on the payload' do
    payload_type = GitlabSchema.types['ArtifactRegistryRepositoryTestConnectionPayload']

    expect(payload_type.fields.keys).to match_array(
      %w[clientMutationId errors passed httpStatus lastHealthStatus lastHealthCheckedAt]
    )
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
