# frozen_string_literal: true

RSpec.shared_examples 'a service for deleting secrets permissions' do |resource_type|
  # Note: The including spec must define:
  # - service (the service instance)
  # - resource (the project or group)
  # - user (a user who is a member of the resource)
  # - secrets_manager (the secrets manager instance)
  # - provision_secrets_manager (method to provision the secrets manager)
  # - update_permission (method to setup and create the permission to delete)
  # - full_namespace_path (full project/group namespace path)

  let(:principal_id) { user.id }
  let(:principal_type) { 'User' }

  subject(:result) { service.execute(principal_id: principal_id, principal_type: principal_type) }

  describe '#execute' do
    context "when the #{resource_type} secrets manager is active" do
      before do
        provision_secrets_manager(secrets_manager, user)
      end

      context 'when the permission exists' do
        before do
          # Create a permission to delete
          update_permission(
            user: user,
            actions: %w[write read],
            principal: { id: principal_id, type: principal_type }
          )
        end

        it 'deletes a secrets permission successfully' do
          # Verify permission exists before deletion
          policy_name = secrets_manager.policy_name_for_principal(
            principal_type: principal_type,
            principal_id: principal_id
          )

          namespace_path = full_namespace_path

          expect_policy_to_exist(namespace_path, policy_name)

          # Delete the permission
          expect(result).to be_success
          expect(result.payload[:secrets_permission]).to be_nil

          # Verify permission is deleted from OpenBao
          expect_policy_not_to_exist(namespace_path, policy_name)
        end

        it 'expires the cached capabilities of the user' do
          expect(SecretsManagement::UserPermissions::EffectiveCapabilitiesService)
            .to receive(:expire_for_user).with(secrets_manager: secrets_manager, user_id: user.id)

          expect(result).to be_success
        end

        it_behaves_like "an operation requiring an exclusive #{resource_type} secret operation lease"
      end

      context 'when the principal is a role' do
        let(:principal_type) { 'Role' }
        let(:principal_id) { Gitlab::Access::MAINTAINER }

        before do
          update_permission(user: user, actions: %w[read], principal: { id: principal_id, type: principal_type })
        end

        # A role grant fans out to every member holding it, so the cache is left to expire.
        it 'does not expire any cached capabilities' do
          expect(SecretsManagement::UserPermissions::EffectiveCapabilitiesService).not_to receive(:expire_for_user)

          expect(result).to be_success
        end
      end

      context 'when the permission grants read_value' do
        let(:api_policy_name) do
          secrets_manager.api_policy_name_for_principal(
            principal_type: principal_type,
            principal_id: principal_id
          )
        end

        before do
          update_permission(
            user: user,
            actions: %w[read write read_value],
            principal: { id: principal_id, type: principal_type }
          )
        end

        it 'also removes the read-only API policy' do
          expect_policy_to_exist(full_namespace_path, api_policy_name)

          expect(result).to be_success

          expect_policy_not_to_exist(full_namespace_path, api_policy_name)
        end
      end

      context 'when the permission does not exist' do
        it 'does nothing but returns successfully' do
          # Verify permission exists before deletion
          policy_name = secrets_manager.policy_name_for_principal(
            principal_type: principal_type,
            principal_id: principal_id
          )

          namespace_path = full_namespace_path

          expect_policy_not_to_exist(namespace_path, policy_name)

          # Attempt to delete the non-existing permission
          expect(result).to be_success
          expect(result.payload[:secret_permission]).to be_nil
        end
      end

      context 'when principal-id format is invalid' do
        let(:principal_id) { '35sds' }

        it 'returns an error' do
          expect(result).to be_error
          expect(result.message).to eq('Invalid principal')
        end
      end

      context 'when principal-type format is invalid' do
        let(:principal_type) { 'TestModel' }

        it 'returns an error' do
          expect(result).to be_error
          expect(result.message).to eq('Invalid principal')
        end
      end

      context 'when principal type is the removed Group' do
        let(:principal_type) { 'Group' }
        let(:principal_id) { create(:group).id }

        it 'returns an error and leaves any leftover policy untouched' do
          create_legacy_group_policies(secrets_manager, principal_id)

          expect(result).to be_error
          expect(result.message).to eq('Invalid principal')
          expect_policy_to_exist(full_namespace_path, "users/direct/group_#{principal_id}")
        end
      end
    end

    context "when the #{resource_type} secrets manager is not active" do
      it 'returns an error' do
        expect(result).to be_error
        expect(result.message).to eq("Secrets manager is not active")
      end
    end
  end
end
