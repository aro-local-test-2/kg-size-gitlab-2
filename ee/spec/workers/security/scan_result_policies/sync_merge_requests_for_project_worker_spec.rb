# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:configuration) do
    create(:security_orchestration_policy_configuration, project: project)
  end

  let_it_be(:security_policy) do
    create(:security_policy, security_orchestration_policy_configuration: configuration, linked_projects: [project])
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(project.id, configuration.id) }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id, configuration.id] }
    end

    it 'has the `until_executed` deduplicate strategy' do
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end

    it 'calls SyncMergeRequestsService with policy_configuration_id' do
      expect_next_instance_of(
        Security::SecurityOrchestrationPolicies::SyncMergeRequestsService,
        project: project,
        policy_configuration_id: configuration.id
      ) do |service|
        expect(service).to receive(:execute)
      end

      perform
    end

    context 'when project does not exist' do
      subject(:perform) { described_class.new.perform(non_existing_record_id, configuration.id) }

      it 'does not call SyncMergeRequestsService' do
        expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).not_to receive(:new)

        perform
      end
    end

    context 'when configuration does not exist' do
      subject(:perform) { described_class.new.perform(project.id, non_existing_record_id) }

      it 'does not call SyncMergeRequestsService' do
        expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).not_to receive(:new)

        perform
      end
    end

    context 'when no policy of the configuration is linked to the project' do
      let_it_be(:unlinked_configuration) do
        create(:security_orchestration_policy_configuration, :namespace, namespace: create(:group))
      end

      let_it_be(:unlinked_policy) do
        create(:security_policy, security_orchestration_policy_configuration: unlinked_configuration)
      end

      subject(:perform) { described_class.new.perform(project.id, unlinked_configuration.id) }

      it 'does not call SyncMergeRequestsService' do
        expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).not_to receive(:new)

        perform
      end
    end
  end
end
