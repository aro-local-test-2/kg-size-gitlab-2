# frozen_string_literal: true

# Drives the shared parts of project + group provision (task-based) worker
# specs.
#
# Including specs must provide:
# - `worker`                  -- described_class.new
# - `user`                    -- persisted user (referenced by maintenance_task.user)
# - `secrets_manager`         -- persisted SM record (returned by task.secrets_manager)
# - `maintenance_task`        -- persisted task with action: :provision
# - `provision_service_class` -- the scope-specific ProvisionService
# - `maintenance_task_class`  -- the scope-specific maintenance task model
# - `full_namespace_path`     -- the SM's full OpenBao namespace path
RSpec.shared_examples 'a secrets manager provision worker' do
  let(:service) { instance_double(provision_service_class, execute: ServiceResponse.success) }

  it 'runs the provision service via the task and destroys the task on success' do
    expect(maintenance_task_class)
      .to receive(:find_by_id).with(maintenance_task.id).and_return(maintenance_task)
    expect(provision_service_class).to receive(:new).with(secrets_manager, user).and_return(service)
    expect(maintenance_task).to receive(:destroy)

    worker.perform(maintenance_task.id)
  end

  it 'does not destroy the task when the service fails' do
    allow(maintenance_task_class).to receive(:find_by_id).and_return(maintenance_task)
    allow(provision_service_class).to receive(:new).and_return(service)
    allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'boom'))

    expect(maintenance_task).not_to receive(:destroy)

    worker.perform(maintenance_task.id)
  end

  context 'when the maintenance task is gone' do
    it 'returns without calling the service (idempotent)' do
      expect(provision_service_class).not_to receive(:new)
      expect { worker.perform(non_existing_record_id) }.not_to raise_error
    end
  end

  context 'when the maintenance task is for the wrong action' do
    let(:wrong_action_task) do
      instance_double(maintenance_task_class, id: maintenance_task.id, provision?: false)
    end

    before do
      allow(maintenance_task_class).to receive(:find_by_id).with(wrong_action_task.id).and_return(wrong_action_task)
    end

    it 'returns without calling the service' do
      expect(provision_service_class).not_to receive(:new)
      worker.perform(wrong_action_task.id)
    end
  end

  context 'when the secrets manager is gone' do
    before do
      allow(maintenance_task_class).to receive(:find_by_id).and_return(maintenance_task)
      allow(maintenance_task).to receive(:secrets_manager).and_return(nil)
    end

    it 'returns without calling the service' do
      expect(provision_service_class).not_to receive(:new)
      worker.perform(maintenance_task.id)
    end
  end

  context 'when the user is gone' do
    before do
      allow(maintenance_task_class).to receive(:find_by_id).and_return(maintenance_task)
      allow(maintenance_task).to receive(:user).and_return(nil)
    end

    it 'returns without calling the service' do
      expect(provision_service_class).not_to receive(:new)
      worker.perform(maintenance_task.id)
    end
  end

  # Provisioning activates the SM before the worker destroys the task. If only
  # the destroy fails, the cron retries the task against an active SM while
  # Owners may already have changed the default grants.
  context 'when only the task destroy fails after a successful provision' do
    let(:client) { secrets_manager_client.with_namespace(full_namespace_path) }
    let(:owner_policy_name) do
      secrets_manager.policy_name_for_principal(principal_type: 'Role', principal_id: Gitlab::Access::OWNER)
    end

    before do
      allow(maintenance_task_class).to receive(:find_by_id).with(maintenance_task.id).and_return(maintenance_task)
      allow(maintenance_task).to receive(:destroy).and_raise(ActiveRecord::StatementInvalid)
    end

    it 'retries without re-granting the removed default and clears the task', :aggregate_failures do
      expect { worker.perform(maintenance_task.id) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(secrets_manager.reload).to be_active

      client.delete_policy(owner_policy_name)
      allow(maintenance_task).to receive(:destroy).and_call_original

      worker.perform(maintenance_task.id)

      expect(maintenance_task_class.find_by(id: maintenance_task.id)).to be_nil
      expect(client.get_policy(owner_policy_name).paths).to be_empty
    end
  end
end
