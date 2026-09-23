# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Updating an Artifact Registry repository', feature_category: :artifact_registry do
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

  let(:repository_attributes) do
    {
      'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
      'name' => 'my-repo',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'Updated',
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'settings' => {}
    }
  end

  let(:updated_repository) { ArtifactRegistry::Repository.new(repository_attributes) }

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:input) do
    {
      'name' => 'my-repo',
      'visibility' => 'PRIVATE',
      'description' => 'Updated'
    }
  end

  let(:mutation) { graphql_mutation(:artifact_registry_repository_update, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_repository_update)
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

    it 'sends only the writable fields and returns the updated repository', :aggregate_failures do
      expect(client).to receive(:update_repository).with(
        slug: slug,
        name: 'my-repo',
        visibility: 'private',
        description: 'Updated'
      ).and_return(updated_repository)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to include(
        'id' => 'c3d4e5f6-0000-0000-0000-000000000000', 'name' => 'my-repo', 'description' => 'Updated'
      )
    end

    context 'when only one writable field is supplied' do
      let(:input) { { 'name' => 'my-repo', 'description' => 'Only description' } }

      it 'forwards just that field, leaving the omitted one untouched' do
        expect(client).to receive(:update_repository).with(
          slug: slug,
          name: 'my-repo',
          description: 'Only description'
        ).and_return(updated_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
      end
    end

    context 'when no writable field is supplied' do
      let(:input) { { 'name' => 'my-repo' } }

      it 'forwards only slug and name, and the client requires a mutable field', :aggregate_failures do
        expect(client).to receive(:update_repository).with(
          slug: slug,
          name: 'my-repo'
        ).and_raise(ArgumentError, 'at least one mutable field is required')

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => 'at least one mutable field is required'))
        expect(mutation_response).to be_nil
      end
    end

    context 'when visibility is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'visibility' => nil } }

      it 'rejects the argument rather than forwarding the null', :aggregate_failures do
        expect(client).not_to receive(:update_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "visibility can't be null"))
      end
    end

    context 'when description is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'description' => nil } }

      it 'forwards a nil description so Artifact Registry clears it' do
        expect(client).to receive(:update_repository).with(
          slug: slug,
          name: 'my-repo',
          description: nil
        ).and_return(updated_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
      end
    end

    context 'when settings is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'settings' => nil } }

      it 'rejects the argument rather than forwarding the null', :aggregate_failures do
        expect(client).not_to receive(:update_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "settings can't be null"))
      end
    end

    context 'when settings are supplied' do
      let(:repository_attributes) { super().merge('kind' => 'remote', 'settings' => settings_response) }

      let(:remote_repository) { ArtifactRegistry::Repository.new(repository_attributes) }

      let(:settings_response) do
        {
          'url' => 'https://upstream.test',
          'cache_validity_hours' => 24,
          'has_credentials' => true,
          'last_health_status' => 'healthy',
          'last_health_checked_at' => nil
        }
      end

      let(:input) { { 'name' => 'my-repo', 'settings' => settings_input } }

      where(:case_name, :settings_input, :forwarded) do
        'a cache window change' | { 'cacheValidityHours' => 48 } | { cache_validity_hours: 48 }
        'a credential rotation' | { 'credentials' => { 'username' => 'robot', 'password' => 'secret' } } |
          { credentials: { username: 'robot', password: 'secret' } }
        'a credential clear'    | { 'credentials' => nil } | { credentials: nil }
      end

      with_them do
        it 'sends only the supplied field' do
          expect(client).to receive(:update_repository).with(
            slug: slug,
            name: 'my-repo',
            settings: forwarded
          ).and_return(remote_repository)

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
        end
      end

      context 'when the URL changes' do
        let(:settings_input) { { 'url' => 'https://other.test' } }

        it 'sends the URL alone' do
          expect(client).to receive(:update_repository).with(
            slug: slug,
            name: 'my-repo',
            settings: { url: 'https://other.test' }
          ).and_return(remote_repository)

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
        end

        context 'when the change cleared the stored credentials' do
          let(:settings_response) { super().merge('credentials_cleared' => true) }

          it 'surfaces the signal Artifact Registry sent inside the settings' do
            allow(client).to receive(:update_repository).and_return(remote_repository)

            post_graphql_mutation(mutation, current_user: current_user)

            expect(mutation_response['repository']['settings']).to include('credentialsCleared' => true)
          end
        end

        context 'when Artifact Registry reported no clear' do
          it 'resolves the signal null' do
            allow(client).to receive(:update_repository).and_return(remote_repository)

            post_graphql_mutation(mutation, current_user: current_user)

            expect(mutation_response['repository']['settings']['credentialsCleared']).to be_nil
          end
        end
      end
    end

    context 'when the repository is absent (update 404)' do
      it 'surfaces a payload not-found error rather than a top-level error', :aggregate_failures do
        allow(client).to receive(:update_repository)
          .and_raise(ArtifactRegistry::Client::ApiError.new('repository not found', status: 404, code: 'not_found'))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/not found/))
      end
    end

    context 'when Artifact Registry denies the update (403)' do
      it 'renders a top-level ResourceNotAvailable' do
        allow(client).to receive(:update_repository)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end
  end

  # No client stub needed: this asserts the schema shape, independent of any request.
  # `name` is present as identity only, and format is absent entirely.
  it 'exposes exactly the identity and writable arguments, and no format' do
    input_type = GitlabSchema.types['ArtifactRegistryRepositoryUpdateInput']

    expect(input_type.arguments.keys).to match_array(%w[clientMutationId name visibility description settings])
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
