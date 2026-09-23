# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating an Artifact Registry repository', feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }

  let(:slug) { 'resolved-handle' }
  let(:namespace) do
    ArtifactRegistry::Namespace.new('id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active')
  end

  let(:repository_attributes) do
    {
      'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
      'name' => 'my-repo',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A repo',
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'settings' => {}
    }
  end

  let(:created_repository) { ArtifactRegistry::Repository.new(repository_attributes) }

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:input) do
    {
      'name' => 'my-repo',
      'format' => 'MAVEN',
      'visibility' => 'PRIVATE',
      'description' => 'A repo'
    }
  end

  let(:mutation) { graphql_mutation(:artifact_registry_repository_create, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_repository_create)
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

    it 'creates the repository and returns it with no errors', :aggregate_failures do
      expect(client).to receive(:create_repository).with(
        slug: slug,
        name: 'my-repo',
        format: 'maven',
        kind: nil,
        visibility: 'private',
        description: 'A repo',
        settings: nil
      ).and_return(created_repository)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to include(
        'id' => 'c3d4e5f6-0000-0000-0000-000000000000', 'name' => 'my-repo', 'description' => 'A repo'
      )
    end

    context 'when Artifact Registry rejects the name (duplicate or invalid)' do
      it 'surfaces the error in the payload errors', :aggregate_failures do
        allow(client).to receive(:create_repository)
          .and_raise(ArtifactRegistry::Client::ApiError.new('name has already been taken', status: 409))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to include(a_string_matching(/already been taken/))
        expect(mutation_response['repository']).to be_nil
      end
    end

    context 'when Artifact Registry denies the create (403)' do
      it 'renders a top-level ResourceNotAvailable' do
        allow(client).to receive(:create_repository)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end

    context 'when an optional enum argument is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'visibility' => nil } }

      it 'rejects the argument rather than dropping the null', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "visibility can't be null"))
      end
    end

    context 'when settings is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'settings' => nil } }

      it 'rejects the argument rather than forwarding the null', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "settings can't be null"))
      end
    end

    context 'when creating a remote repository' do
      let(:repository_attributes) do
        super().merge(
          'kind' => 'remote',
          'settings' => {
            'url' => 'https://upstream.test',
            'cache_validity_hours' => 24,
            'metadata_cache_validity_hours' => 1,
            'has_credentials' => false,
            'last_health_status' => 'unknown',
            'last_health_checked_at' => nil
          }
        )
      end

      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'MAVEN',
          'kind' => 'REMOTE',
          'settings' => {
            'url' => 'https://upstream.test',
            'cacheValidityHours' => 24,
            'metadataCacheValidityHours' => 1
          }
        }
      end

      it 'sends the kind and the writable settings, and returns the created settings', :aggregate_failures do
        expect(client).to receive(:create_repository).with(
          hash_including(
            kind: 'remote',
            settings: { url: 'https://upstream.test', cache_validity_hours: 24, metadata_cache_validity_hours: 1 }
          )
        ).and_return(created_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']['settings']).to include(
          'url' => 'https://upstream.test',
          'cacheValidityHours' => 24,
          'metadataCacheValidityHours' => 1,
          'hasCredentials' => false
        )
      end

      context 'when credentials are supplied' do
        let(:input) do
          super().merge('settings' => { 'url' => 'https://upstream.test',
                                        'credentials' => { 'username' => 'robot', 'password' => 'secret' } })
        end

        it 'forwards the credential object' do
          expect(client).to receive(:create_repository).with(
            hash_including(settings: { url: 'https://upstream.test',
                                       credentials: { username: 'robot', password: 'secret' } })
          ).and_return(created_repository)

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
        end
      end
    end

    context 'when a metadata cache window is sent on a container format' do
      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'DOCKER',
          'kind' => 'REMOTE',
          'settings' => { 'url' => 'https://upstream.test', 'metadataCacheValidityHours' => 1 }
        }
      end

      it 'reaches Artifact Registry rather than being dropped, and its rejection surfaces' do
        expect(client).to receive(:create_repository)
          .with(hash_including(settings: hash_including(metadata_cache_validity_hours: 1)))
          .and_raise(
            ArtifactRegistry::Client::ApiError.new('unknown field metadata_cache_validity_hours', status: 400)
          )

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include(a_string_matching(/metadata_cache_validity_hours/))
      end
    end

    context 'when a non-hosted kind is requested' do
      let(:input) do
        { 'name' => 'my-repo', 'format' => 'MAVEN', 'kind' => 'VIRTUAL' }
      end

      it 'passes the kind through to Artifact Registry and surfaces its rejection', :aggregate_failures do
        expect(client).to receive(:create_repository)
          .with(hash_including(kind: 'virtual'))
          .and_raise(ArtifactRegistry::Client::ApiError.new('kind not supported', status: 422))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include(a_string_matching(/not supported/))
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
