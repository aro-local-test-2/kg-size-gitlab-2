# frozen_string_literal: true

# Shared coverage for the disable and enable Artifact Registry condition mutations,
# which share one flow (authorize update_organization, call the condition endpoint,
# invalidate the cache, build the payload) and differ only by endpoint and status.
#
# Required bindings from the including spec:
#   mutation_name  - the GraphQL mutation name symbol, e.g. :artifact_registry_disable
#   endpoint       - the client method symbol, e.g. :disable_namespace
#   target_status  - the status the transition resolves to, e.g. 'disabled'
RSpec.shared_examples 'an Artifact Registry condition mutation' do
  include GraphqlHelpers

  let_it_be_with_reload(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_owner, organization: current_organization).user }
  let_it_be(:member) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  # Reloadable (not frozen) because the cache-invalidation example calls #reload.
  let_it_be_with_reload(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  let(:client) { instance_double(ArtifactRegistry::Client) }
  let(:transitioned_namespace) do
    ArtifactRegistry::Namespace.new(
      'id' => mapping.ar_namespace_id, 'slug' => 'acme',
      'status' => target_status, 'created_at' => '2026-01-01T00:00:00Z'
    )
  end

  let(:mutation) { graphql_mutation(mutation_name, {}, nil, ['userPermissions']) }

  def mutation_response
    graphql_mutation_response(mutation_name)
  end

  # current_organization is let_it_be and memoizes its client, so a doubled client
  # would leak across examples; clear it wherever the mutation may build one.
  def clear_service_client_memo
    current_organization.clear_memoization(:artifact_registry_client)
    mapping.organization.clear_memoization(:artifact_registry_client)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      clear_service_client_memo
      # current_user: nil pins the service-authenticated client: a slip to the
      # per-user Client.new(current_user: user) would send a user-exchanged token
      # AR would reject.
      allow(ArtifactRegistry::Client).to receive(:new)
        .with(current_user: nil, organization: anything).and_return(client)
      allow(client).to receive(endpoint).and_return(transitioned_namespace)
    end

    it 'calls the condition endpoint once and returns the transitioned registry from its response',
      :aggregate_failures do
      expect(client).to receive(endpoint).with(uuid: mapping.ar_namespace_id).once
        .and_return(transitioned_namespace)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['registry']).to eq(
        'id' => mapping.ar_namespace_id, 'slug' => 'acme', 'status' => target_status,
        'createdAt' => '2026-01-01T00:00:00+00:00'
      )
    end

    it 'invalidates the resolution cache so a later render-path read reflects the transition',
      :aggregate_failures do
      other_namespace = ArtifactRegistry::Namespace.new(
        'id' => mapping.ar_namespace_id, 'slug' => 'acme', 'status' => 'suspended',
        'created_at' => '2026-01-01T00:00:00Z'
      )
      # Warm the render-path cache with a different status. Without expire_registry_cache
      # the next read would serve that stale entry; with it, the read issues a fresh
      # namespace call and sees the transitioned status.
      allow(client).to receive(:namespace).and_return(other_namespace, transitioned_namespace)
      expect(mapping.reload.registry.status).to eq('suspended')

      post_graphql_mutation(mutation, current_user: current_user)

      clear_service_client_memo
      expect(mapping.reload.registry.status).to eq(target_status)
    end

    it 'is idempotent: a repeat request calls the endpoint again and still succeeds',
      :aggregate_failures do
      expect(client).to receive(endpoint).twice.and_return(transitioned_namespace)

      2.times { post_graphql_mutation(mutation, current_user: current_user) }

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['registry']).to include('status' => target_status)
    end

    it 'resolves a response with no status to unknown rather than a null-field error',
      :aggregate_failures do
      statusless = ArtifactRegistry::Namespace.new(
        'id' => mapping.ar_namespace_id, 'slug' => 'acme', 'created_at' => '2026-01-01T00:00:00Z'
      )
      allow(client).to receive(endpoint).and_return(statusless)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['registry']).to include('status' => 'unknown')
    end

    it 'returns the transitioned payload even when cache invalidation fails',
      :aggregate_failures do
      allow_next_found_instance_of(ArtifactRegistry::NamespaceMapping) do |instance|
        allow(instance).to receive(:expire_registry_cache).and_raise(StandardError, 'redis down')
      end
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(StandardError))

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['registry']).to include('status' => target_status)
    end

    context 'when userPermissions is selected on the payload' do
      let(:user_client) { instance_double(ArtifactRegistry::Client) }
      let(:verdicts) do
        ArtifactRegistry::Permissions::Verdicts.new(
          ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with { true },
          scope: :namespace, read: :namespace_details, slug: 'acme'
        )
      end

      let(:mutation) do
        graphql_mutation(mutation_name, {}, 'errors registry { slug userPermissions { createRepository } }')
      end

      before do
        allow(ArtifactRegistry::Client).to receive(:new)
          .with(current_user: current_user, organization: anything).and_return(user_client)
        allow(client).to receive(:namespace).and_return(transitioned_namespace)
        allow(user_client).to receive(:namespace_details)
          .with(slug: 'acme', include_permissions: true)
          .and_return(ArtifactRegistry::NamespaceDetails.new({ 'slug' => 'acme' }, verdicts))
      end

      it 'resolves the permissions against the organization the payload registry carries', :aggregate_failures do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['registry']).to eq(
          'slug' => 'acme', 'userPermissions' => { 'createRepository' => true }
        )
      end
    end

    context 'when the namespace is unknown to Artifact Registry (404)' do
      it 'surfaces a payload error rather than a top-level one', :aggregate_failures do
        allow(client).to receive(endpoint)
          .and_raise(ArtifactRegistry::Client::ApiError.new('namespace not found', status: 404, code: 'not_found'))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/not found/))
        expect(mutation_response['registry']).to be_nil
      end
    end

    context 'when Artifact Registry denies the transition (403)' do
      it 'renders a top-level not-available error' do
        allow(client).to receive(endpoint)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end

    context 'when Artifact Registry is unavailable (5xx)' do
      it 'renders a top-level service-unavailable error carrying the request ID', :aggregate_failures do
        allow(client).to receive(endpoint)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('boom', status: 503, request_id: 'req-9'))

        post_graphql_mutation(mutation, current_user: current_user)

        error = graphql_errors.find { |e| e['message'].include?('unavailable') }
        expect(error).to be_present
        expect(error.dig('extensions', 'request_id')).to eq('req-9')
      end
    end

    context 'when no service credential is wired (nil-status authorization failure)' do
      it 'renders service-unavailable and tracks the exception, not a permission error',
        :aggregate_failures do
        allow(client).to receive(endpoint)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('no credential'))
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)
          .with(instance_of(ArtifactRegistry::Client::AuthorizationError))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /unavailable/))
      end
    end

    context 'when the organization has no mapping row' do
      # An owner, so the update_organization gate passes and the not-available
      # error can only come from the missing mapping row, not from authorization.
      let_it_be(:current_organization) { create(:organization) }
      let_it_be(:current_user) { create(:organization_owner, organization: current_organization).user }

      it 'raises a top-level not-available error and builds no client', :aggregate_failures do
        expect(current_user.can?(:update_organization, current_organization)).to be(true)
        expect(ArtifactRegistry::Client).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end
  end

  # The flag is on by default in tests, so these deny paths exercise the
  # update_organization gate rather than the flag gate.
  context 'when the user holds only the read ability' do
    let(:current_user) { member }

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'makes no client call' do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: member)
    end
  end

  context 'when the user is not a member' do
    let(:current_user) { non_member }

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'makes no client call' do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: non_member)
    end
  end

  context 'when the request is unauthenticated' do
    it 'returns a top-level access error and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: nil)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    it_behaves_like 'a mutation that returns a top-level access error' do
      before do
        stub_feature_flags(artifact_registry_ui: false)
      end
    end

    it 'makes no client call' do
      stub_feature_flags(artifact_registry_ui: false)
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)
    end
  end
end
