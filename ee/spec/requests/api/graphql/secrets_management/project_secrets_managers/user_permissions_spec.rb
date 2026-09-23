# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projectSecretsManager userPermissions', :gitlab_secrets_manager, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project) }
  # `let`, not `let_it_be`: provisioning mutates the record, and a frozen
  # `let_it_be` record raises FrozenError in the provision service.
  let(:project_secrets_manager) { create(:project_secrets_manager, project: project) }
  let_it_be(:owner) { create(:user, owner_of: project) }

  let(:current_user) { create(:user) }

  let(:query) do
    graphql_query_for(
      'projectSecretsManager',
      { project_path: project.full_path },
      <<~FIELDS
        userPermissions {
          readMetadata
          createSecrets
          updateSecrets
          deleteSecrets
        }
      FIELDS
    )
  end

  before do
    provision_project_secrets_manager(project_secrets_manager, owner)
  end

  subject(:post_query) { post_graphql(query, current_user: current_user) }

  def permissions
    graphql_data_at(:project_secrets_manager, :user_permissions)
  end

  # Stubs the resolver's OpenBao client so capabilities-self raises. We stub the
  # service rather than SecretsManagerClient.new: wrapping `.new` leaks into the
  # spec cleanup, which builds a TestClient and would inherit the stubbed `.new`.
  def stub_capabilities_self_error(error_class, message)
    allow_next_instance_of(SecretsManagement::UserPermissions::ProjectEffectiveCapabilitiesService) do |service|
      failing_client = instance_double(SecretsManagement::SecretsManagerClient)
      allow(failing_client).to receive(:capabilities_self).and_raise(error_class, message)
      allow(service).to receive(:user_scoped_client).and_return(failing_client)
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_secrets_manager do
    let(:user) { create(:user, maintainer_of: project) }
    let(:boundary_object) { project }
    # Query a data field, not userPermissions: permission-metadata types are
    # not readable by granular tokens (they carry no directive by design).
    let(:query) do
      graphql_query_for('projectSecretsManager', { project_path: project.full_path }, 'status')
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  context 'when current user is a guest' do
    let(:current_user) { create(:user, guest_of: project) }

    it 'returns a top-level access error' do
      post_query

      expect_graphql_errors_to_include(/you don't have permission/i)
    end
  end

  context 'when current user has no OpenBao grant (Reporter role)' do
    let(:current_user) { create(:user, reporter_of: project) }

    it 'returns false for all permissions' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when current user has no OpenBao grant (Developer role)' do
    let(:current_user) { create(:user, developer_of: project) }

    it 'returns false for all permissions' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when current user has the default Maintainer role grant' do
    let(:current_user) { create(:user, maintainer_of: project) }

    it 'returns readMetadata, createSecrets and updateSecrets true and deleteSecrets false' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => true,
        'updateSecrets' => true,
        'deleteSecrets' => false
      )
    end

    context 'when an owner removes the Maintainer role grant' do
      before do
        SecretsManagement::ProjectSecretsPermissions::DeleteService.new(project, owner)
          .execute(principal_id: Gitlab::Access::MAINTAINER, principal_type: 'Role')
      end

      it 'returns false for all permissions' do
        post_query

        expect(permissions).to eq(
          'readMetadata' => false,
          'createSecrets' => false,
          'updateSecrets' => false,
          'deleteSecrets' => false
        )
      end
    end

    context 'when an owner downgrades the Maintainer role grant to read only' do
      before do
        update_project_secrets_permission(
          user: owner,
          project: project,
          actions: %w[read],
          principal: { id: Gitlab::Access::MAINTAINER, type: 'Role' }
        )
      end

      it 'returns readMetadata=true and others false' do
        post_query

        expect(permissions).to eq(
          'readMetadata' => true,
          'createSecrets' => false,
          'updateSecrets' => false,
          'deleteSecrets' => false
        )
      end
    end
  end

  context 'when current user has read-only OpenBao grant' do
    let(:current_user) { create(:user, reporter_of: project) }

    before do
      update_project_secrets_permission(
        user: owner,
        project: project,
        actions: %w[read],
        principal: { id: current_user.id, type: 'User' }
      )
    end

    it 'returns readMetadata=true and others false' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when current user has read+write OpenBao grant' do
    let(:current_user) { create(:user, developer_of: project) }

    before do
      update_project_secrets_permission(
        user: owner,
        project: project,
        actions: %w[read write],
        principal: { id: current_user.id, type: 'User' }
      )
    end

    it 'returns read/create/update=true and deleteSecrets=false' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => true,
        'updateSecrets' => true,
        'deleteSecrets' => false
      )
    end

    it 'resolves all four sub-fields with a single OpenBao capabilities call' do
      # Regression guard: the four permission_field resolvers share
      # `effective_capabilities` via strong_memoize, so selecting all four
      # must still result in one capabilities-self round-trip.
      expect_next_instance_of(SecretsManagement::UserPermissions::ProjectEffectiveCapabilitiesService) do |service|
        expect(service).to receive(:execute).once.and_call_original
      end

      post_query
    end
  end

  context 'when current user has read+write+delete OpenBao grant' do
    let(:current_user) { create(:user, maintainer_of: project) }

    before do
      update_project_secrets_permission(
        user: owner,
        project: project,
        actions: %w[read write delete],
        principal: { id: current_user.id, type: 'User' }
      )
    end

    it 'returns true for all permissions' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => true,
        'updateSecrets' => true,
        'deleteSecrets' => true
      )
    end
  end

  context 'when current user has a grant via Role principal' do
    let(:current_user) { create(:user, developer_of: project) }

    before do
      update_project_secrets_permission(
        user: owner,
        project: project,
        actions: %w[read write],
        principal: { id: Gitlab::Access.sym_options[:developer], type: 'Role' }
      )
    end

    it 'unions role grant into effective capabilities' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => true,
        'updateSecrets' => true,
        'deleteSecrets' => false
      )
    end
  end

  context 'when current user has an expired grant' do
    let(:current_user) { create(:user, developer_of: project) }

    before do
      update_project_secrets_permission(
        user: owner,
        project: project,
        actions: %w[read write delete],
        principal: { id: current_user.id, type: 'User' },
        expired_at: 1.hour.from_now.iso8601
      )

      expire_secrets_permission_grant!(project_secrets_manager.full_project_namespace_path, current_user)
    end

    it 'treats expired grant as no grant (all false)' do
      post_query

      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when OpenBao is unreachable' do
    let(:current_user) { create(:user, maintainer_of: project) }

    before do
      stub_capabilities_self_error(SecretsManagement::SecretsManagerClient::ApiError, 'connection refused')
    end

    it 'returns false for all permissions without raising a top-level GraphQL error' do
      post_query

      expect(graphql_errors).to be_nil
      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when a leftover Group principal policy exists' do
    let_it_be(:group) { create(:group) }
    let_it_be(:group_project) { create(:project, group: group) }
    let(:group_project_secrets_manager) { create(:project_secrets_manager, project: group_project) }
    let_it_be(:group_owner) { create(:user, owner_of: group) }
    let_it_be(:current_user) { create(:user) }

    let(:query) do
      graphql_query_for(
        'projectSecretsManager',
        { project_path: group_project.full_path },
        <<~FIELDS
          userPermissions {
            readMetadata
            createSecrets
            updateSecrets
            deleteSecrets
          }
        FIELDS
      )
    end

    before_all do
      group.add_developer(current_user)
    end

    before do
      provision_project_secrets_manager(group_project_secrets_manager, group_owner)

      create_legacy_group_policies(group_project_secrets_manager, group.id)
    end

    # Group principals were removed. A policy left in OpenBao never attaches,
    # because the JWT no longer carries a groups claim.
    it 'does not grant any capability through the group policy' do
      post_graphql(query, current_user: current_user)

      group_permissions = graphql_data_at(:project_secrets_manager, :user_permissions)

      expect(group_permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when OpenBao raises a non-ApiError failure (ConnectionError)' do
    let(:current_user) { create(:user, maintainer_of: project) }

    before do
      stub_capabilities_self_error(SecretsManagement::SecretsManagerClient::ConnectionError, 'connection timed out')
    end

    it 'returns false for all permissions without raising a top-level GraphQL error' do
      post_query

      expect(graphql_errors).to be_nil
      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  context 'when OpenBao raises ServiceUnavailableError' do
    let(:current_user) { create(:user, maintainer_of: project) }

    before do
      stub_capabilities_self_error(SecretsManagement::SecretsManagerClient::ServiceUnavailableError,
        'service unavailable')
    end

    it 'returns false for all permissions without raising a top-level GraphQL error' do
      post_query

      expect(graphql_errors).to be_nil
      expect(permissions).to eq(
        'readMetadata' => false,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end
  end

  # `readOnly` must stay reachable while the instance is read-only: the read-only
  # middleware allowlists GraphQL POSTs, and only mutations are refused. The
  # frontend relies on this query to render the maintenance banner.
  context 'when the instance is read-only (maintenance mode)' do
    let(:current_user) { create(:user, maintainer_of: project) }

    let(:query) do
      graphql_query_for(
        'projectSecretsManager',
        { project_path: project.full_path },
        <<~FIELDS
          readOnly
          userPermissions {
            readMetadata
            createSecrets
            updateSecrets
            deleteSecrets
          }
        FIELDS
      )
    end

    before do
      stub_maintenance_mode_setting(true)
    end

    it 'returns readOnly true and zeroes every write while keeping reads', :aggregate_failures do
      post_query

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project_secrets_manager, :read_only)).to be(true)
      expect(permissions).to eq(
        'readMetadata' => true,
        'createSecrets' => false,
        'updateSecrets' => false,
        'deleteSecrets' => false
      )
    end

    context 'when maintenance mode is turned off again' do
      before do
        stub_maintenance_mode_setting(false)
      end

      it 'returns readOnly false and the OpenBao capabilities' do
        post_query

        expect(graphql_data_at(:project_secrets_manager, :read_only)).to be(false)
        expect(permissions).to include('createSecrets' => true, 'updateSecrets' => true)
      end
    end
  end
end
