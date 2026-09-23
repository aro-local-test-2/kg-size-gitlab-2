# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::LinkPolicyConfigurationService,
  feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:configuration) do
    create(:security_orchestration_policy_configuration, project: project)
  end

  subject(:execute) { described_class.new(project: project, configuration: configuration).execute }

  shared_examples 'does not link any policy or enqueue workers' do
    it 'does not link any policy or enqueue workers', :aggregate_failures do
      expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

      expect { execute }.not_to change { Security::PolicyProjectLink.count }
      expect(execute.payload).to eq(linked_policy_ids: [], failed_policy_ids: [])
    end
  end

  context 'when there are applicable approval policies' do
    let_it_be_with_reload(:security_policy) do
      create(:security_policy, :require_approval,
        security_orchestration_policy_configuration: configuration)
    end

    before_all do
      create(:approval_policy_rule, security_policy: security_policy)
    end

    context 'when there are no opened merge requests and policies with enrichment filters' do
      it 'links the policy without without scheduling project-wide syncs',
        :aggregate_failures do
        expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)
        expect(Security::ScanResultPolicies::SyncProjectFindingEnrichmentsWorker).not_to receive(:perform_async)

        expect { execute }
          .to change { Security::PolicyProjectLink.count }.by(1)
          .and change { project.approval_rules.count }.by(1)

        expect(execute).to be_success
        expect(execute.payload).to eq(linked_policy_ids: [security_policy.id], failed_policy_ids: [])
      end
    end

    context 'with open merge requests' do
      before do
        create(:merge_request, source_project: project)
        create(:merge_request, source_project: project, source_branch: 'another-branch')
      end

      it 'enqueues SyncMergeRequestsForProjectWorker once for the project' do
        expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker)
          .to receive(:perform_async).with(project.id, configuration.id).once

        execute
      end
    end

    context 'with only a closed merge request' do
      before do
        create(:merge_request, :closed, source_project: project)
      end

      it 'does not enqueue SyncMergeRequestsForProjectWorker' do
        expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when several policies have enrichment filters' do
      let_it_be(:enrichment_policy) do
        create(:security_policy, :with_enrichment_filter_rule,
          security_orchestration_policy_configuration: configuration, policy_index: 1)
      end

      before do
        create(:security_policy, :with_enrichment_filter_rule,
          security_orchestration_policy_configuration: configuration, policy_index: 2)
      end

      it 'enqueues SyncProjectFindingEnrichmentsWorker only once for the project' do
        expect(Security::ScanResultPolicies::SyncProjectFindingEnrichmentsWorker)
          .to receive(:perform_async).with(project.id, enrichment_policy.id).once

        execute
      end
    end

    context 'when the policy scope excludes the project' do
      before do
        security_policy.update!(scope: { projects: { excluding: [{ id: project.id }] } })
      end

      it_behaves_like 'does not link any policy or enqueue workers'
    end

    context 'when policy has branch exceptions bypass settings' do
      before do
        security_policy.update!(content: security_policy.content.merge(
          bypass_settings: { branches: [{ source: { name: 'feature' }, target: { name: 'main' } }] }
        ))
      end

      it 'tracks internal event via SyncProjectService', :clean_gitlab_redis_shared_state do
        allow(Gitlab::InternalEvents).to receive(:track_event).and_call_original

        execute

        expect(Gitlab::InternalEvents).to have_received(:track_event)
          .with('check_branch_exceptions_bypass_settings_for_approval_policy', include(project: project))
      end
    end

    context 'when linking one policy raises' do
      before_all do
        create(:merge_request, source_project: project)
      end

      before do
        allow(Security::SecurityOrchestrationPolicies::SyncProjectService).to receive(:new).and_call_original
        allow_next_instance_of(
          Security::SecurityOrchestrationPolicies::SyncProjectService, hash_including(security_policy: security_policy)
        ) do |service|
          allow(service).to receive(:execute).and_raise(error)
        end
      end

      context 'with ActiveRecord::RecordInvalid' do
        let(:error) { ActiveRecord::RecordInvalid }

        before do
          allow(Gitlab::ErrorTracking).to receive(:track_exception)
          allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
          allow(Security::SyncProjectPolicyWorker).to receive(:perform_async)
          allow(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).to receive(:perform_async)
          allow(Security::ScanResultPolicies::SyncProjectFindingEnrichmentsWorker).to receive(:perform_async)
        end

        context 'when another approval policy links' do
          let_it_be(:other_policy) do
            create(:security_policy, :require_approval,
              security_orchestration_policy_configuration: configuration, policy_index: 1)
          end

          it 'hands the failed policy to SyncProjectPolicyWorker and still links and syncs the other',
            :aggregate_failures do
            expect { execute }.to change { Security::PolicyProjectLink.count }.by(1)

            expect(execute.payload)
              .to eq(linked_policy_ids: [other_policy.id], failed_policy_ids: [security_policy.id])
            expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
              instance_of(ActiveRecord::RecordInvalid), security_policy_id: security_policy.id, project_id: project.id
            )
            expect(Security::SyncProjectPolicyWorker)
              .to have_received(:perform_async).with(project.id, security_policy.id)
            expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker)
              .to have_received(:perform_async).with(project.id, configuration.id)
            expect(Gitlab::AppJsonLogger).to have_received(:info).with(
              event: 'link_policy_configuration',
              project_id: project.id,
              configuration_id: configuration.id,
              linked_policy_ids: [other_policy.id],
              failed_policy_ids: [security_policy.id]
            )
          end
        end

        context 'when it is the only approval policy' do
          before do
            create(:approval_policy_rule, :scan_finding_with_epss_filter, security_policy: security_policy)
          end

          it 'hands the policy to SyncProjectPolicyWorker without scheduling project-wide syncs',
            :aggregate_failures do
            expect { execute }.not_to change { Security::PolicyProjectLink.count }

            expect(execute.payload).to eq(linked_policy_ids: [], failed_policy_ids: [security_policy.id])

            expect(Security::SyncProjectPolicyWorker)
              .to have_received(:perform_async).with(project.id, security_policy.id)
            expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker)
              .not_to have_received(:perform_async)
            expect(Security::ScanResultPolicies::SyncProjectFindingEnrichmentsWorker)
              .not_to have_received(:perform_async)
          end
        end
      end

      context 'with another error' do
        let(:error) { StandardError.new('boom') }

        it 're-raises so the job retries', :aggregate_failures do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
          expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

          expect { execute }.to raise_error(StandardError, 'boom')
        end
      end
    end
  end

  context 'when there are policies without MR approval policy' do
    let_it_be(:security_policy) do
      create(:security_policy, :scan_execution_policy,
        security_orchestration_policy_configuration: configuration)
    end

    before do
      create(:merge_request, source_project: project)
    end

    it 'links the policy without enqueuing SyncMergeRequestsForProjectWorker', :aggregate_failures do
      expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

      expect { execute }.to change { Security::PolicyProjectLink.count }.by(1)
    end
  end

  context 'when policy is disabled' do
    let_it_be(:security_policy) do
      create(:security_policy, :require_approval,
        security_orchestration_policy_configuration: configuration,
        enabled: false)
    end

    it_behaves_like 'does not link any policy or enqueue workers'
  end

  context 'when policy is deleted' do
    let_it_be(:security_policy) do
      create(:security_policy, :require_approval, :deleted,
        security_orchestration_policy_configuration: configuration)
    end

    it_behaves_like 'does not link any policy or enqueue workers'
  end
end
