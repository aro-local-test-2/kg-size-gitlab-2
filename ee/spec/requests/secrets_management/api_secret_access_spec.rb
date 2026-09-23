# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Secrets Manager non-CI API secret access', :gitlab_secrets_manager, feature_category: :secrets_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:owner) { create(:user, owner_of: project) }
  let_it_be(:reader) { create(:user) }

  let_it_be_with_reload(:project_secrets_manager) { create(:project_secrets_manager, project: project) }

  before_all do
    project.add_developer(reader)
  end

  before do
    provision_project_secrets_manager(project_secrets_manager, owner)
    create_project_secret(
      user: owner, project: project, name: 'db_password', branch: 'master', environment: '*', value: 'super-secret'
    )
  end

  def grant(user, actions)
    SecretsManagement::ProjectSecretsPermissions::UpdateService.new(project, owner).execute(
      principal_id: user.id,
      principal_type: 'User',
      actions: actions,
      expired_at: nil
    )
  end

  def read_value_via_api(user, secret_name)
    jwt = SecretsManagement::ProjectApiJwt.new(
      current_user: user, project: project, auth_via: 'personal_access_token'
    ).encoded

    client = SecretsManagement::TestClient.new(
      jwt: jwt,
      role: project_secrets_manager.api_auth_role,
      auth_mount: project_secrets_manager.api_auth_mount,
      use_cel_auth: true,
      auth_namespace: project_secrets_manager.full_project_namespace_path,
      namespace: project_secrets_manager.full_project_namespace_path
    )

    client.read_kv_secret_value(
      project_secrets_manager.ci_secrets_mount_path,
      project_secrets_manager.ci_data_path(secret_name)
    )
  end

  context 'when the principal is granted read_value' do
    before do
      grant(reader, %w[read_metadata read_value])
    end

    it 'reads the secret value through the API mount' do
      expect(read_value_via_api(reader, 'db_password')).to eq('super-secret')
    end
  end

  context 'when the principal is granted only read_metadata' do
    before do
      grant(reader, %w[read_metadata])
    end

    it 'cannot read the secret value' do
      expect { read_value_via_api(reader, 'db_password') }
        .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
    end
  end

  context 'when read_value is revoked' do
    before do
      grant(reader, %w[read_metadata read_value])
      grant(reader, %w[read_metadata])
    end

    it 'can no longer read the secret value' do
      expect { read_value_via_api(reader, 'db_password') }
        .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
    end
  end

  context 'when the principal has no secrets permission' do
    it 'cannot read the secret value' do
      expect { read_value_via_api(reader, 'db_password') }
        .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
    end
  end

  # Group principals were removed, but policies created before the removal can
  # still exist in OpenBao. Rails no longer sends the groups claim, so nothing
  # attaches them at login. These assert the denial at the mount for a member,
  # so a regression in the claim shows up as restored access.
  describe 'a leftover Group principal policy' do
    def grant_group(principal_group)
      create_legacy_group_policies(project_secrets_manager, principal_group.id, read_value: true)
    end

    context 'on the project mount, for a member of the project group' do
      let_it_be(:group_member) { create(:user) }

      before_all do
        group.add_developer(group_member)
      end

      before do
        grant_group(group)
      end

      it 'denies the value read' do
        expect { read_value_via_api(group_member, 'db_password') }
          .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
      end
    end

    context 'on the project mount, for a member of a group the project is shared with' do
      let_it_be(:shared_group) { create(:group) }
      let_it_be(:shared_group_member) { create(:user) }

      before_all do
        create(:project_group_link, :developer, project: project, group: shared_group)
        shared_group.add_developer(shared_group_member)
      end

      before do
        grant_group(shared_group)
      end

      it 'denies the value read' do
        expect { read_value_via_api(shared_group_member, 'db_password') }
          .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
      end
    end

    context 'on the project mount, for a member of a group shared into the project group' do
      let_it_be(:member_group) { create(:group) }
      let_it_be(:member_group_user) { create(:user) }

      before_all do
        create(:group_group_link, :developer, shared_group: group, shared_with_group: member_group)
        member_group.add_developer(member_group_user)
      end

      before do
        grant_group(group)
      end

      it 'denies the value read' do
        expect { read_value_via_api(member_group_user, 'db_password') }
          .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
      end
    end

    context 'on the group mount, for a member of the group' do
      let_it_be(:target_group) { create(:group) }
      let_it_be(:target_group_owner) { create(:user, owner_of: target_group) }
      let_it_be(:target_group_member) { create(:user, developer_of: target_group) }
      let_it_be(:target_secrets_manager, freeze: false) { create(:group_secrets_manager, group: target_group) }

      before do
        provision_group_secrets_manager(target_secrets_manager, target_group_owner)
        create_group_secret(
          user: target_group_owner, group: target_group, name: 'group_password',
          protected: false, environment: '*', value: 'group-super-secret'
        )
        create_legacy_group_policies(target_secrets_manager, target_group.id, read_value: true)
      end

      def read_group_value_via_api(user, secret_name)
        jwt = SecretsManagement::GroupApiJwt.new(
          current_user: user, group: target_group, auth_via: 'personal_access_token'
        ).encoded

        client = SecretsManagement::TestClient.new(
          jwt: jwt,
          role: target_secrets_manager.api_auth_role,
          auth_mount: target_secrets_manager.api_auth_mount,
          use_cel_auth: true,
          auth_namespace: target_secrets_manager.full_group_namespace_path,
          namespace: target_secrets_manager.full_group_namespace_path
        )

        client.read_kv_secret_value(
          target_secrets_manager.ci_secrets_mount_path,
          target_secrets_manager.ci_data_path(secret_name)
        )
      end

      it 'denies the value read' do
        expect { read_group_value_via_api(target_group_member, 'group_password') }
          .to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
      end
    end
  end

  describe 'minted OpenBao token TTL' do
    # Without lease_options in the CEL program, OpenBao would mint a token with
    # its 32-day default TTL, far outliving the 5-minute JWT. The CEL program
    # caps it to the 5-minute default instead.
    it 'defaults the project mount token TTL to 5 minutes' do
      api_jwt = SecretsManagement::ProjectApiJwt.new(
        current_user: reader, project: project, auth_via: 'personal_access_token'
      ).encoded

      response = secrets_manager_client
        .with_namespace(project_secrets_manager.full_project_namespace_path)
        .cel_login_jwt(
          mount_path: project_secrets_manager.api_auth_mount,
          role: project_secrets_manager.api_auth_role,
          jwt: api_jwt
        )

      expect(response.dig('auth', 'lease_duration')).to eq(300)
    end

    context 'for the group mount' do
      let_it_be(:group_owner) { create(:user, owner_of: group) }
      let_it_be_with_reload(:group_secrets_manager) { create(:group_secrets_manager, group: group) }

      before do
        provision_group_secrets_manager(group_secrets_manager, group_owner)
      end

      it 'defaults the group mount token TTL to 5 minutes' do
        group_api_jwt = SecretsManagement::GroupApiJwt.new(
          current_user: group_owner, group: group, auth_via: 'personal_access_token'
        ).encoded

        response = secrets_manager_client
          .with_namespace(group_secrets_manager.full_group_namespace_path)
          .cel_login_jwt(
            mount_path: group_secrets_manager.api_auth_mount,
            role: group_secrets_manager.api_auth_role,
            jwt: group_api_jwt
          )

        expect(response.dig('auth', 'lease_duration')).to eq(300)
      end
    end
  end
end
