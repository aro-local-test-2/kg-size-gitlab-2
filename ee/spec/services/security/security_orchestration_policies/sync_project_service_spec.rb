# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::SyncProjectService, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }
  let_it_be_with_refind(:security_policy) { create(:security_policy, :require_approval) }
  let_it_be_with_refind(:approval_policy_rule) { create(:approval_policy_rule, security_policy: security_policy) }

  let(:policy_changes) { { diff: {}, rules_diff: {} } }

  subject(:service) do
    described_class.new(security_policy: security_policy, project: project, policy_changes: policy_changes)
  end

  shared_examples 'with branch exceptions bypass settings for security policy' do
    before do
      security_policy.update!(content: {
        bypass_settings: { branches: [{ source: { name: 'feature' }, target: { name: 'main' } }] }
      })
    end

    it 'tracks internal event', :clean_gitlab_redis_shared_state do
      expect { service.execute }
        .to trigger_internal_events('check_branch_exceptions_bypass_settings_for_approval_policy')
        .with(project: project)
        .and increment_usage_metrics(
          "redis_hll_counters." \
            "count_distinct_project_id_from_check_branch_exceptions_bypass_settings_for_approval_policy_monthly"
        )
    end
  end

  # Self-contained: uses its own repository-backed, not-yet-linked project rather than the
  # shared `project` (needed so `PolicyBranchesService` sees a non-empty repo), and its own
  # `service` instance. Leaving the policy unlinked lets `link_policy` create the project/rule
  # links itself, matching the "policy is enabled" context above, instead of pre-creating them
  # and risking interference with sibling `let_it_be` state scoped to the shared `project`.
  shared_examples 'with unenforceable target branch for security policy' do
    let(:project_with_repo) { create(:project, :repository) }

    subject(:sync_service) do
      described_class.new(
        security_policy: security_policy, project: project_with_repo, policy_changes: { diff: {}, rules_diff: {} }
      )
    end

    context 'when the rule applies to all protected branches and none exist' do
      before do
        approval_policy_rule.update!(content: approval_policy_rule.content.merge('branches' => []))
      end

      it 'tracks internal event', :clean_gitlab_redis_shared_state do
        expect { sync_service.execute }
          .to trigger_internal_events('check_target_branch_not_protected_for_approval_policy')
          .with(project: project_with_repo)
          .and increment_usage_metrics(
            "redis_hll_counters." \
              "count_distinct_project_id_from_check_target_branch_not_protected_for_approval_policy_monthly"
          )
      end
    end

    context 'when the rule applies to all protected branches and one exists' do
      before do
        create(:protected_branch, project: project_with_repo, name: project_with_repo.default_branch)
        approval_policy_rule.update!(content: approval_policy_rule.content.merge('branches' => []))
      end

      it 'does not track internal event', :clean_gitlab_redis_shared_state do
        expect { sync_service.execute }
          .not_to trigger_internal_events('check_target_branch_not_protected_for_approval_policy')
      end
    end

    context 'when the rule has explicit branches matching no protected branch' do
      before do
        create(:protected_branch, project: project_with_repo, name: project_with_repo.default_branch)
        approval_policy_rule.update!(content: approval_policy_rule.content.merge('branches' => ['does-not-match']))
      end

      # ApprovalProjectRule#applies_to_branch? falls back to applying to every protected branch
      # when a rule's explicit `branches` match none, so this rule isn't actually dead.
      it 'does not track internal event', :clean_gitlab_redis_shared_state do
        expect { sync_service.execute }
          .not_to trigger_internal_events('check_target_branch_not_protected_for_approval_policy')
      end
    end
  end

  describe '#execute' do
    context 'when policy_changes is empty' do
      context 'when policy is disabled' do
        before do
          security_policy.update!(enabled: false)
        end

        it 'does not link the policy and rules' do
          expect { service.execute }.to not_change { Security::PolicyProjectLink.count }
            .and not_change { Security::ApprovalPolicyRuleProjectLink.count }
        end
      end

      context 'when defer_policy_mr_sync: true' do
        let_it_be(:enrichment_rule) do
          create(:approval_policy_rule, :scan_finding_with_epss_filter, security_policy: security_policy)
        end

        subject(:service) do
          described_class.new(
            security_policy: security_policy,
            project: project,
            policy_changes: {},
            defer_policy_mr_sync: true
          )
        end

        it 'links policy and creates approval rules without syncing merge requests inline', :aggregate_failures do
          expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).not_to receive(:new)
          expect(Security::ScanResultPolicies::SyncProjectFindingEnrichmentsWorker).not_to receive(:perform_async)

          expect { service.execute }
            .to change { Security::PolicyProjectLink.count }.by(1)
            .and change { project.approval_rules.count }.by(2)
        end
      end

      context 'when policy is enabled' do
        it 'links policy and rules to project' do
          expect { service.execute }
            .to change { Security::PolicyProjectLink.count }.from(0).to(1)
              .and change { Security::ApprovalPolicyRuleProjectLink.count }.from(0).to(1)
        end

        it 'create project approval_rule' do
          expect { service.execute }.to change { project.approval_rules.count }.by(1)
        end

        it 'syncs merge requests inline' do
          expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService)
            .to receive(:new).with(project: project, security_policy: security_policy).and_call_original

          service.execute
        end

        # Pins that the call stays after the linking transaction commits, not inside it -
        # moving it back in would reintroduce Gitaly calls inside an open DB transaction.
        it 'tracks the target-branch-not-protected event after the linking transaction' do
          expect(security_policy).to receive(:link_project!).ordered.and_call_original
          expect(service).to receive(:track_target_branch_not_protected).ordered.and_call_original

          service.execute
        end

        include_examples 'creates PEP project schedules' do
          subject(:execute) { service.execute }
        end

        context 'with scan execution policy' do
          let_it_be(:security_policy) do
            create(:security_policy, :scan_execution_policy, policy_index: 0)
          end

          let_it_be(:rule_schedule) do
            create(:security_orchestration_policy_rule_schedule,
              security_orchestration_policy_configuration:
                security_policy.security_orchestration_policy_configuration,
              policy_index: 0,
              rule_index: 0)
          end

          it 'creates scan execution project schedules' do
            expect { service.execute }.to change { Security::ScanExecutionProjectSchedule.count }.by(1)
          end

          # Pins that the call stays behind the `type_approval_policy?` guard.
          it 'does not track the target-branch-not-protected event' do
            expect { service.execute }
              .not_to trigger_internal_events('check_target_branch_not_protected_for_approval_policy')
          end

          context 'when scan_execution_policy_project_schedule_creation feature flag is disabled' do
            before do
              stub_feature_flags(scan_execution_policy_project_schedule_creation: false)
            end

            it 'does not create scan execution project schedules' do
              expect { service.execute }.not_to change { Security::ScanExecutionProjectSchedule.count }
            end
          end
        end

        include_examples 'with unenforceable target branch for security policy'
        include_examples 'syncs finding enrichments for approval policy with enrichment filters'

        context 'when policy_scope is not applicable' do
          before do
            allow_next_found_instance_of(Security::Policy) do |instance|
              allow(instance).to receive(:scope_applicable?).and_return(false)
            end
          end

          it 'does not link the policy and rules' do
            expect { service.execute }.to not_change { Security::PolicyProjectLink.count }
              .and not_change { Security::ApprovalPolicyRuleProjectLink.count }
          end
        end
      end
    end

    context 'when policy_changes exists' do
      shared_context 'when project approval_rules already exists' do
        let_it_be(:project_approval_rule) do
          create(:approval_project_rule, :scan_finding,
            project: project,
            approval_policy_rule: approval_policy_rule,
            security_orchestration_policy_configuration: security_policy.security_orchestration_policy_configuration
          )
        end

        it 'deletes project approval_rules' do
          expect { service.execute }.to change { project.approval_rules.count }.by(-1)
        end
      end

      describe 'changes of rules' do
        context 'when policy is linked to the project' do
          before do
            create(:security_policy_project_link, project: project, security_policy: security_policy)
            create(:approval_policy_rule_project_link, project: project, approval_policy_rule: approval_policy_rule)
          end

          context 'with deleted policy rules' do
            let(:policy_changes) do
              { rules_diff: { deleted: [{ id: approval_policy_rule.id }] } }
            end

            it 'unlinks policy rules project' do
              expect { service.execute }
                .to change { Security::ApprovalPolicyRuleProjectLink.count }.from(1).to(0)
            end

            include_context 'when project approval_rules already exists'
          end

          context 'with created policy rules' do
            let_it_be(:new_approval_policy_rule) { create(:approval_policy_rule, security_policy: security_policy) }

            let(:policy_changes) do
              { diff: { enabled: { from: false, to: true } },
                rules_diff: { created: [{ id: new_approval_policy_rule.id }] } }
            end

            it 'links policy rules project' do
              expect { service.execute }
                .to change { Security::ApprovalPolicyRuleProjectLink.count }.from(1).to(2)
            end

            context 'when policy_scope is not applicable' do
              before do
                allow(service).to receive(:scope_applicable?).and_return(false)
              end

              it 'does not link the policy and rules' do
                expect { service.execute }.to not_change { Security::PolicyProjectLink.count }
                  .and not_change { Security::ApprovalPolicyRuleProjectLink.count }
              end
            end

            include_examples 'with branch exceptions bypass settings for security policy'
            include_examples 'with unenforceable target branch for security policy'
            include_examples 'syncs finding enrichments for approval policy with enrichment filters'
          end

          context 'with updated policy rules' do
            let(:updated_rule_content) do
              {
                type: 'scan_finding',
                branches: [],
                scanners: %w[dependency_scanning],
                vulnerabilities_allowed: 0,
                severity_levels: %w[critical],
                vulnerability_states: %w[detected]
              }
            end

            let(:policy_changes) do
              {
                rules_diff: {
                  updated: [{
                    id: approval_policy_rule.id,
                    from: {
                      type: 'scan_finding',
                      branches: [],
                      scanners: %w[container_scanning],
                      vulnerabilities_allowed: 0,
                      severity_levels: %w[critical],
                      vulnerability_states: %w[detected]
                    },
                    to: updated_rule_content
                  }]
                }
              }
            end

            let_it_be(:scan_result_policy_read) do
              create(:scan_result_policy_read,
                project: project,
                orchestration_policy_idx: security_policy.policy_index,
                approval_policy_rule: approval_policy_rule,
                rule_idx: approval_policy_rule.rule_index,
                security_orchestration_policy_configuration: security_policy.security_orchestration_policy_configuration
              )
            end

            let_it_be(:project_approval_rule) do
              create(:approval_project_rule, :scan_finding,
                project: project,
                scan_result_policy_read: scan_result_policy_read,
                approval_policy_rule: approval_policy_rule,
                security_orchestration_policy_configuration: security_policy.security_orchestration_policy_configuration
              )
            end

            before do
              approval_policy_rule.update!(content: updated_rule_content)
            end

            it 'updates project approval_rules' do
              service.execute

              expect(project_approval_rule.reload.scanners).to contain_exactly('dependency_scanning')
            end

            context 'when policy is already disabled' do
              before do
                security_policy.update!(enabled: false)
              end

              it 'does not link the policy and rules' do
                expect { service.execute }.to not_change { Security::PolicyProjectLink.count }
                  .and not_change { Security::ApprovalPolicyRuleProjectLink.count }
              end
            end

            include_examples 'with branch exceptions bypass settings for security policy'
            include_examples 'with unenforceable target branch for security policy'
            include_examples 'syncs finding enrichments for approval policy with enrichment filters'
          end
        end

        context 'when policy is not linked to the project' do
          let(:policy_changes) do
            { diff: {}, rules_diff: { updated: [{ id: approval_policy_rule.id, from: {}, to: {} }] } }
          end

          before do
            security_policy.update!(enabled: true)
          end

          it 'links policy and rules to project' do
            expect { service.execute }
              .to change { Security::PolicyProjectLink.count }.from(0).to(1)
                .and change { Security::ApprovalPolicyRuleProjectLink.count }.from(0).to(1)
          end

          it 'creates project approval_rule' do
            expect { service.execute }.to change { project.approval_rules.count }.by(1)
          end

          context 'when policy_scope is not applicable' do
            before do
              allow(service).to receive(:scope_applicable?).and_return(false)
            end

            it 'does not link the policy and rules' do
              expect { service.execute }.to not_change { Security::PolicyProjectLink.count }
                .and not_change { Security::ApprovalPolicyRuleProjectLink.count }
            end
          end
        end
      end

      context 'when policy gets disabled' do
        let(:policy_changes) { { diff: { enabled: { from: true, to: false } }, rules_diff: {} } }

        before do
          security_policy.update!(enabled: false)
        end

        context 'when policy was linked to the project' do
          before do
            create(:security_policy_project_link, project: project, security_policy: security_policy)
            create(:approval_policy_rule_project_link, project: project, approval_policy_rule: approval_policy_rule)
          end

          it 'unlinks the project from the security policy' do
            expect { service.execute }.to change { Security::PolicyProjectLink.count }.from(1).to(0)
          end

          it 'unlinks policy rules project if it is an approval policy' do
            expect { service.execute }.to change { Security::ApprovalPolicyRuleProjectLink.count }.from(1).to(0)
          end

          include_context 'when project approval_rules already exists'
        end

        context 'when policy was not linked to the project' do
          it 'does not unlink the project from the security policy' do
            expect { service.execute }.not_to change { Security::PolicyProjectLink.count }
          end

          it 'does not unlink policy rules project if it is an approval policy' do
            expect { service.execute }.not_to change { Security::ApprovalPolicyRuleProjectLink.count }
          end
        end

        context 'with pipeline execution schedule policy' do
          let_it_be_with_refind(:security_policy) { create(:security_policy, :pipeline_execution_schedule_policy) }

          before do
            create(:security_pipeline_execution_project_schedule, project: project, security_policy: security_policy)
          end

          it 'deletes project pipeline execution schedule' do
            expect { service.execute }.to change { Security::PipelineExecutionProjectSchedule.count }.from(1).to(0)
          end

          it 'enqueues CancelPolicyPipelinesWorker' do
            expect(Security::PipelineExecutionPolicies::CancelPolicyPipelinesWorker)
              .to receive(:perform_async)
              .with(security_policy.id, project.id)

            service.execute
          end
        end

        context 'with scan execution policy' do
          let_it_be_with_refind(:security_policy) do
            create(:security_policy, :scan_execution_policy, policy_index: 0)
          end

          before do
            create(:security_scan_execution_project_schedule, project: project, security_policy: security_policy)
          end

          it 'deletes scan execution project schedules' do
            expect { service.execute }.to change { Security::ScanExecutionProjectSchedule.count }.from(1).to(0)
          end

          context 'when scan_execution_policy_project_schedule_creation feature flag is disabled' do
            before do
              stub_feature_flags(scan_execution_policy_project_schedule_creation: false)
            end

            it 'does not delete scan execution project schedules' do
              expect { service.execute }.not_to change { Security::ScanExecutionProjectSchedule.count }
            end
          end
        end
      end

      context 'when policy gets enabled' do
        let(:policy_changes) { { diff: { enabled: { from: false, to: true } }, rules_diff: {} } }

        context 'when policy is scoped' do
          before do
            allow(service).to receive_messages(
              policy_scope_changed_and_unscoped?: false,
              policy_scope_changed_and_scoped?: true
            )
          end

          context 'when policy is not linked to project' do
            it 'links policy and rules to project' do
              expect { service.execute }
                .to change { Security::PolicyProjectLink.count }.from(0).to(1)
            end

            include_examples 'syncs finding enrichments for approval policy with enrichment filters'
          end

          context 'when policy is already linked to project' do
            before do
              create(:security_policy_project_link, project: project, security_policy: security_policy)
              create(:approval_policy_rule_project_link, project: project, approval_policy_rule: approval_policy_rule)
            end

            it 'does not change the project links' do
              expect { service.execute }
                .not_to change { Security::PolicyProjectLink.count }
            end
          end
        end

        context 'when policy is unscoped' do
          before do
            allow(service).to receive_messages(
              policy_scope_changed_and_unscoped?: true,
              policy_scope_changed_and_scoped?: false
            )
          end

          context 'when policy is linked to the project' do
            before do
              create(:security_policy_project_link, project: project, security_policy: security_policy)
              create(:approval_policy_rule_project_link, project: project, approval_policy_rule: approval_policy_rule)
            end

            it 'unlinks the project from the security policy' do
              expect { service.execute }.to change { Security::PolicyProjectLink.count }.from(1).to(0)
            end

            it 'unlinks policy rules project if it is an approval policy' do
              expect { service.execute }.to change { Security::ApprovalPolicyRuleProjectLink.count }.from(1).to(0)
            end
          end

          context 'when it is not linked to the project' do
            it 'does not unlink the project from the security policy' do
              expect { service.execute }.not_to change { Security::PolicyProjectLink.count }
            end

            it 'does not unlink policy rules project if it is an approval policy' do
              expect { service.execute }.not_to change { Security::ApprovalPolicyRuleProjectLink.count }
            end
          end
        end
      end

      context 'with scheduled pipeline execution policy' do
        let_it_be(:snoozed_until) { 1.month.from_now.beginning_of_day }
        let_it_be(:snooze) { { until: snoozed_until.iso8601 } }

        let_it_be(:schedule_to) do
          { type: "daily", start_time: "10:00", time_window: { value: 600, distribution: "random" }, snooze: snooze }
        end

        let_it_be(:schedule_from) { schedule_to.except(:snooze) }

        let_it_be(:diff) { { schedules: { from: [schedule_from], to: [schedule_to] } } }
        let_it_be(:policy_changes) do
          {
            diff: diff,
            rules_diff: {
              created: [],
              updated: [],
              deleted: []
            }
          }
        end

        let_it_be(:security_policy) do
          create(
            :security_policy,
            :pipeline_execution_schedule_policy,
            content: {
              content: { include: [{ project: 'compliance-project', file: "compliance-pipeline.yml" }] },
              schedules: [schedule_to]
            })
        end

        let_it_be_with_refind(:project_schedule) do
          create(:security_pipeline_execution_project_schedule, project: project, security_policy: security_policy)
        end

        def persisted_schedule
          Security::PipelineExecutionProjectSchedule.for_project(project).for_policy(security_policy).first!
        end

        context 'when policy is already linked to the project' do
          before do
            create(:security_policy_project_link, project: project, security_policy: security_policy)
          end

          context 'with experiment enabled' do
            before do
              allow(security_policy.security_orchestration_policy_configuration)
                .to receive(:experiment_enabled?).and_return(true)
            end

            it 'recreates pipeline execution project schedules' do
              expect { service.execute }.not_to change { Security::PipelineExecutionProjectSchedule.count }

              expect(persisted_schedule.snoozed_until).to eq(snoozed_until)
            end

            it 'enqueues CancelPolicyPipelinesWorker when schedule is snoozed' do
              expect(Security::PipelineExecutionPolicies::CancelPolicyPipelinesWorker)
                .to receive(:perform_async)
                .with(security_policy.id, project.id)

              service.execute
            end

            context 'when schedule changes without snooze being added' do
              let(:schedule_from) { { type: 'daily', start_time: '10:00', time_window: { value: 600 } } }
              let(:schedule_to) { { type: 'daily', start_time: '11:00', time_window: { value: 600 } } }
              let(:diff) { { schedules: { from: [schedule_from], to: [schedule_to] } } }
              let(:policy_changes) do
                {
                  diff: diff,
                  rules_diff: {
                    created: [],
                    updated: [],
                    deleted: []
                  }
                }
              end

              it 'does not enqueue CancelPolicyPipelinesWorker' do
                expect(Security::PipelineExecutionPolicies::CancelPolicyPipelinesWorker)
                  .not_to receive(:perform_async)

                service.execute
              end
            end
          end
        end

        context 'with experiment enabled' do
          before do
            allow(security_policy.security_orchestration_policy_configuration)
              .to receive(:experiment_enabled?).and_return(true)
          end

          specify do
            expect { service.execute }.to change { persisted_schedule.snoozed_until }.from(nil).to(snoozed_until)
          end

          context 'when policy_scope is not applicable' do
            before do
              allow(service).to receive(:scope_applicable?).and_return(false)
            end

            specify do
              expect { service.execute }.not_to change { persisted_schedule.snoozed_until }
            end
          end
        end

        context 'when scheduled_pipeline_execution_policies feature flag is disabled' do
          before do
            stub_feature_flags(scheduled_pipeline_execution_policies: false)
          end

          specify do
            expect { service.execute }.to change { Security::PipelineExecutionProjectSchedule.count }.from(1).to(0)
          end
        end
      end

      context 'with pipeline execution policy' do
        let_it_be(:security_policy) do
          create(:security_policy, :pipeline_execution_policy, policy_index: 0)
        end

        let(:policy_changes) do
          {
            diff: { content: { from: { include: [] }, to: { include: [{ project: 'p', file: 'f.yml' }] } } },
            rules_diff: { created: [], updated: [], deleted: [] }
          }
        end

        before do
          create(:security_policy_project_link, project: project, security_policy: security_policy)
        end

        it 'does not raise an error' do
          expect { service.execute }.not_to raise_error
        end
      end

      context 'with scan execution policy' do
        let_it_be(:security_policy) do
          create(:security_policy, :scan_execution_policy, policy_index: 0)
        end

        let_it_be(:rule_schedule) do
          create(:security_orchestration_policy_rule_schedule,
            security_orchestration_policy_configuration:
              security_policy.security_orchestration_policy_configuration,
            policy_index: 0,
            rule_index: 0)
        end

        let(:policy_changes) do
          {
            diff: { content: { from: { actions: [] }, to: { actions: [{ scan: 'secret_detection' }] } } },
            rules_diff: { created: [], updated: [], deleted: [] }
          }
        end

        before do
          create(:security_policy_project_link, project: project, security_policy: security_policy)
        end

        it 'recreates scan execution project schedules' do
          expect { service.execute }.to change { Security::ScanExecutionProjectSchedule.count }.by(1)
        end

        context 'when scan_execution_policy_project_schedule_creation feature flag is disabled' do
          before do
            stub_feature_flags(scan_execution_policy_project_schedule_creation: false)
          end

          it 'does not create scan execution project schedules' do
            expect { service.execute }.not_to change { Security::ScanExecutionProjectSchedule.count }
          end
        end

        context 'when policy_scope is not applicable' do
          before do
            allow(service).to receive(:scope_applicable?).and_return(false)
          end

          it 'does not create scan execution project schedules' do
            expect { service.execute }.not_to change { Security::ScanExecutionProjectSchedule.count }
          end
        end
      end
    end

    describe 'scheduling warn mode push settings audit events worker' do
      let(:enforcement_type) { 'warn' }
      let(:policy_scope) { { projects: { including: [{ id: project.id }] } } }
      let(:security_policy) do
        create(:security_policy, type: :approval_policy, scope: policy_scope).tap do |policy|
          policy.update!(content: policy.content.merge('enforcement_type' => enforcement_type))
        end
      end

      shared_examples 'scheduling warn mode push settings audit events worker' do
        specify do
          expect(Security::ScanResultPolicies::CreateProjectWarnModePushSettingsAuditEventsWorker)
            .to receive(:perform_async)
            .with(project.id, security_policy.id)

          service.execute
        end
      end

      shared_examples 'not scheduling warn mode push settings audit events worker' do
        specify do
          expect(Security::ScanResultPolicies::CreateProjectWarnModePushSettingsAuditEventsWorker)
            .not_to receive(:perform_async)

          service.execute
        end
      end

      context 'when policy is an approval policy in warn mode and applicable to the project' do
        it_behaves_like 'scheduling warn mode push settings audit events worker'
      end

      context 'when policy is not in warn mode' do
        let(:enforcement_type) { 'enforce' }

        it_behaves_like 'not scheduling warn mode push settings audit events worker'
      end

      context 'when policy is not applicable to the project' do
        let(:policy_scope) { { projects: { excluding: [{ id: project.id }] } } }

        it_behaves_like 'not scheduling warn mode push settings audit events worker'
      end

      context 'when policy is not an approval policy' do
        let(:security_policy) { create(:security_policy, :scan_execution_policy) }

        it_behaves_like 'not scheduling warn mode push settings audit events worker'
      end

      context 'when the policy is disabled' do
        before do
          security_policy.update!(enabled: false)
        end

        it_behaves_like 'not scheduling warn mode push settings audit events worker'
      end
    end
  end
end
