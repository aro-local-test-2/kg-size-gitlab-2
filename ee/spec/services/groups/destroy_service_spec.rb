# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::DestroyService, feature_category: :groups_and_projects do
  include ::EE::GeoHelpers

  let_it_be(:user, freeze: false) { create(:user) }
  let!(:group) { create(:group) }

  before do
    group.add_owner(user)
  end

  subject(:service) { described_class.new(group, user, {}) }

  context 'audit events' do
    include_examples 'audit event logging' do
      let(:operation) { service.execute }
      let(:fail_condition!) do
        expect(group).to receive(:destroy).and_return(group)
      end

      let_it_be(:event_type, freeze: false) { 'group_destroyed' }

      let(:attributes) do
        {
          author_id: user.id,
          entity_id: group.id,
          entity_type: 'Group',
          details: {
            remove: 'group',
            author_name: user.name,
            author_class: user.class.name,
            event_name: "group_destroyed",
            target_id: group.id,
            target_type: 'Group',
            target_details: group.full_path,
            custom_message: 'Group destroyed'
          }
        }
      end
    end
  end

  context 'streaming audit event for sub group' do
    let_it_be(:parent_group, freeze: false) { create :group }
    let(:group) { create :group, parent: parent_group }

    subject(:result) { described_class.new(group, user, {}).execute }

    before_all do
      parent_group.add_owner(user)
    end

    before do
      stub_licensed_features(external_audit_events: true)
      create(:audit_events_group_external_streaming_destination, group: parent_group)
    end

    it 'sends the audit streaming event with json format' do
      expect(AuditEvents::AuditEventStreamingWorker).to receive(:perform_async).with(
        'group_destroyed',
        nil,
        a_string_including("group_entity_id\":#{parent_group.id}"))

      result
    end
  end

  context 'dependency_proxy_blobs' do
    let_it_be(:blob, freeze: false) { create(:dependency_proxy_blob) }
    let_it_be(:group, freeze: false) { blob.group }

    before_all do
      group.add_owner(user)
    end

    it 'destroys the dependency proxy blobs' do
      expect { service.execute }.to change { DependencyProxy::Blob.count }.by(-1)
    end
  end

  context 'when on a Geo primary site' do
    let_it_be(:geo_primary_site, freeze: false) { create(:geo_node, :primary) }

    before do
      stub_current_geo_node(geo_primary_site)
    end

    context 'when group_wiki_repository does not exist' do
      it 'does not call replicator to update Geo' do
        expect_next_instance_of(Geo::GroupWikiRepositoryReplicator).never

        service.execute
      end
    end

    it 'calls replicator to update Geo' do
      group.wiki.create_wiki_repository

      expect(group.group_wiki_repository.replicator).to receive(:geo_handle_after_destroy)

      service.execute
    end
  end

  context 'when not on a Geo primary site' do
    it 'does not call replicator to update Geo' do
      group.wiki.create_wiki_repository

      expect(group.group_wiki_repository.replicator).not_to receive(:geo_handle_after_destroy)

      service.execute
    end
  end

  context 'when group epics have parent epic outside of group' do
    let!(:parent_group) { create(:group) }
    let!(:group) { create(:group, parent: parent_group) }
    let!(:parent_epic1) { create(:epic, group: parent_group) }
    let!(:parent_epic2) { create(:epic, group: parent_group) }
    let!(:parent_epic3) { create(:epic, group: parent_group) }
    let!(:epic1) { create(:epic, group: group, parent: parent_epic1) }
    let!(:epic2) { create(:epic, group: group, parent: parent_epic2) }
    let!(:epic3) { create(:epic, group: group, parent: parent_epic3) }
    # update should not be called for this as parent is in the same group:
    let!(:epic4) { create(:epic, group: group, parent: epic2) }

    before do
      group.add_owner(user)
    end

    it 'schedules cache update for associated epics in batches' do
      stub_const('::Epics::UpdateCachedMetadataWorker::BATCH_SIZE', 2)

      expect(::Epics::UpdateCachedMetadataWorker).to receive(:bulk_perform_in) do |delay, ids|
        expect(delay).to eq(1.minute)
        expect(ids.map(&:first).map(&:length)).to eq([2, 1])
        expect(ids.flatten).to match_array([parent_epic1.id, parent_epic2.id, parent_epic3.id])
      end.once

      service.execute
    end
  end

  context 'associated records' do
    let!(:service_account) { create(:service_account, provisioned_by_group: group) }
    let!(:service_account_another_group) { create(:service_account, provisioned_by_group: create(:group)) }
    let!(:provisioned_user) { create(:user, provisioned_by_group: group) }

    it 'deletes group serviced accounts and user bots', :sidekiq_inline do
      service.execute

      expect(
        Users::GhostUserMigration.where(user: service_account, initiator_user: user)
      ).to be_exists
      expect(
        Users::GhostUserMigration.where(user: service_account_another_group, initiator_user: user)
      ).to be_empty
      expect(
        Users::GhostUserMigration.where(user: provisioned_user, initiator_user: user)
      ).to be_empty
    end
  end

  context 'when the group is the sole approver on a protected environment it does not own' do
    let!(:protected_environment) { create(:protected_environment) }
    let!(:approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
    end

    it 'destroys the group and reassigns the rule to a maintainer-level fallback', :aggregate_failures do
      expect { service.execute }.not_to raise_error

      expect(Group.exists?(group.id)).to be(false)

      approval_rule.reload
      expect(approval_rule.group_id).to be_nil
      expect(approval_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
    end
  end

  context 'when the group is the sole approver on a group-level protected environment it does not own' do
    let!(:owning_group) { create(:group) }
    let!(:protected_environment) { create(:protected_environment, :group_level, group: owning_group) }
    let!(:approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
    end

    it 'destroys the group and reassigns the rule', :aggregate_failures do
      expect { service.execute }.not_to raise_error

      expect(Group.exists?(group.id)).to be(false)

      approval_rule.reload
      expect(approval_rule.group_id).to be_nil
    end
  end

  context 'when the group is the sole approver on its own group-level protected environment' do
    let!(:protected_environment) { create(:protected_environment, :group_level, group: group) }
    let!(:approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
    end

    it 'destroys the group - the environment is removed by the FK cascade, not left dangling' do
      expect { service.execute }.not_to raise_error

      expect(Group.exists?(group.id)).to be(false)
    end
  end

  context 'when the group is the sole approver on a protected environment owned by its own subgroup' do
    let!(:subgroup) { create(:group, parent: group) }
    let!(:subproject) { create(:project, group: subgroup) }
    let!(:protected_environment) { create(:protected_environment, project: subproject) }
    let!(:approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
    end

    it 'destroys the group, subgroup, subproject, and environment together, with nothing left to reassign',
      :aggregate_failures do
      expect { service.execute }.not_to raise_error

      expect(Group.exists?(group.id)).to be(false)
      expect(Group.exists?(subgroup.id)).to be(false)
      expect(Project.exists?(subproject.id)).to be(false)
      expect(ProtectedEnvironment.exists?(protected_environment.id)).to be(false)
      expect(ProtectedEnvironments::ApprovalRule.exists?(approval_rule.id)).to be(false)
    end
  end

  context 'when the group is a redundant (non-sole) approver on a protected environment it does not own' do
    let!(:protected_environment) { create(:protected_environment) }
    let!(:approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
    end

    let!(:other_approval_rule) do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, user: create(:user))
    end

    it 'proceeds with the destroy - deleting this group would not drop the environment to zero approvers' do
      expect { service.execute }.not_to raise_error

      expect(Group.exists?(group.id)).to be(false)
      expect(ProtectedEnvironments::ApprovalRule.exists?(approval_rule.id)).to be(false)
      expect(ProtectedEnvironments::ApprovalRule.exists?(other_approval_rule.id)).to be(true)
    end
  end

  context 'when group has a secrets manager' do
    # The destroy hook no longer calls `InitiateDeprovisionService`. The
    # FK on `group_secrets_managers.group_id` is `ON DELETE CASCADE`, so
    # destroying the group also deletes the SM row, which fires the
    # `enqueue_gsm_deprovision_task_after_delete` trigger and inserts a
    # deprovision maintenance task with the snapshot ids read off the
    # SM's denormalized columns. See gitlab-org/gitlab#600290.

    context 'and the secrets manager is active' do
      let!(:secrets_manager) { create(:group_secrets_manager, :active, group: group) }

      it 'lets CASCADE + the trigger enqueue the deprovision task; no service call' do
        expect(SecretsManagement::GroupSecretsManagers::InitiateDeprovisionService).not_to receive(:new)

        expect { service.execute }
          .to change { SecretsManagement::GroupSecretsManager.where(group_id: group.id).count }.from(1).to(0)
          .and change {
                 SecretsManagement::GroupSecretsManagerMaintenanceTask.where(group_id: group.id,
                   action: :deprovision).count
               }.from(0).to(1)
      end
    end

    context 'and the secrets manager is still provisioning' do
      let!(:secrets_manager) { create(:group_secrets_manager, :provisioning, group: group) }

      it 'still cascade-deletes the SM and creates a deprovision task' do
        expect(SecretsManagement::GroupSecretsManagers::InitiateDeprovisionService).not_to receive(:new)

        expect { service.execute }
          .to change { SecretsManagement::GroupSecretsManager.where(group_id: group.id).count }.from(1).to(0)
          .and change {
                 SecretsManagement::GroupSecretsManagerMaintenanceTask.where(group_id: group.id,
                   action: :deprovision).count
               }.from(0).to(1)

        expect(Group.find_by(id: group.id)).to be_nil
      end
    end

    context 'and a deprovision maintenance task already exists' do
      let!(:secrets_manager) { create(:group_secrets_manager, :active, group: group) }
      let!(:existing_task) do
        create(:group_secrets_manager_maintenance_task, :deprovision, group: group, user: user)
      end

      it "the trigger's ON CONFLICT skips the dup; the existing task drains as usual" do
        expect(SecretsManagement::DeprovisionGroupSecretsManagerWorker).not_to receive(:perform_async)

        expect { service.execute }
          .to change { SecretsManagement::GroupSecretsManager.where(group_id: group.id).count }.from(1).to(0)
          .and not_change { SecretsManagement::GroupSecretsManagerMaintenanceTask.where(group_id: group.id, action: :deprovision).count }
      end
    end
  end

  context 'when group has no secrets manager' do
    it 'completes the destroy without touching SM state' do
      expect(SecretsManagement::GroupSecretsManagers::InitiateDeprovisionService).not_to receive(:new)

      expect { service.execute }
        .to not_change { SecretsManagement::GroupSecretsManagerMaintenanceTask.count }
    end

    context 'but a descendant subgroup has a secrets manager' do
      # The descendant's own destroy CASCADE-deletes its SM and fires
      # its own trigger. We assert that hand-off still happens even
      # when there's nothing to do at the parent.
      let!(:subgroup) { create(:group, parent: group) }
      let!(:subgroup_sm) { create(:group_secrets_manager, :active, group: subgroup) }

      it 'creates a deprovision task for the descendant SM via the trigger' do
        expect { service.execute }
          .to change {
                SecretsManagement::GroupSecretsManagerMaintenanceTask.where(group_id: subgroup.id,
                  action: :deprovision).count
              }.from(0).to(1)
      end
    end

    context 'but a descendant project has a secrets manager' do
      let!(:descendant_project) { create(:project, namespace: group) }
      let!(:project_sm) { create(:project_secrets_manager, :active, project: descendant_project) }

      it 'creates a deprovision task for the descendant project SM via the trigger' do
        expect { service.execute }
          .to change {
                SecretsManagement::ProjectSecretsManagerMaintenanceTask.where(project_id: descendant_project.id,
                  action: :deprovision).count
              }.from(0).to(1)
      end
    end
  end
end
