# frozen_string_literal: true

# Including specs must provide:
# - `result`               -- `service.execute` (a subject)
# - `secrets_manager`      -- the SM record being provisioned
# - `user`                 -- the provisioning user
# - `full_namespace_path`  -- the SM's full OpenBao namespace path
# - `privileged_jwt_class` -- the JWT class the base service builds for OpenBao calls
# - `payload_key`          -- the ServiceResponse payload key for the SM
RSpec.shared_context 'with secrets manager default role policies' do
  let(:client) { secrets_manager_client.with_namespace(full_namespace_path) }
  let(:data_path) { secrets_manager.ci_full_path('*') }
  let(:metadata_path) { secrets_manager.ci_metadata_full_path('*') }
  let(:detailed_metadata_path) { secrets_manager.detailed_metadata_path('*') }

  # Fail loudly here so the negative examples below cannot pass because
  # provisioning never wrote anything.
  before do
    raise "provisioning failed: #{result.message}" unless result.success?
  end

  def role_policy_name(access_level)
    secrets_manager.policy_name_for_principal(principal_type: 'Role', principal_id: access_level)
  end

  def role_policy(access_level)
    client.get_policy(role_policy_name(access_level))
  end
end

RSpec.shared_examples 'a secrets manager provision service' do
  describe 'default role policies' do
    include_context 'with secrets manager default role policies'

    it 'grants the Owner role full management access', :aggregate_failures do
      policy = role_policy(Gitlab::Access::OWNER)

      expect(policy.paths[data_path].capabilities).to contain_exactly('create', 'update', 'delete', 'list', 'scan')
      expect(policy.paths[metadata_path].capabilities)
        .to contain_exactly('create', 'update', 'delete', 'read', 'list', 'scan')
      expect(policy.paths[detailed_metadata_path].capabilities).to contain_exactly('list')
    end

    it 'does not grant the Developer role a default policy' do
      expect_policy_not_to_exist(full_namespace_path, role_policy_name(Gitlab::Access::DEVELOPER))
    end

    context 'when provisioning is retried after activation and a default grant was removed' do
      before do
        client.delete_policy(role_policy_name(Gitlab::Access::OWNER))

        described_class.new(secrets_manager.reload, user).execute
      end

      it 'does not re-grant the removed default' do
        expect_policy_not_to_exist(full_namespace_path, role_policy_name(Gitlab::Access::OWNER))
      end
    end
  end

  context 'when the secrets manager is already active' do
    before do
      secrets_manager.activate!
    end

    it 'returns success without touching OpenBao', :aggregate_failures do
      expect(privileged_jwt_class).not_to receive(:new)

      expect(result).to be_success
      expect(result.payload[payload_key]).to eq(secrets_manager)
      expect(secrets_manager.reload).to be_active
    end

    # A lapsed entitlement must not turn a retried provision task into a
    # permanent failure, so the active check has to come before the gate.
    context 'when the entitlement is blocked' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        allow(SecretsManagement::Entitlement).to receive(:for).and_return(
          SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :grace)
        )
      end

      it 'still returns success' do
        expect(result).to be_success
      end
    end
  end
end

RSpec.shared_examples 'a secrets manager provision service granting the Maintainer default' do
  describe 'Maintainer default role policy' do
    include_context 'with secrets manager default role policies'

    it 'grants create, update and metadata read but not delete', :aggregate_failures do
      policy = role_policy(Gitlab::Access::MAINTAINER)

      expect(policy.paths[data_path].capabilities).to contain_exactly('create', 'update', 'list', 'scan')
      expect(policy.paths[metadata_path].capabilities).to contain_exactly('create', 'update', 'read', 'list', 'scan')
      expect(policy.paths[detailed_metadata_path].capabilities).to contain_exactly('list')
    end
  end
end

RSpec.shared_examples 'a secrets manager provision service not granting the Maintainer default' do
  describe 'Maintainer default role policy' do
    include_context 'with secrets manager default role policies'

    it 'does not grant the Maintainer role a default policy' do
      expect_policy_not_to_exist(full_namespace_path, role_policy_name(Gitlab::Access::MAINTAINER))
    end
  end
end
