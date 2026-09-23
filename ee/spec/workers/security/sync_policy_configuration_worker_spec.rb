# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SyncPolicyConfigurationWorker, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let(:event) do
    Security::PolicyConfigurationAssignedEvent.build(configuration: configuration)
  end

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:configuration) do
    create(:security_orchestration_policy_configuration, project: project)
  end

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  it_behaves_like 'subscribes to event'

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '.idempotency_arguments' do
    it 'returns the configuration_id from the event data' do
      expect(described_class.idempotency_arguments([event.class.name, event.data]))
        .to eq([configuration.id])
    end
  end

  context 'when sync_policies_in_bulk_on_policy_configuration_assign flag is disabled' do
    before do
      stub_feature_flags(sync_policies_in_bulk_on_policy_configuration_assign: false)
    end

    it 'does not enqueue SyncProjectPoliciesWorker' do
      expect(Security::SyncProjectPoliciesWorker).not_to receive(:bulk_perform_in_with_contexts)

      use_event
    end
  end

  context 'when configuration does not exist' do
    let(:event) do
      stub_configuration = instance_double(Security::OrchestrationPolicyConfiguration, id: non_existing_record_id)
      Security::PolicyConfigurationAssignedEvent.build(configuration: stub_configuration)
    end

    it 'does not enqueue SyncProjectPoliciesWorker' do
      expect(Security::SyncProjectPoliciesWorker).not_to receive(:bulk_perform_in_with_contexts)

      use_event
    end
  end

  context 'when configuration has no projects' do
    it 'does not enqueue SyncProjectPoliciesWorker' do
      allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |config|
        allow(config).to receive(:all_project_ids).and_yield([])
      end

      expect(Security::SyncProjectPoliciesWorker).not_to receive(:bulk_perform_in_with_contexts)

      use_event
    end
  end

  context 'when configuration is project-based' do
    it 'enqueues SyncProjectPoliciesWorker with a 1-interval delay' do
      expect(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts)
        .with(
          described_class::BATCH_DELAY_INTERVAL,
          [project.id],
          arguments_proc: satisfy { |proc|
            proc.call(project.id) == [project.id, configuration.id, { 'triggered_by_assign' => true }]
          },
          context_proc: satisfy { |proc| proc.call(nil) == { project: project } }
        )

      use_event
    end
  end

  context 'when configuration is namespace-based' do
    let_it_be(:configuration) do
      create(:security_orchestration_policy_configuration, namespace: group, project: nil)
    end

    let_it_be(:another_project) { create(:project, group: group) }

    it 'enqueues SyncProjectPoliciesWorker for all group projects with namespace context and params' do
      expect(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts)
        .with(
          described_class::BATCH_DELAY_INTERVAL,
          contain_exactly(project.id, another_project.id),
          arguments_proc: satisfy { |proc|
            proc.call(project.id) == [project.id, configuration.id, { 'triggered_by_assign' => true }]
          },
          context_proc: satisfy { |proc| proc.call(nil) == { namespace: group } }
        )

      use_event
    end

    it 'uses strictly increasing delays across batches' do
      batch1 = [1, 2, 3]
      batch2 = [4, 5, 6]
      received_delays = []

      allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |config|
        allow(config).to receive(:all_project_ids).and_yield(batch1).and_yield(batch2)
      end

      allow(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts) do |delay, *|
        received_delays << delay
      end

      use_event

      expect(received_delays).to eq([
        1 * described_class::BATCH_DELAY_INTERVAL,
        2 * described_class::BATCH_DELAY_INTERVAL
      ])
    end
  end
end
