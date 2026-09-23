# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::RestartWorkflowService, feature_category: :duo_agent_platform do
  include ExclusiveLeaseHelpers
  include Ai::Catalog::TestHelpers

  let_it_be(:project) { create(:project, group: create(:group)) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be_with_reload(:flow) { create(:ai_catalog_flow, :public, project: project) }
  let_it_be(:consumer) { create(:ai_catalog_item_consumer, item: flow, project: project) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }

  let(:callback_context) { { 'adapter' => 'slack', 'channel' => 'C123' } }
  let(:privileges) { ::Ai::DuoWorkflows::Workflow::AgentPrivileges }
  let(:original_attributes) do
    {
      user: user,
      project: project,
      goal: 'Fix the bug',
      issue: issue,
      summary: 'It broke',
      messaging_callback_context: callback_context,
      source_type: :slack,
      source_link: 'https://slack.example.com/t/1',
      agent_privileges: [privileges::READ_WRITE_FILES, privileges::READ_ONLY_GITLAB],
      pre_approved_agent_privileges: [privileges::READ_WRITE_FILES],
      image: 'ruby:3.3',
      web_search_enabled: true,
      trigger_source: :system,
      trigger_flow_trigger: flow_trigger,
      trigger_event_type: :mention
    }
  end

  let(:workflow) { create(:duo_workflows_workflow, :failed, **original_attributes) }
  let(:new_workflow) { create(:duo_workflows_workflow, :running, user: user, project: project, goal: 'Fix the bug') }
  let(:lease_key) { "duo_workflows_restart:#{workflow.id}" }
  let(:allowed) { true }
  let(:execute_result) { ServiceResponse.success(payload: { workflow: new_workflow, workload_id: 123 }) }
  let(:flows_execute_service) { instance_double(::Ai::Catalog::Flows::ExecuteService, execute: execute_result) }

  subject(:execute) do
    described_class.new(
      workflow: workflow,
      current_user: user,
      item_consumer: consumer,
      service_account: service_account
    ).execute
  end

  before do
    allow(user).to receive(:can?).and_call_original
    allow(user).to receive(:can?).with(:restart_duo_workflow, workflow).and_return(allowed)
    allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(flows_execute_service)
  end

  context 'when the user is not allowed to restart the workflow' do
    let(:allowed) { false }

    it 'returns a forbidden error without starting anything', :aggregate_failures do
      expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

      expect(execute).to be_error
      expect(execute.reason).to eq(:forbidden)
    end
  end

  %i[failed stopped].each do |status|
    context "when the workflow is #{status}" do
      let(:workflow) { create(:duo_workflows_workflow, status, **original_attributes) }

      it 'starts a new session with the parameters of the original one', :aggregate_failures do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: {
            item_consumer: consumer,
            service_account: service_account,
            execute_workflow: true,
            event_type: 'mention',
            user_prompt: 'Fix the bug',
            issue_id: issue.iid,
            merge_request_id: nil,
            messaging_callback_context: callback_context,
            workflow_attributes: {
              agent_privileges: [privileges::READ_WRITE_FILES, privileges::READ_ONLY_GITLAB],
              pre_approved_agent_privileges: [privileges::READ_WRITE_FILES],
              image: 'ruby:3.3',
              web_search_enabled: true,
              trigger_source: 'system',
              trigger_flow_trigger_id: flow_trigger.id,
              trigger_flow_schedule_id: nil,
              trigger_event_type: 'mention',
              source_type: 'slack',
              source_link: 'https://slack.example.com/t/1'
            }
          }
        ).and_return(flows_execute_service)

        expect(execute).to be_success
        expect(execute.payload).to eq(workflow: new_workflow, workload_id: 123)
      end

      it 'leaves the original workflow untouched', :aggregate_failures do
        execute

        workflow.reload
        expect(workflow.status_name).to eq(status)
        expect(workflow.summary).to eq('It broke')
      end

      it 'holds the lease for the workflow and keeps it after success' do
        expect_to_obtain_exclusive_lease(lease_key, 'uuid', timeout: described_class::LEASE_TTL.to_i)
        expect(Gitlab::ExclusiveLease).not_to receive(:cancel)

        expect(execute).to be_success
      end

      context 'when the original callback context carries per-run adapter state' do
        let(:callback_context) do
          {
            'adapter' => 'slack',
            'channel' => 'C123',
            'delivered_at' => '2026-09-16T10:00:00Z',
            'started_note_id' => 11,
            'status_ts' => '1.2',
            'session_url' => 'http://example.com/old',
            'workflow_id' => 99,
            'progress_cursor' => 7
          }
        end

        it 'passes only the adapter identity on to the new session' do
          expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
            project: project,
            current_user: user,
            params: hash_including(messaging_callback_context: { 'adapter' => 'slack', 'channel' => 'C123' })
          ).and_return(flows_execute_service)

          expect(execute).to be_success
        end
      end

      context 'when the new session has a messaging callback context' do
        let(:new_context) { { 'adapter' => 'gitlab_duo_note', 'note_id' => 1, 'note_author_id' => 2 } }
        let(:new_workflow) do
          create(:duo_workflows_workflow, :running, user: user, project: project, goal: 'Fix the bug',
            messaging_callback_context: new_context)
        end

        it 'fires the adapter enqueued hook for the new session' do
          expect_next_instance_of(::Ai::Messaging::Adapters::GitlabDuoNote) do |adapter|
            expect(adapter).to receive(:on_flow_enqueued).with(callback_context: new_context, workflow: new_workflow)
          end

          expect(execute).to be_success
        end

        it 'tracks a failing hook and still succeeds', :aggregate_failures do
          allow_next_instance_of(::Ai::Messaging::Adapters::GitlabDuoNote) do |adapter|
            allow(adapter).to receive(:on_flow_enqueued).and_raise(StandardError, 'hook failed')
          end

          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(StandardError), workflow_id: new_workflow.id)

          expect(execute).to be_success
        end

        context 'when the adapter is unknown' do
          let(:new_context) { { 'adapter' => 'unknown' } }

          it 'skips the hook' do
            expect(::Ai::Messaging::Adapters::GitlabDuoNote).not_to receive(:from_callback_context)

            expect(execute).to be_success
          end
        end
      end

      it 'creates an audit event pointing at both sessions' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'duo_session_restarted',
            author: user,
            scope: project,
            target: workflow,
            target_details: "#{workflow.workflow_definition} session #{workflow.id} restarted as #{new_workflow.id}",
            message: 'Restarted Duo session'
          )
        )

        execute
      end

      context 'when audit event creation fails' do
        before do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'audit failed')
        end

        it 'tracks the exception and still succeeds', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(StandardError), workflow_id: workflow.id)

          expect(execute).to be_success
        end
      end
    end
  end

  context 'when the original workflow was not started by a trigger' do
    let(:workflow) do
      create(:duo_workflows_workflow, :failed, **original_attributes.merge(trigger_event_type: nil))
    end

    it 'runs the new session as an API execution' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: project,
        current_user: user,
        params: hash_including(event_type: 'api_execution')
      ).and_return(flows_execute_service)

      expect(execute).to be_success
    end
  end

  context 'when the original workflow is linked to a merge request instead of an issue' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let(:workflow) do
      create(:duo_workflows_workflow, :failed, **original_attributes.merge(issue: nil, merge_request: merge_request))
    end

    it 'links the new session to the same merge request' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: project,
        current_user: user,
        params: hash_including(issue_id: nil, merge_request_id: merge_request.iid)
      ).and_return(flows_execute_service)

      expect(execute).to be_success
    end
  end

  # Runs the real ExecuteService path down to StartWorkflowService, so the
  # noteable is resolved by CreateWorkflowService the way it is in production.
  context 'when the new session is created through the real execution path' do
    let_it_be(:mention_note) { create(:note_on_issue, project: project, noteable: issue, author: user) }

    let(:oauth_token) { instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token') }
    let(:callback_context) do
      {
        'adapter' => 'gitlab_duo_note',
        'note_id' => mention_note.id,
        'note_author_id' => service_account.id,
        'started_note_id' => 11,
        'delivered_at' => '2026-09-16T10:00:00Z'
      }
    end

    before do
      enable_ai_catalog
      flow.latest_version.update!(release_date: 1.hour.ago)
      project.project_setting.update!(duo_features_enabled: true, duo_remote_flows_enabled: true)
      allow(user).to receive(:allowed_to_use?).and_return(true)
      allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_call_original
      # CreateWorkflowService refuses CI-backed flows when the project has no gitlab--duo runner.
      stub_duo_runner_available(true)

      allow_next_instance_of(Ai::UsageQuotaService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success)
      end

      allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
        allow(service).to receive_messages(
          generate_oauth_token_with_composite_identity_support:
            ServiceResponse.success(payload: { oauth_access_token: oauth_token }),
          generate_workflow_token:
            ServiceResponse.success(payload: { token: 'workflow-token', expires_at: 1.hour.from_now }),
          duo_agent_platform_feature_setting: nil
        )
      end

      allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workload_id: 456 }))
      end
    end

    it 'links the new session to the same issue as the original', :aggregate_failures do
      expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

      restarted = Ai::DuoWorkflows::Workflow.last
      expect(restarted.id).not_to eq(workflow.id)
      expect(restarted.issue_id).to eq(issue.id)
      expect(restarted.goal).to eq('Fix the bug')
    end

    it 'links the triggering note and posts a fresh progress note for the new session', :aggregate_failures do
      expect(execute).to be_success

      restarted = execute.payload[:workflow]
      expect(restarted.note_links.link_type_triggered.pluck(:note_id)).to eq([mention_note.id])

      context = restarted.reload.messaging_callback_context
      expect(context).not_to have_key('delivered_at')
      expect(context['started_note_id']).to be_present
      expect(context['started_note_id']).not_to eq(11)
      expect(Note.find(context['started_note_id'])).to have_attributes(noteable: issue, author: service_account)
    end
  end

  context 'when another restart of the same workflow is in progress' do
    before do
      stub_exclusive_lease_taken(lease_key)
    end

    it 'returns a conflict error without starting anything', :aggregate_failures do
      expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

      expect(execute).to be_error
      expect(execute.reason).to eq(:conflict)
    end
  end

  context 'when starting the new session fails' do
    let(:execute_result) { ServiceResponse.error(message: ['Something went wrong']) }

    it 'returns that error, releases the lease and skips the audit event', :aggregate_failures do
      expect_to_obtain_exclusive_lease(lease_key, 'uuid', timeout: described_class::LEASE_TTL.to_i)
      expect_to_cancel_exclusive_lease(lease_key, 'uuid')
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      expect(execute).to be_error
      expect(execute.message).to eq(['Something went wrong'])
    end
  end
end
