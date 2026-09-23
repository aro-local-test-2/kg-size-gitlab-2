# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Activating an Artifact Registry', :use_clean_rails_memory_store_caching, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be_with_reload(:current_organization) { create(:organization) }
  let_it_be(:billing_group) { create(:group, organization: current_organization) }
  let_it_be(:owner) { create(:organization_owner, organization: current_organization).user }
  let_it_be(:member) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:handle) { 'my-handle' }
  let(:ar_namespace) do
    ArtifactRegistry::Namespace.new(
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'slug' => handle,
      'status' => 'active',
      'created_at' => '2026-01-01T00:00:00Z'
    )
  end

  let(:client) { instance_double(ArtifactRegistry::Client) }
  let(:input) { { 'slug' => handle } }
  let(:mutation) { graphql_mutation(:artifact_registry_activate, input, nil, ['userPermissions']) }
  let(:current_user) { owner }

  def mutation_response
    graphql_mutation_response(:artifact_registry_activate)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      # current_organization is let_it_be and memoizes its client, so a doubled
      # client would otherwise leak across examples. CachesClient memoizes under
      # :artifact_registry_client, so that is the key to clear.
      current_organization.clear_memoization(:artifact_registry_client)
      allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive(:provision_namespace).and_return(ar_namespace)
    end

    it 'provisions the registry from the fetched namespace with no read-back', :aggregate_failures do
      expect(client).to receive(:provision_namespace).with(
        slug: handle,
        platform: 'gitlab',
        entity_type: 'organization',
        entity_id: current_organization.uuid,
        billing_entity_type: 'group',
        billing_entity_id: billing_group.id
      ).and_return(ar_namespace)
      # The provisioned namespace already carries slug/status/created_at, so the
      # mutation must not issue a second GET to read the new row back.
      expect(client).not_to receive(:namespace)

      expect { post_graphql_mutation(mutation, current_user: owner) }
        .to change { current_organization.reload.artifact_registry_namespace_mapping }.from(nil)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['registry']).to include(
        'id' => ar_namespace.id, 'slug' => handle, 'status' => 'active'
      )
    end

    context 'when userPermissions is selected on the payload' do
      let(:mutation) do
        graphql_mutation(
          :artifact_registry_activate, input, 'errors registry { slug userPermissions { createRepository } }'
        )
      end

      let(:verdicts) do
        ArtifactRegistry::Permissions::Verdicts.new(
          ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with { true },
          scope: :namespace, read: :namespace_details, slug: handle
        )
      end

      before do
        allow(client).to receive(:namespace).and_return(ar_namespace)
        allow(client).to receive(:namespace_details)
          .with(slug: handle, include_permissions: true)
          .and_return(ArtifactRegistry::NamespaceDetails.new({ 'slug' => handle }, verdicts))
      end

      it 'resolves the permissions against the organization the payload registry carries', :aggregate_failures do
        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['registry']).to eq(
          'slug' => handle, 'userPermissions' => { 'createRepository' => true }
        )
      end
    end

    context 'when Artifact Registry rejects the handle as taken (409)' do
      it 'returns a payload error and writes no row', :aggregate_failures do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::ApiError.new('handle has already been taken', status: 409))

        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to include(a_string_matching(/already been taken/))
        expect(mutation_response['registry']).to be_nil
        expect(current_organization.reload.artifact_registry_namespace_mapping).to be_nil
      end
    end

    context 'when the slug breaks a syntactic rule' do
      let(:input) { { 'slug' => 'A' } }

      it 'returns the syntactic refusal and makes no client call', :aggregate_failures do
        expect(client).not_to receive(:provision_namespace)

        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to include(a_string_matching(/between 3 and 63 characters/))
        expect(mutation_response['registry']).to be_nil
      end
    end

    context 'when the organization has no top-level group' do
      let_it_be(:current_organization) { create(:organization) }
      let_it_be(:owner) { create(:organization_owner, organization: current_organization).user }

      it 'returns the no-anchor refusal and makes no client call', :aggregate_failures do
        expect(client).not_to receive(:provision_namespace)

        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to include(a_string_matching(/no top-level groups/))
        expect(mutation_response['registry']).to be_nil
      end
    end

    context 'when the organization has several top-level groups' do
      let_it_be(:second_group) { create(:group, organization: current_organization) }

      it 'returns the ambiguous-anchor refusal and makes no client call', :aggregate_failures do
        expect(client).not_to receive(:provision_namespace)

        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to include(a_string_matching(/more than one top-level group/))
        expect(mutation_response['registry']).to be_nil
      end
    end

    context 'when the organization is already activated' do
      let_it_be(:existing_mapping) do
        create(:artifact_registry_namespace_mapping, organization: current_organization)
      end

      let(:existing_namespace) do
        ArtifactRegistry::Namespace.new(
          'id' => existing_mapping.ar_namespace_id, 'slug' => 'existing-slug',
          'status' => 'active', 'created_at' => '2026-01-01T00:00:00Z'
        )
      end

      let(:input) { { 'slug' => 'a-different-slug' } }

      before do
        allow(client).to receive(:namespace).and_return(existing_namespace)
      end

      it 'resolves the existing registry without calling Artifact Registry to provision', :aggregate_failures do
        expect(client).not_to receive(:provision_namespace)

        post_graphql_mutation(mutation, current_user: owner)

        expect(mutation_response['errors']).to be_empty
        # The service is idempotent on an existing mapping, so it returns the
        # already-claimed slug rather than the different one requested here.
        expect(mutation_response['registry']).to include('slug' => 'existing-slug')
      end
    end

    context 'when Artifact Registry is unavailable (503)' do
      it 'raises service-unavailable carrying the message and writes no registry', :aggregate_failures do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('registry timed out', status: 503))

        post_graphql_mutation(mutation, current_user: owner)

        expect(graphql_errors).to include(a_hash_including('message' => a_string_matching(/unavailable/)))
        expect(mutation_response).to be_nil
      end
    end

    context 'when a namespace read-back would fail after provisioning' do
      it 'still succeeds and keeps the row, since it reads no status back', :aggregate_failures do
        # A broken read-back must not turn a claimed slug into a visible failure:
        # the mutation builds the registry from the provisioned namespace instead.
        allow(client).to receive(:namespace)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('status read failed', status: 503))

        expect { post_graphql_mutation(mutation, current_user: owner) }
          .to change { current_organization.reload.artifact_registry_namespace_mapping }.from(nil)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['registry']).to include('slug' => handle, 'status' => 'active')
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

    context 'when the user holds only the read ability' do
      let(:current_user) { member }

      it_behaves_like 'a mutation that returns a top-level access error'

      it 'makes no client call' do
        expect(ArtifactRegistry::Client).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: member)
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'raises a top-level ResourceNotAvailable and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: owner)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end
end
