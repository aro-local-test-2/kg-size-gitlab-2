# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::CreateWorkflowService, feature_category: :duo_agent_platform do
  let_it_be(:default_organization) { create(:organization) }

  before do
    allow(::Organizations::Organization).to receive(:default_organization).and_return(default_organization)
  end

  describe '#execute' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:user) { create(:user, maintainer_of: project) }
    let(:container) { project }
    let(:params) { { environment: "ide" } }
    let(:execution) { nil }

    # Most examples exercise the client-facing entry points (GraphQL create, REST
    # POST /workflows), which mark their privileges as caller-supplied. Contexts
    # covering app-set privileges override this to false.
    let(:privileges_from_client) { true }

    subject(:execute) do
      described_class
        .new(
          container: container, current_user: user, params: params, execution: execution,
          privileges_from_client: privileges_from_client
        )
        .execute
    end

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :create_duo_workflow_for_ci, container).and_return(true)
      allow_next_instance_of(Ai::UsageQuotaService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.success
        )
      end
      # The precondition check (flag on by default) would otherwise refuse these flows: factory
      # projects have no gitlab--duo runner. The precondition contexts below re-stub as needed.
      stub_duo_runner_available(true)
    end

    it 'creates a new workflow' do
      expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

      expect(execute[:workflow]).to be_a(Ai::DuoWorkflows::Workflow)
      expect(execute[:workflow].user).to eq(user)
      expect(execute[:workflow].project).to eq(project)
    end

    describe 'goal size logging' do
      let(:params) { { environment: "ide", goal: 'a' * 10, workflow_definition: 'software_development' } }

      it 'logs the goal size' do
        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(
            'message' => 'Duo Workflow goal size',
            'goal_size' => 10,
            Labkit::Fields::DUO_WORKFLOW_DEFINITION => 'software_development'
          )
        )

        execute
      end

      context 'when the goal exceeds the maximum length' do
        let(:goal_size) { Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH + 1 }
        let(:params) { { environment: "ide", goal: 'a' * goal_size } }

        it 'logs the goal size even though the workflow fails validation' do
          expect(Gitlab::AppLogger).to receive(:info).with(hash_including('goal_size' => goal_size))

          expect { execute }.not_to change { Ai::DuoWorkflows::Workflow.count }
        end
      end

      context 'when the goal is blank' do
        let(:params) { { environment: "ide" } }

        it 'does not log' do
          expect(Gitlab::AppLogger).not_to receive(:info).with(hash_including('message' => 'Duo Workflow goal size'))

          execute
        end
      end
    end

    context 'when workflow_definition is provided', :saas do
      let(:params) { { environment: "ide", workflow_definition: 'sast_fp_detection/v1' } }

      before do
        allow(user.user_preference).to receive(:duo_default_namespace_with_fallback).and_return(group)
        allow(::Gitlab::SubscriptionPortal::Client).to receive(:verify_usage_quota).and_return({ success: true })

        allow_next_instance_of(Ai::UsageQuotaService) do |instance|
          allow(instance).to receive(:execute).and_call_original
        end
      end

      it 'creates a workflow successfully' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
        expect(execute[:status]).to eq(:success)
      end

      it 'performs quota check using the workflow-specific feature name' do
        expect(::Gitlab::SubscriptionPortal::Client).to receive(:verify_usage_quota).with(hash_including(
          event_type: :rails_on_ui_check,
          feature_qualified_name: 'sast_fp_detection/v1',
          feature_ai_catalog_item: false
        )).and_return({ success: true })

        execute
      end
    end

    context 'when flow is gated behind a feature flag' do
      let(:params) { { environment: 'ide', workflow_definition: 'risk_classification/v1' } }
      let(:foundational_flow) { ::Ai::Catalog::FoundationalFlow.risk_classification_v1 }

      before do
        allow(foundational_flow)
          .to receive(:blocked_by_feature_flag?)
          .with(group.root_ancestor)
          .and_return(flow_blocked_by_feature_flag)
      end

      context 'when feature flag is disabled' do
        let(:flow_blocked_by_feature_flag) { true }

        it 'refuses to create the session' do
          expect { execute }.not_to change { Ai::DuoWorkflows::Workflow.count }
          expect(execute).to be_error
          expect(execute.message).to eq('This flow is not available')
          expect(execute.http_status).to eq(:forbidden)
          expect(foundational_flow).to have_received(:blocked_by_feature_flag?).with(group.root_ancestor)
        end
      end

      context 'when feature flag is enabled' do
        let(:flow_blocked_by_feature_flag) { false }

        it 'creates the session' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute).to be_success
          expect(foundational_flow).to have_received(:blocked_by_feature_flag?).with(group.root_ancestor)
        end
      end
    end

    context 'with the precondition check (duo_workflow_precondition_check)', :aggregate_failures do
      # container is the project and execution is nil, so the flow is treated as CI-backed and
      # checked. The flag defaults on in specs, so the enabled path needs no stub.
      before do
        # The dropped-session status update is authorized to the flow owner (the current user).
        allow(Ability).to receive(:allowed?).with(user, :update_duo_workflow, anything).and_return(true)
      end

      context 'when no eligible runner is available' do
        before do
          stub_duo_runner_available(false)
          allow(project.ci_minutes_usage).to receive(:minutes_used_up?).and_return(false)
        end

        it 'creates the session, drops it, and returns an error naming the reason' do
          expect(::Ai::DuoWorkflows::UpdateWorkflowStatusService).to receive(:new)
            .with(hash_including(status_event: 'drop', reason: a_string_including('gitlab--duo')))
            .and_call_original

          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

          expect(execute).to be_error
          expect(execute.payload[:reason]).to eq(:no_eligible_runner)
          expect(execute[:http_status]).to eq(:unprocessable_entity)
          expect(execute.message).to include('no runner available')

          workflow = Ai::DuoWorkflows::Workflow.order(:id).last
          expect(workflow).to be_failed
          expect(workflow.summary).to be_present
        end
      end

      context 'when the drop itself fails' do
        before do
          stub_duo_runner_available(false)
          allow(project.ci_minutes_usage).to receive(:minutes_used_up?).and_return(false)
          allow_next_instance_of(::Ai::DuoWorkflows::UpdateWorkflowStatusService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Can not drop workflow', reason: :bad_request)
            )
          end
        end

        it 'tracks the exception so a session left stuck in created is visible' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(described_class::CouldNotDropWorkflowError),
            hash_including(reason: :no_eligible_runner)
          )

          expect(execute).to be_error
        end
      end

      context 'when the drop raises' do
        before do
          stub_duo_runner_available(false)
          allow(project.ci_minutes_usage).to receive(:minutes_used_up?).and_return(false)
          allow_next_instance_of(::Ai::DuoWorkflows::UpdateWorkflowStatusService) do |svc|
            allow(svc).to receive(:execute).and_raise(StandardError, 'boom')
          end
        end

        it 'still returns the error and tracks the raised exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(StandardError),
            hash_including(reason: :no_eligible_runner)
          )

          expect(execute).to be_error
          expect(execute.payload[:reason]).to eq(:no_eligible_runner)
          expect(execute[:http_status]).to eq(:unprocessable_entity)
        end
      end

      context 'when the readiness probe raises' do
        before do
          allow(::Ai::DuoWorkflow::ProjectReadiness).to receive(:new).and_raise(StandardError, 'boom')
        end

        it 'fails open: tracks the error and still creates the session' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(StandardError), hash_including(workflow_id: kind_of(Integer))
          )

          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute).to be_success
        end
      end

      context 'when no runner is available and the namespace is out of compute minutes' do
        before do
          stub_duo_runner_available(false)
          allow(project.ci_minutes_usage).to receive(:minutes_used_up?).and_return(true)
        end

        it 'reports the out-of-minutes reason' do
          expect(execute).to be_error
          expect(execute.payload[:reason]).to eq(:namespace_ci_minutes_used_up)
          expect(execute[:http_status]).to eq(:unprocessable_entity)
          expect(Ai::DuoWorkflows::Workflow.order(:id).last).to be_failed
        end
      end

      context 'when the namespace is out of compute minutes but a usable runner exists' do
        before do
          stub_duo_runner_available(true)
          allow(project.ci_minutes_usage).to receive(:minutes_used_up?).and_return(true)
        end

        it 'creates the session: a top-level group runner still runs the job when minutes are exhausted' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

          expect(execute).to be_success
          expect(Ai::DuoWorkflows::Workflow.order(:id).last).not_to be_failed
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(duo_workflow_precondition_check: false)
          stub_duo_runner_available(false)
        end

        it 'does not run the check and creates the session' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute).to be_success
        end
      end

      context 'when the session is client-executed' do
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::CLIENT }

        before do
          stub_duo_runner_available(false)
        end

        it 'skips the check and creates the session' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute).to be_success
        end
      end
    end

    context 'when service_account is provided' do
      let_it_be(:service_account) { create(:service_account) }
      let(:params) { { environment: "ide", service_account: service_account } }

      it 'creates a workflow with the service_account' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        workflow = execute[:workflow]
        expect(workflow.service_account).to eq(service_account)
        expect(workflow.service_account_id).to eq(service_account.id)
      end
    end

    context 'when service_account is not provided' do
      let(:params) { { environment: "ide" } }

      it 'creates a workflow without service_account' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        workflow = execute[:workflow]
        expect(workflow.service_account).to be_nil
        expect(workflow.service_account_id).to be_nil
      end
    end

    it 'creates the workflow with incremental checkpoints enabled' do
      expect(execute[:workflow].incremental_checkpoints_enabled).to be(true)
    end

    it 'sends session create event without source when source is not provided' do
      expect { execute }.to trigger_internal_events("agent_platform_session_created")
                              .with(category: "Ai::DuoWorkflows::CreateWorkflowService",
                                user: user,
                                project: project,
                                additional_properties: {
                                  label: "software_development",
                                  value: be_a(Integer),
                                  property: "ide"
                                }
                              )
    end

    context 'when source param is provided' do
      let(:params) { { environment: "ide", source: "merge_request_code_conflict" } }

      it 'sends session create event with source in additional_properties' do
        expect { execute }.to trigger_internal_events("agent_platform_session_created")
                                .with(category: "Ai::DuoWorkflows::CreateWorkflowService",
                                  user: user,
                                  project: project,
                                  additional_properties: {
                                    label: "software_development",
                                    value: be_a(Integer),
                                    property: "ide",
                                    source: "merge_request_code_conflict"
                                  }
                                )
      end

      it 'persists source as source_type on the workflow' do
        result = execute

        expect(result[:status]).to eq(:success)
        expect(result[:workflow]).to be_persisted
        expect(result[:workflow].source_type).to eq('merge_request_code_conflict')
      end
    end

    context 'when source_type param is provided by an internal caller' do
      let(:params) { { environment: "ide", source_type: :slack } }

      it 'sends session create event with source in additional_properties' do
        expect { execute }.to trigger_internal_events("agent_platform_session_created")
                                .with(category: "Ai::DuoWorkflows::CreateWorkflowService",
                                  user: user,
                                  project: project,
                                  additional_properties: {
                                    label: "software_development",
                                    value: be_a(Integer),
                                    property: "ide",
                                    source: "slack"
                                  }
                                )
      end

      it 'persists source_type on the workflow' do
        expect(execute[:workflow].source_type).to eq('slack')
      end
    end

    context 'when source param is an unknown value' do
      let(:params) { { environment: "ide", source: "unknown_source" } }

      it 'creates the workflow without setting source_type' do
        result = execute

        expect(result[:status]).to eq(:success)
        expect(result[:workflow]).to be_persisted
        expect(result[:workflow].source_type).to be_nil
      end

      it 'sends session create event without source' do
        expect { execute }.to trigger_internal_events("agent_platform_session_created")
                                .with(category: "Ai::DuoWorkflows::CreateWorkflowService",
                                  user: user,
                                  project: project,
                                  additional_properties: {
                                    label: "software_development",
                                    value: be_a(Integer),
                                    property: "ide"
                                  }
                                )
      end
    end

    context 'when source param is not provided' do
      it 'creates the workflow without setting source_type' do
        result = execute

        expect(result[:status]).to eq(:success)
        expect(result[:workflow]).to be_persisted
        expect(result[:workflow].source_type).to be_nil
      end
    end

    it 'creates an audit event' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: 'duo_session_created',
          author: user,
          scope: project,
          target: be_a(Ai::DuoWorkflows::Workflow),
          message: 'Created Duo session'
        )
      )

      execute
    end

    context 'when audit event creation fails' do
      let(:audit_error) { StandardError.new('Audit service unavailable') }

      before do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(audit_error)
      end

      it 'tracks the exception and workflow creation continues successfully' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          audit_error,
          hash_including(workflow_id: be_a(Integer))
        )

        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
        expect(execute[:status]).to eq(:success)
      end

      it 'does not fail the workflow creation' do
        result = execute

        expect(result[:status]).to eq(:success)
        expect(result[:workflow]).to be_persisted
      end
    end

    describe 'workflow title generation' do
      it 'enqueues the title worker' do
        expect(Ai::DuoWorkflows::GenerateWorkflowTitleWorker).to receive(:perform_async).with(Integer)

        execute
      end
    end

    context 'when trigger_source is verification' do
      let(:params) { { environment: "ide", trigger_source: :verification } }

      it 'creates the workflow without checking the usage quota' do
        expect(Ai::UsageQuotaService).not_to receive(:new)

        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
        expect(execute[:status]).to eq(:success)
      end

      it 'does not enqueue the title worker' do
        expect(Ai::DuoWorkflows::GenerateWorkflowTitleWorker).not_to receive(:perform_async)

        execute
      end

      it 'marks the workflow as triggered by verification' do
        expect(execute[:workflow]).to be_triggered_by_verification
      end

      it 'prefixes the audit event target_details' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(target_details: a_string_starting_with('[Verification Run] '))
        )

        execute
      end

      it 'includes verification_run in the audit event additional_details' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(additional_details: { verification_run: true })
        )

        execute
      end

      it 'sends session create event with verification_run in additional_properties' do
        expect { execute }.to trigger_internal_events("agent_platform_session_created")
                                .with(category: "Ai::DuoWorkflows::CreateWorkflowService",
                                  user: user,
                                  project: project,
                                  additional_properties: {
                                    label: "software_development",
                                    value: be_a(Integer),
                                    property: "ide",
                                    verification_run: "true"
                                  }
                                )
      end
    end

    describe 'session artifact sync' do
      context 'when ClickHouse is not enabled for analytics' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        it 'enqueues the sync worker' do
          expect(Ai::DuoWorkflows::SyncSessionArtifactWorker).to receive(:perform_async).with(Integer)

          execute
        end
      end

      context 'when ClickHouse is enabled for analytics' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
        end

        it 'does not enqueue the sync worker' do
          expect(Ai::DuoWorkflows::SyncSessionArtifactWorker).not_to receive(:perform_async)

          execute
        end
      end
    end

    context 'when namespace-level workflow',
      skip: 'Not yet supported. See https://gitlab.com/gitlab-org/gitlab/-/issues/554952' do
      let(:container) { group }

      it 'creates a new workflow' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
        expect(execute[:workflow]).to be_a(Ai::DuoWorkflows::Workflow)
        expect(execute[:workflow].user).to eq(user)
        expect(execute[:workflow].namespace).to eq(group)
      end
    end

    context 'when user cannot execute asynchronous duo workflows' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :create_duo_workflow_for_ci, container).and_return(false)
      end

      it 'returns error' do
        expect(execute[:status]).to eq(:error)
        expect(execute[:http_status]).to eq(:forbidden)
        expect(execute[:message]).to include('forbidden to access duo workflow')
      end
    end

    describe 'the access check chosen for the execution mode' do
      # :create_duo_workflow_for_ci carries the minimum role required for asynchronous
      # execution, which a run the caller performs itself is not.
      context 'when the run is client-executed' do
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::CLIENT }

        # Already authorized by FlowExecutionAuthorizer; a second check would refuse a
        # valid seat used outside its own namespace (https://gitlab.com/gitlab-org/gitlab/-/issues/623975).
        it 'skips the workflow entitlement check' do
          expect(Ability).not_to receive(:allowed?).with(user, :duo_workflow, container)
          expect(Ability).not_to receive(:allowed?).with(user, :create_duo_workflow_for_ci, container)

          expect(execute[:status]).to eq(:success)
        end
      end

      context 'when a chat run is client-executed' do
        let(:params) { { workflow_definition: 'chat' } }
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::CLIENT }

        it 'still runs the agentic chat access check' do
          expect(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(true)

          execute
        end
      end

      shared_examples 'keeps :create_duo_workflow_for_ci' do
        it 'keeps :create_duo_workflow_for_ci' do
          expect(Ability).not_to receive(:allowed?).with(user, :duo_workflow, container)

          expect(execute[:status]).to eq(:success)
        end
      end

      context 'when the run is unclassified' do
        let(:execution) { nil }

        it_behaves_like 'keeps :create_duo_workflow_for_ci'
      end

      context 'when the run is a background run' do
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::BACKGROUND }

        it_behaves_like 'keeps :create_duo_workflow_for_ci'
      end

      context 'when a caller passes a raw symbol the authorizer did not mint' do
        let(:execution) { :client }

        it_behaves_like 'keeps :create_duo_workflow_for_ci'
      end
    end

    describe 'the persisted execution_mode' do
      context 'when the run is client-executed' do
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::CLIENT }

        before do
          allow(Ability).to receive(:allowed?).with(user, :duo_workflow, container).and_return(true)
        end

        it 'records client' do
          expect(execute[:workflow].execution_mode).to eq('client')
        end
      end

      context 'when the run is a background run' do
        let(:execution) { ::Ai::DuoWorkflows::FlowExecutionAuthorizer::Classification::BACKGROUND }

        it 'records background' do
          expect(execute[:workflow].execution_mode).to eq('background')
        end
      end

      context 'when the run is unclassified' do
        let(:execution) { nil }

        it 'leaves the mode unset, so surface resolution keeps its environment fallback' do
          expect(execute[:workflow].execution_mode).to be_nil
        end
      end

      context 'when a caller passes a raw symbol the authorizer did not mint' do
        let(:execution) { :client }

        it 'leaves the mode unset' do
          expect(execute[:workflow].execution_mode).to be_nil
        end
      end

      context 'when the request params carry an execution_mode' do
        let(:params) { { environment: 'ide', execution_mode: :background } }

        it 'ignores it, so the value can only come from the classification' do
          expect(execute[:workflow].execution_mode).to be_nil
        end
      end
    end

    context 'when credit check fails' do
      context 'with user missing' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "User is required", reason: :user_missing)
            )
          end
        end

        it 'returns bad request error' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:bad_request)
          expect(execute[:message]).to include('User is required')
        end
      end

      context 'with namespace missing' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Namespace is required", reason: :namespace_missing)
            )
          end
        end

        it 'returns bad request error with actionable message' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:bad_request)
          expect(execute[:message]).to include(user.to_reference)
          expect(execute[:message]).to include('default GitLab Duo namespace')
          expect(execute[:message]).to include('preferences')
          expect(execute.payload[:reason]).to eq(:namespace_missing)
        end
      end

      context 'when usage quota is exceeded' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Usage quota exceeded", reason: :usage_quota_exceeded)
            )
          end
        end

        it 'returns payment required error' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:payment_required)
          expect(execute[:message]).to include('Usage quota exceeded')
          expect(execute.payload[:reason]).to eq(:usage_quota_exceeded)
        end
      end

      context 'when usage billing is forbidden' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Usage billing not available", reason: :usage_billing_forbidden)
            )
          end
        end

        it 'returns forbidden error with user-facing message' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:forbidden)
          expect(execute[:message]).to include('contact your administrator')
          expect(execute.payload[:reason]).to eq(:usage_billing_forbidden)
        end
      end

      context 'with generic error' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Something went wrong", reason: :some_error)
            )
          end
        end

        it 'returns internal server error' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:internal_server_error)
          expect(execute[:message]).to include('Something went wrong')
        end
      end
    end

    context 'when container is not supported' do
      let(:container) { create(:ci_empty_pipeline) }

      it 'returns error' do
        expect(execute[:status]).to eq(:error)
        expect(execute[:http_status]).to eq(:bad_request)
        expect(execute[:message]).to include('container must be a Project or Namespace')
      end
    end

    context 'when workflow definition is chat' do
      let(:params) { { workflow_definition: 'chat' } }

      before do
        allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(true)
      end

      it 'creates a new workflow' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
        expect(execute[:workflow]).to be_a(Ai::DuoWorkflows::Workflow)
        expect(execute[:workflow].user).to eq(user)
        expect(execute[:workflow].project).to eq(project)
      end

      context 'when user cannot access duo agentic chat' do
        before do
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(false)
        end

        it 'returns error' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:forbidden)
          expect(execute[:message]).to include('forbidden to access agentic chat')
        end
      end

      describe 'ultimate_only agent enforcement' do
        include_context 'with mocked Foundational Chat Agents'

        let(:ultimate_only_agent) do
          { id: 99, reference: 'ultimate_agent', version: 'v1', name: 'Ultimate Agent',
            description: 'Ultimate only agent', ultimate_only: true }
        end

        let(:mocked_foundational_chat_agents) do
          [foundational_duo_chat_agent, foundational_chat_agent_1, ultimate_only_agent]
        end

        let(:params) { { workflow_definition: 'ultimate_agent/v1' } }

        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(true)
          allow(user.user_preference).to receive(:duo_default_namespace_with_fallback).and_return(group)
          allow(group).to receive(:foundational_agent_enabled?).with('ultimate_agent').and_return(true)
        end

        context 'when the namespace does not have Ultimate plan' do
          before do
            allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(false)
          end

          it 'returns forbidden error' do
            expect(execute[:status]).to eq(:error)
            expect(execute[:http_status]).to eq(:forbidden)
            expect(execute[:message]).to include('agent requires Ultimate plan')
          end
        end

        context 'when the namespace has only a Premium plan' do
          before do
            allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(false)
            allow(group).to receive(:licensed_feature_available?).with(:ai_catalog).and_return(true)
          end

          it 'returns forbidden error' do
            expect(execute[:status]).to eq(:error)
            expect(execute[:http_status]).to eq(:forbidden)
            expect(execute[:message]).to include('agent requires Ultimate plan')
          end
        end

        context 'when the namespace has Ultimate plan' do
          before do
            allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
          end

          it 'creates the workflow' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          end
        end

        context 'when the agent is not found (e.g. feature-flagged out)' do
          before do
            allow(Ai::FoundationalChatAgent).to receive(:with_workflow_definition).and_return(nil)
            allow(group).to receive(:foundational_agent_enabled?).with('ultimate_agent').and_return(true)
          end

          it 'skips ultimate_only check and creates the workflow' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          end
        end
      end

      describe 'validates foundational agent' do
        include_context 'with mocked Foundational Chat Agents'

        let_it_be(:default_group_namespace) { create(:group) }
        let(:params) { { workflow_definition: foundational_chat_agent_1_workflow_definition } }
        let(:default_namespace) { default_group_namespace }
        let(:is_saas) { true }

        before do
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(true)
          stub_saas_features(gitlab_com_subscriptions: is_saas)
          allow(user.user_preference).to receive(:duo_default_namespace_with_fallback).and_return(default_namespace)
        end

        shared_examples 'the agent is disabled' do
          it 'returns error with agent disabled' do
            expect(execute[:status]).to eq(:error)
            expect(execute[:http_status]).to eq(:forbidden)
            expect(execute[:message]).to include('foundation agent disabled for namespace')
          end
        end

        shared_examples 'the workflow is created' do
          it 'creates the workflow' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
            expect(execute[:workflow]).to be_a(Ai::DuoWorkflows::Workflow)
          end
        end

        context 'when is SaaS' do
          context 'when has default namespace' do
            context 'when disabled on default namespace' do
              before do
                allow(default_namespace).to receive(:foundational_agent_enabled?)
                                              .with(foundational_chat_agent_1_ref)
                                              .and_return(false)
              end

              it_behaves_like 'the agent is disabled'
            end

            context 'when enabled on default namespace' do
              before do
                allow(default_namespace).to receive(:foundational_agent_enabled?)
                                              .with(foundational_chat_agent_1_ref)
                                              .and_return(true)
              end

              it_behaves_like 'the workflow is created'
            end

            context 'when namespace is not nil' do
              let(:container) { group }

              context 'when enabled on default namespace' do
                before do
                  allow(default_namespace).to receive(:foundational_agent_enabled?)
                                                .with(foundational_chat_agent_1_ref)
                                                .and_return(true)
                end

                it_behaves_like 'the workflow is created'
              end

              context 'when disabled on default namespace' do
                before do
                  allow(default_namespace).to receive(:foundational_agent_enabled?)
                                                .with(foundational_chat_agent_1_ref)
                                                .and_return(false)
                end

                it_behaves_like 'the agent is disabled'
              end
            end
          end

          context 'when does not have default namespace' do
            let(:default_namespace) { nil }

            context 'when namespace is not nil' do
              let(:subgroup) { create(:group, parent: group) }
              let(:container) { subgroup }

              context 'when enabled on namespace' do
                before do
                  subgroup.add_guest(user)
                  allow(group).to receive(:foundational_agent_enabled?)
                                    .with(foundational_chat_agent_1_ref)
                                    .and_return(true)
                end

                it_behaves_like 'the workflow is created'
              end
            end

            context 'when project is not nil' do
              let(:container) { project }

              context 'when enabled on project parent' do
                before do
                  project.parent.add_guest(user)
                  allow(group).to receive(:foundational_agent_enabled?)
                                    .with(foundational_chat_agent_1_ref)
                                    .and_return(true)
                end

                it_behaves_like 'the workflow is created'
              end

              context 'when disabled on project parent' do
                before do
                  allow(group).to receive(:foundational_agent_enabled?)
                                    .with(foundational_chat_agent_1_ref)
                                    .and_return(false)
                end

                it_behaves_like 'the agent is disabled'
              end
            end
          end
        end

        context 'when is not SaaS' do
          let(:is_saas) { false }

          context 'when disabled on organization' do
            before do
              allow(default_organization).to receive(:foundational_agent_enabled?)
                                               .with(foundational_chat_agent_1_ref)
                                               .and_return(false)
            end

            it_behaves_like 'the agent is disabled'
          end

          context 'when enabled on organization' do
            before do
              allow(default_organization).to receive(:foundational_agent_enabled?)
                                               .with(foundational_chat_agent_1_ref)
                                               .and_return(true)
            end

            it_behaves_like 'the workflow is created'
          end
        end
      end
    end

    context 'when container is nil' do
      let(:container) { nil }

      it 'returns error' do
        allow(user.user_preference).to receive(:duo_default_namespace_with_fallback).and_return(nil)

        expect(execute[:status]).to eq(:error)
        expect(execute[:http_status]).to eq(:bad_request)
        expect(execute[:message]).to include('container must be a Project or Namespace')
      end
    end

    context 'when the workflow cannot be saved' do
      before do
        allow_next_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
          allow(instance).to receive(:save).and_return(false)
          instance.errors.add(:base, "Something bad")
        end
      end

      it 'returns an error' do
        expect(execute[:status]).to eq(:error)
        expect(execute[:message]).to eq('Something bad')
      end
    end

    context 'when project_id or namespace_id are provided in params' do
      let(:params) { { environment: "ide", project_id: project.id, namespace_id: group.id } }

      it 'ignores both ids and creates workflow using container' do
        expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        workflow = execute[:workflow]
        expect(workflow.project).to eq(container)
        expect(workflow.namespace).to be_nil
      end
    end

    context 'when ai_catalog_item_version is provided' do
      let_it_be_with_reload(:ai_catalog_item) { create(:ai_catalog_item) }
      let_it_be_with_reload(:ai_catalog_item_version) { create(:ai_catalog_item_version, item: ai_catalog_item) }
      let(:params) { { environment: "ide", ai_catalog_item_version: ai_catalog_item_version } }

      context 'when user has access to the AI catalog item' do
        before do
          allow_next_instance_of(Ai::Catalog::ItemConsumersFinder) do |finder|
            allow(finder).to receive(:execute).and_return(class_double(::Ai::Catalog::ItemConsumer, exists?: true))
          end
        end

        it 'creates a new workflow' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute[:workflow]).to be_a(Ai::DuoWorkflows::Workflow)
          expect(execute[:workflow].ai_catalog_item_version).to eq(ai_catalog_item_version)
        end
      end

      context 'when user does not have access to the AI catalog item' do
        before do
          allow_next_instance_of(Ai::Catalog::ItemConsumersFinder) do |finder|
            allow(finder).to receive(:execute).and_return(class_double(::Ai::Catalog::ItemConsumer, exists?: false))
          end
        end

        it 'returns error' do
          expect(execute[:status]).to eq(:error)
          expect(execute[:http_status]).to eq(:not_found)
          expect(execute[:message]).to include('ItemVersion not found')
        end
      end

      context 'with namespace-level workflow' do
        let(:container) { group }

        before do
          allow_next_instance_of(Ai::Catalog::ItemConsumersFinder) do |finder|
            allow(finder).to receive(:execute).and_return(class_double(::Ai::Catalog::ItemConsumer, exists?: true))
          end
        end

        it 'passes group_id to ItemConsumersFinder' do
          expect(Ai::Catalog::ItemConsumersFinder).to receive(:new).with(
            user,
            params: hash_including(group_id: group.id, item_id: ai_catalog_item.id)
          )

          execute
        end
      end

      context 'with project-level workflow' do
        before do
          allow_next_instance_of(Ai::Catalog::ItemConsumersFinder) do |finder|
            allow(finder).to receive(:execute).and_return(class_double(::Ai::Catalog::ItemConsumer, exists?: true))
          end
        end

        it 'passes project_id to ItemConsumersFinder' do
          expect(Ai::Catalog::ItemConsumersFinder).to receive(:new).with(
            user,
            params: hash_including(project_id: project.id, item_id: ai_catalog_item.id)
          )

          execute
        end
      end
    end

    context 'when a foundational flow is created without a catalog item version' do
      let_it_be_with_reload(:flow_catalog_item) do
        create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1')
      end

      let(:params) { { environment: "web", workflow_definition: 'fix_pipeline/v1', goal: "no pipeline here" } }

      before do
        # FoundationalFlow[] is a process-wide instance that memoizes catalog_item across examples.
        ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1.clear_memoization(:catalog_item)
      end

      it 'links the workflow to the latest released version of the flow catalog item' do
        released_version = create(:ai_catalog_flow_version, :released, item: flow_catalog_item)

        expect(execute).to be_success
        expect(execute[:workflow].ai_catalog_item_version).to eq(released_version)
      end

      it 'falls back to the latest version when it is released' do
        fallback_version = create(:ai_catalog_flow_version, :released, item: flow_catalog_item)
        flow_catalog_item.update!(latest_released_version: nil)

        expect(execute).to be_success
        expect(execute[:workflow].ai_catalog_item_version).to eq(fallback_version)
      end

      it 'stores no version when the flow catalog item has no released version' do
        flow_catalog_item.latest_version.update!(release_date: nil)

        expect(execute).to be_success
        expect(execute[:workflow].ai_catalog_item_version).to be_nil
      end

      it 'does not check caller access to the server-resolved version' do
        create(:ai_catalog_flow_version, :released, item: flow_catalog_item)

        expect(Ai::Catalog::ItemConsumersFinder).not_to receive(:new)

        expect(execute).to be_success
      end

      # Ai::Catalog::ExecuteWorkflowService always sends the key, nil when it has no version.
      context 'when the caller passes an explicit nil version id' do
        let(:params) { super().merge(ai_catalog_item_version_id: nil) }

        it 'still resolves the flow catalog item version' do
          released_version = create(:ai_catalog_flow_version, :released, item: flow_catalog_item)

          expect(execute).to be_success
          expect(execute[:workflow].ai_catalog_item_version).to eq(released_version)
        end
      end

      context 'when the caller passes an explicit nil version record' do
        let(:params) { super().merge(ai_catalog_item_version: nil) }

        it 'still resolves the flow catalog item version' do
          released_version = create(:ai_catalog_flow_version, :released, item: flow_catalog_item)

          expect(execute).to be_success
          expect(execute[:workflow].ai_catalog_item_version).to eq(released_version)
        end
      end

      context 'when a catalog item version is provided explicitly' do
        let_it_be_with_reload(:explicit_item) { create(:ai_catalog_item) }
        let_it_be(:explicit_version) { create(:ai_catalog_item_version, item: explicit_item) }
        let_it_be(:released_flow_version) { create(:ai_catalog_flow_version, :released, item: flow_catalog_item) }

        before do
          allow_next_instance_of(Ai::Catalog::ItemConsumersFinder) do |finder|
            allow(finder).to receive(:execute).and_return(class_double(::Ai::Catalog::ItemConsumer, exists?: true))
          end
        end

        context 'as a record' do
          let(:params) { super().merge(ai_catalog_item_version: explicit_version) }

          it 'keeps the explicit version' do
            expect(execute).to be_success
            expect(execute[:workflow].ai_catalog_item_version).to eq(explicit_version)
          end
        end

        context 'as an id' do
          let(:params) { super().merge(ai_catalog_item_version_id: explicit_version.id) }

          it 'keeps the explicit version' do
            expect(execute).to be_success
            expect(execute[:workflow].ai_catalog_item_version).to eq(explicit_version)
          end
        end
      end

      context 'when the workflow definition is not a foundational flow' do
        let(:params) { { environment: "ide", workflow_definition: 'software_development' } }

        it 'stores no version' do
          expect(execute).to be_success
          expect(execute[:workflow].ai_catalog_item_version).to be_nil
        end
      end
    end

    context 'when linking a flow to its source work item' do
      let_it_be(:issue) { create(:issue, project: project) }
      let(:params) { { environment: "web", issue_id: issue.iid } }

      it 'records a source link to the work item' do
        expect { execute }.to change { Ai::DuoWorkflows::WorkflowWorkItem.count }.by(1)

        link = Ai::DuoWorkflows::WorkflowWorkItem.order(:id).last
        expect(link).to have_attributes(
          workflow: execute[:workflow],
          work_item_id: issue.id,
          link_type: 'source'
        )
      end

      it 'does not fail workflow creation when linking raises' do
        allow_next_instance_of(::Ai::DuoWorkflows::LinkArtifactService) do |service|
          allow(service).to receive(:execute).and_raise(StandardError, 'boom')
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id))

        expect(execute[:status]).to eq(:success)
      end

      it 'does not fail workflow creation when reading the work item association raises' do
        allow_next_instance_of(::Ai::DuoWorkflows::Workflow) do |workflow|
          allow(workflow).to receive(:work_item).and_raise(StandardError, 'boom')
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id))

        expect { expect(execute[:status]).to eq(:success) }
          .not_to change { Ai::DuoWorkflows::WorkflowWorkItem.count }
      end

      context 'with the developer flow' do
        let(:params) do
          {
            environment: "web",
            workflow_definition: "developer/v1",
            issue_id: issue.iid
          }
        end

        it 'also records a source link to the work item' do
          expect { execute }.to change { Ai::DuoWorkflows::WorkflowWorkItem.count }.by(1)
        end
      end

      context 'when there is no associated work item' do
        let(:params) { { environment: "web" } }

        it 'does not record a work item link' do
          expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowWorkItem.count }
        end
      end
    end

    context 'when linking a flow to its source merge request' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let(:params) { { environment: "web", merge_request_id: merge_request.iid } }

      it 'records a source link to the merge request' do
        expect { execute }.to change { Ai::DuoWorkflows::WorkflowMergeRequest.count }.by(1)

        link = Ai::DuoWorkflows::WorkflowMergeRequest.order(:id).last
        expect(link).to have_attributes(
          workflow: execute[:workflow],
          merge_request_id: merge_request.id,
          link_type: 'source'
        )
      end

      it 'does not fail workflow creation when linking raises' do
        allow_next_instance_of(::Ai::DuoWorkflows::LinkArtifactService) do |service|
          allow(service).to receive(:execute).and_raise(StandardError, 'boom')
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id))

        expect(execute[:status]).to eq(:success)
      end

      it 'does not fail workflow creation when reading the merge request association raises' do
        allow_next_instance_of(::Ai::DuoWorkflows::Workflow) do |workflow|
          allow(workflow).to receive(:merge_request).and_raise(StandardError, 'boom')
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id))
          .at_least(:once)

        expect { expect(execute[:status]).to eq(:success) }
          .not_to change { Ai::DuoWorkflows::WorkflowMergeRequest.count }
      end

      context 'when there is no associated merge request' do
        let(:params) { { environment: "web" } }

        it 'does not record a merge request link' do
          expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowMergeRequest.count }
        end
      end
    end

    context 'when linking a flow to its source pipeline' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
      let(:params) do
        {
          environment: "web",
          workflow_definition: 'fix_pipeline/v1',
          goal: "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}"
        }
      end

      it 'records a source link to the pipeline' do
        expect { execute }.to change { Ai::DuoWorkflows::WorkflowPipeline.count }.by(1)

        link = Ai::DuoWorkflows::WorkflowPipeline.order(:id).last
        expect(link).to have_attributes(
          workflow: execute[:workflow],
          pipeline_id: pipeline.id,
          link_type: 'source'
        )
      end

      it 'does not fail workflow creation when linking raises' do
        allow_next_instance_of(::Ai::DuoWorkflows::LinkArtifactService) do |service|
          allow(service).to receive(:execute).and_raise(StandardError, 'boom')
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id))

        expect(execute[:status]).to eq(:success)
      end

      it 'does not fail workflow creation when resolving the source pipeline raises' do
        flow = ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1
        allow(flow).to receive(:resolve_source_pipeline_for).and_raise(StandardError, 'boom')

        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(:workflow_id, :container_id))

        expect { expect(execute[:status]).to eq(:success) }
          .not_to change { Ai::DuoWorkflows::WorkflowPipeline.count }
      end

      context 'when the goal does not reference a pipeline' do
        let(:params) { { environment: "web", workflow_definition: 'fix_pipeline/v1', goal: "no pipeline here" } }

        it 'does not record a pipeline link' do
          expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowPipeline.count }
        end
      end

      context 'when the flow does not resolve a source pipeline' do
        let(:params) { { environment: "web", workflow_definition: "developer/v1", goal: "do something" } }

        it 'does not record a pipeline link' do
          expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowPipeline.count }
        end
      end
    end

    context 'on system note creation' do
      context 'when noteable is an issue' do
        context 'when issue_id is valid' do
          let_it_be(:issue) { create(:issue, project: project) }
          let_it_be(:duo_service_account) { create(:service_account) }
          let(:params) { { environment: "web", issue_id: issue.iid, service_account: duo_service_account } }

          it 'creates a workflow associated with the issue' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

            workflow = execute[:workflow]
            expect(workflow.issue).to eq(issue)
          end

          it 'creates a system note on the issue' do
            expect(SystemNoteService).to receive(:agent_session_started).with(
              issue,
              project,
              be_a(Integer),
              user,
              duo_service_account
            )

            execute
          end
        end

        context 'when workflow has no service account' do
          let_it_be(:issue) { create(:issue, project: project) }
          let(:params) { { environment: "web", issue_id: issue.iid } }

          it 'calls SystemNoteService with nil author but does not create a note' do
            expect(SystemNoteService).to receive(:agent_session_started).with(
              issue,
              project,
              be_a(Integer),
              user,
              nil
            ).and_call_original

            result = execute

            expect(result[:status]).to eq(:success)
            expect(issue.notes).to be_empty
          end
        end

        context 'when issue_id is invalid' do
          let(:params) { { environment: "web", issue_id: 999999 } }

          it 'creates a workflow without issue association' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

            workflow = execute[:workflow]
            expect(workflow.issue).to be_nil
          end

          it 'does not create a system note' do
            expect(SystemNoteService).not_to receive(:agent_session_started)

            execute
          end
        end
      end

      context 'when noteable is resolved from the goal via foundational flow' do
        let_it_be(:merge_request) { create(:merge_request, source_project: project) }
        let_it_be(:pipeline) { create(:ci_pipeline, project: project, merge_request: merge_request) }

        let(:params) do
          {
            environment: "web",
            workflow_definition: 'fix_pipeline/v1',
            goal: "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}"
          }
        end

        it 'creates a workflow associated with the merge request' do
          result = nil
          expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(result[:workflow].merge_request).to eq(merge_request)
        end

        it 'creates a system note on the merge request' do
          expect(SystemNoteService).to receive(:agent_session_started).with(
            merge_request,
            project,
            be_a(Integer),
            user,
            nil
          ).and_call_original

          execute
        end

        context 'when the pipeline has no merge request' do
          let_it_be(:pipeline_without_mr) { create(:ci_pipeline, project: project) }

          let(:params) do
            {
              environment: "web",
              workflow_definition: 'fix_pipeline/v1',
              goal: "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline_without_mr.id}"
            }
          end

          it 'creates a workflow without merge request association' do
            result = nil
            expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
            expect(result[:workflow].merge_request).to be_nil
          end
        end
      end

      context 'when the workplan flow resolves the work item from the goal' do
        let_it_be(:work_item) { create(:work_item, project: project) }

        let(:params) do
          {
            environment: "web",
            workflow_definition: 'workplan/v1',
            goal: "Plan this: #{Gitlab::UrlBuilder.build(work_item)}"
          }
        end

        it 'creates a workflow associated with the work item', :aggregate_failures do
          result = nil
          expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

          workflow = result[:workflow]
          expect(workflow.work_item).to eq(work_item)
          expect(Ai::DuoWorkflows::WorkflowWorkItem.where(workflow: workflow, work_item: work_item)).to exist
        end

        context 'when the goal does not reference a work item' do
          let(:params) do
            { environment: "web", workflow_definition: 'workplan/v1', goal: "Plan something" }
          end

          it 'creates a workflow without a work item association' do
            result = nil
            expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
            expect(result[:workflow].work_item).to be_nil
          end
        end
      end

      context 'when the code review flow resolves the merge request from the goal' do
        let_it_be(:merge_request) { create(:merge_request, source_project: project) }

        let(:params) do
          {
            environment: "web",
            workflow_definition: ::Ai::Catalog::FoundationalFlow.code_review.foundational_flow_reference,
            goal: merge_request.iid
          }
        end

        it 'creates a workflow linked to the merge request' do
          result = nil
          expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(result[:workflow].merge_request).to eq(merge_request)
        end

        context 'when the merge request iid does not resolve' do
          let(:params) do
            {
              environment: "web",
              workflow_definition: ::Ai::Catalog::FoundationalFlow.code_review.foundational_flow_reference,
              goal: non_existing_record_iid
            }
          end

          it 'creates a workflow without merge request association' do
            result = nil
            expect { result = execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
            expect(result[:workflow].merge_request).to be_nil
          end
        end
      end

      context 'when noteable is a merge request' do
        context 'when merge_request_id is valid' do
          let_it_be(:merge_request) { create(:merge_request, source_project: project) }
          let_it_be(:duo_service_account) { create(:service_account) }
          let(:params) do
            { environment: "web", merge_request_id: merge_request.iid, service_account: duo_service_account }
          end

          it 'creates a workflow associated with the merge request' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

            workflow = execute[:workflow]
            expect(workflow.merge_request).to eq(merge_request)
          end

          context 'when the flow does not opt out of the agent session note' do
            let(:params) do
              {
                environment: "web",
                merge_request_id: merge_request.iid,
                service_account: duo_service_account,
                workflow_definition: 'developer/v1'
              }
            end

            it 'posts the generic agent session started system note' do
              expect(SystemNoteService).to receive(:agent_session_started)

              execute
            end
          end

          context 'when the flow opts out of the agent session note' do
            let(:params) do
              {
                environment: "web",
                merge_request_id: merge_request.iid,
                service_account: duo_service_account,
                workflow_definition: ::Ai::Catalog::FoundationalFlow.code_review.foundational_flow_reference
              }
            end

            it 'does not post the generic agent session started system note' do
              expect(SystemNoteService).not_to receive(:agent_session_started)

              execute
            end

            it 'still associates the workflow with the merge request' do
              workflow = execute[:workflow]

              expect(workflow.merge_request).to eq(merge_request)
            end
          end
        end

        context 'when merge_request_id is invalid' do
          let(:params) { { environment: "web", merge_request_id: non_existing_record_id } }

          it 'creates a workflow without merge request association' do
            expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

            workflow = execute[:workflow]
            expect(workflow.merge_request).to be_nil
          end
        end

        context 'when MergeRequestsFinder raises an error' do
          let(:params) { { environment: "web", merge_request_id: 1 } }
          let(:error) { StandardError.new('Database connection failed') }

          before do
            allow_next_instance_of(MergeRequestsFinder) do |finder|
              allow(finder).to receive(:execute).and_raise(error)
            end
          end

          it 'tracks the exception' do
            expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
              error,
              hash_including(
                merge_request_iid: 1,
                project_id: project.id
              )
            )

            execute
          end

          it 'creates workflow without merge request association' do
            workflow = execute[:workflow]

            expect(workflow).to be_persisted
            expect(workflow.merge_request).to be_nil
          end
        end
      end

      context 'when SystemNoteService raises an error' do
        let_it_be(:issue) { create(:issue, project: project) }
        let(:params) { { environment: "web", issue_id: issue.iid } }

        before do
          allow(SystemNoteService).to receive(:agent_session_started).and_raise(StandardError, 'Note creation failed')
        end

        it 'tracks the exception and workflow creation continues successfully' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(StandardError),
            hash_including(
              workflow_id: be_a(Integer),
              noteable_type: 'Issue',
              noteable_id: issue.id
            )
          )

          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute[:status]).to eq(:success)
        end

        it 'does not fail the workflow creation' do
          result = execute

          expect(result[:status]).to eq(:success)
          expect(result[:workflow]).to be_persisted
          expect(result[:workflow].issue).to eq(issue)
        end
      end

      context 'when finder raises an error' do
        context 'when IssuesFinder raises an error for issue_id' do
          let(:params) { { environment: "web", issue_id: 1 } }
          let(:error) { StandardError.new('Database connection failed') }

          before do
            allow_next_instance_of(IssuesFinder) do |finder|
              allow(finder).to receive(:execute).and_raise(error)
            end
          end

          it 'tracks the exception with issue_iid' do
            expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
              error,
              hash_including(
                issue_iid: 1,
                container_id: project.id
              )
            )

            execute
          end

          it 'creates workflow without issue association' do
            workflow = execute[:workflow]

            expect(workflow).to be_persisted
            expect(workflow.issue).to be_nil
          end

          it 'does not create a system note' do
            expect(SystemNoteService).not_to receive(:agent_session_started)

            execute
          end
        end
      end

      context 'when noteable does not have a project' do
        let_it_be(:issue) { create(:issue, project: project) }
        let(:params) { { environment: "web", issue_id: issue.iid } }

        before do
          allow_next_found_instance_of(Issue) do |instance|
            allow(instance).to receive(:project).and_return(nil)
          end
        end

        it 'does not create a system note' do
          expect(SystemNoteService).not_to receive(:agent_session_started)

          execute
        end

        it 'still creates the workflow successfully' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute[:status]).to eq(:success)
        end
      end

      context 'when noteable project is not present' do
        let_it_be(:issue) { create(:issue, project: project) }
        let(:params) { { environment: "web", issue_id: issue.iid } }
        let(:empty_project) { instance_double(Project, present?: false) }

        before do
          allow_next_found_instance_of(Issue) do |instance|
            allow(instance).to receive(:project).and_return(empty_project)
          end
        end

        it 'does not create a system note' do
          expect(SystemNoteService).not_to receive(:agent_session_started)

          execute
        end

        it 'still creates the workflow successfully' do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(execute[:status]).to eq(:success)
        end
      end

      context 'when noteable does not respond to project method' do
        let_it_be(:issue) { create(:issue, project: project) }
        let(:params) { { environment: "web", issue_id: issue.iid } }

        before do
          allow_next_instance_of(IssuesFinder) do |finder|
            allow(finder).to receive(:execute).and_return(Issue.none)
          end
        end

        it 'does not create a system note' do
          expect(SystemNoteService).not_to receive(:agent_session_started)

          execute
        end

        it 'creates workflow without issue association' do
          workflow = execute[:workflow]

          expect(workflow).to be_persisted
          expect(workflow.issue_id).to be_nil
        end
      end

      context 'when container is not a Project' do
        let(:container) { group }
        let(:params) { { environment: "web", issue_id: 1, workflow_definition: 'chat' } }

        before do
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, container).and_return(true)
        end

        it 'does not attempt to find the issue' do
          expect(IssuesFinder).not_to receive(:new)

          execute
        end

        it 'creates workflow without issue association' do
          workflow = execute[:workflow]

          expect(workflow).to be_persisted
          expect(workflow.issue).to be_nil
          expect(workflow.namespace).to eq(group)
        end
      end

      context 'when issue is passed as a pre-resolved AR object (API layer resolution)' do
        let_it_be(:issue) { create(:issue, project: project) }
        let_it_be(:duo_service_account) { create(:service_account) }
        let(:params) { { environment: "web", issue: issue, service_account: duo_service_account } }

        it 'creates a workflow associated with the issue', :aggregate_failures do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

          workflow = Ai::DuoWorkflows::Workflow.last
          expect(workflow.issue).to eq(issue)
          expect(workflow.merge_request).to be_nil
        end

        it 'creates a system note on the issue' do
          expect(SystemNoteService).to receive(:agent_session_started).with(
            issue, project, be_a(Integer), user, duo_service_account
          )

          execute
        end
      end

      context 'when merge_request is passed as a pre-resolved AR object (API layer resolution)' do
        let_it_be(:merge_request) { create(:merge_request, source_project: project) }
        let_it_be(:duo_service_account) { create(:service_account) }
        let(:params) { { environment: "web", merge_request: merge_request, service_account: duo_service_account } }

        it 'creates a workflow associated with the merge request', :aggregate_failures do
          expect { execute }.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

          workflow = Ai::DuoWorkflows::Workflow.last
          expect(workflow.merge_request).to eq(merge_request)
          expect(workflow.issue).to be_nil
        end
      end

      context 'when pre-resolved issue prevents goal-based flow resolution' do
        let_it_be(:issue) { create(:issue, project: project) }
        let_it_be(:merge_request) { create(:merge_request, source_project: project) }
        let_it_be(:pipeline) { create(:ci_pipeline, project: project, merge_request: merge_request) }
        let(:params) do
          {
            environment: "web",
            issue: issue,
            workflow_definition: 'fix_pipeline/v1',
            goal: "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}"
          }
        end

        it 'uses the explicit issue and does not resolve MR from goal', :aggregate_failures do
          result = execute

          expect(result[:status]).to eq(:success)
          workflow = result[:workflow]
          expect(workflow.issue).to eq(issue)
          expect(workflow.merge_request).to be_nil
        end
      end
    end

    describe 'agent privileges resolution' do
      context 'when the server resolves privileges on a local surface' do
        let(:params) { { environment: "ide" } }

        context 'when the duo_workflow_local_tool_governance flag is disabled' do
          before do
            stub_feature_flags(duo_workflow_local_tool_governance: false)
          end

          it 'resolves nothing and keeps DEFAULT_PRIVILEGES', :aggregate_failures do
            # degraded_surface used to pass the raw 'ide' through, so local_access rules
            # were written to the row while local governance was off. See
            # gitlab-org/gitlab#622602.
            expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

            workflow = execute[:workflow]

            expect(workflow.agent_privileges).to match_array(
              ::Ai::DuoWorkflows::Workflow::AgentPrivileges::DEFAULT_PRIVILEGES
            )
          end
        end

        context 'when the duo_workflow_local_tool_governance flag is enabled' do
          before do
            stub_feature_flags(duo_workflow_local_tool_governance: true)
          end

          it 'resolves against the local surface' do
            expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
              hash_including(surface: :ide)
            ).and_call_original

            execute
          end
        end
      end

      context 'when the client supplies agent_privileges' do
        let(:client_privileges) { [1, 2, 4] }
        let(:params) { { environment: "ide", agent_privileges: client_privileges } }

        context 'when the caller omits environment entirely' do
          # The clamp now runs for a caller-supplied set on every surface, so the
          # environment the caller sends no longer decides whether it applies.
          let(:params) { { agent_privileges: client_privileges } }

          before do
            # Production config. Re-adding the deleted local-flag check would
            # leave this green while the clamp stopped running.
            stub_feature_flags(duo_workflow_local_tool_governance: false)

            allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.success(payload: {
                  agent_privileges: [1, 2, 7],
                  pre_approved_agent_privileges: [2, 7],
                  pre_approved_tools: ['list_issues']
                })
              )
            end
          end

          it 'still clamps, so the caller cannot opt out by leaving it unset',
            :aggregate_failures do
            workflow = execute[:workflow]

            expect(workflow.agent_privileges).to match_array([1, 2])
            expect(workflow.pre_approved_agent_privileges).to match_array([2])
          end
        end

        context 'on a local surface' do
          before do
            allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.success(payload: {
                  agent_privileges: [1, 2, 7],
                  pre_approved_agent_privileges: [1, 7],
                  pre_approved_tools: ['read_file']
                })
              )
            end
          end

          it 'clamps the client privileges to the governance resolution', :aggregate_failures do
            workflow = execute[:workflow]

            expect(workflow.agent_privileges).to match_array([1, 2])
          end

          it 'resolves governance rules for the local surface' do
            expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
              hash_including(surface: :ide)
            ).and_call_original

            execute
          end

          %w[chat chat_partial].each do |environment|
            context "when the environment is #{environment}" do
              let(:params) { { environment: environment, agent_privileges: client_privileges } }

              it 'resolves governance rules for the local surface' do
                expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
                  hash_including(surface: environment.to_sym)
                ).and_call_original

                execute
              end
            end
          end

          context 'when pre_approved_agent_privileges are also supplied' do
            let(:params) do
              { environment: "ide", agent_privileges: client_privileges, pre_approved_agent_privileges: [1, 2] }
            end

            it 'clamps them to the resolved pre-approved privileges' do
              expect(execute[:workflow].pre_approved_agent_privileges).to match_array([1])
            end
          end

          context 'when pre_approved_agent_privileges are omitted' do
            it 'adopts the resolved pre-approved privileges instead of the column default' do
              # Resolved [1, 7] constrained to the clamped grants [1, 2].
              expect(execute[:workflow].pre_approved_agent_privileges).to match_array([1])
            end
          end

          context 'when the environment is not a recognized local surface' do
            let(:params) { { environment: "external", agent_privileges: client_privileges } }

            it 'clamps against the web surface rules' do
              expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
                hash_including(surface: :web)
              ).and_call_original

              execute
            end
          end

          context 'when the duo_workflow_local_tool_governance flag is disabled' do
            before do
              stub_feature_flags(duo_workflow_local_tool_governance: false)
            end

            it 'keeps the client-supplied privileges without resolving governance', :aggregate_failures do
              expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

              expect(execute[:workflow].agent_privileges).to match_array(client_privileges)
            end
          end

          context 'when the surface resolves as ungoverned' do
            # Pins the guard independently of how the surface became ungoverned.
            before do
              allow(::Ai::ToolRules::GovernanceSurface).to receive(:for)
                .and_return(::Ai::ToolRules::GovernanceSurface::UNGOVERNED)
            end

            it 'does not clamp, and keeps the client-supplied privileges', :aggregate_failures do
              expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

              expect(execute[:workflow].agent_privileges).to match_array(client_privileges)
            end
          end

          context 'when governance resolution fails' do
            before do
              allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
                allow(instance).to receive(:execute).and_return(
                  ServiceResponse.error(message: 'something went wrong')
                )
              end
            end

            it 'fails closed with no privileges', :aggregate_failures do
              workflow = execute[:workflow]

              expect(workflow.agent_privileges).to eq([])
              expect(workflow.pre_approved_agent_privileges).to eq([])
            end
          end
        end

        context 'when the privileges were set by the application, not the caller' do
          let(:privileges_from_client) { false }
          let(:params) { { environment: "web", agent_privileges: client_privileges } }

          # Catalog, agent_workflows and foundational flows set privileges themselves,
          # so clamping would narrow flows the caller never influenced.
          it 'persists them untouched and does not resolve governance', :aggregate_failures do
            expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

            expect(execute[:workflow].agent_privileges).to match_array(client_privileges)
          end
        end

        context 'on a web surface' do
          let(:params) { { environment: "web", agent_privileges: client_privileges } }

          before do
            stub_feature_flags(duo_workflow_local_tool_governance: false)
          end

          it 'clamps the client privileges to the governance resolution' do
            allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.success(payload: {
                  agent_privileges: [1, 2, 7],
                  pre_approved_agent_privileges: [1, 7],
                  pre_approved_tools: ['read_file']
                })
              )
            end

            expect(execute[:workflow].agent_privileges).to match_array([1, 2])
          end
        end

        context 'when a privilege is not a known value' do
          let(:params) { { environment: "ide", agent_privileges: [1, 999] } }

          # Clamping would intersect the unknown value away and save successfully, hiding
          # the model's error. Skipping the clamp lets that validation reject the request.
          it 'skips the clamp so model validation can report it', :aggregate_failures do
            expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

            expect(execute[:status]).to eq(:error)
            expect(execute[:message]).to include('contains an invalid value 999')
          end
        end
      end

      # Not a supported shape, but the conditional that skips the clamp for it is easy to
      # refactor away by accident, which would silently reopen #618863 on this path.
      context 'when the client supplies only pre_approved_agent_privileges' do
        let(:params) { { environment: "ide", pre_approved_agent_privileges: [1, 2] } }

        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(payload: {
                agent_privileges: [1, 2, 7],
                pre_approved_agent_privileges: [2, 7],
                pre_approved_tools: ['read_file']
              })
            )
          end
        end

        it 'falls through to server resolution, which overwrites rather than intersects' do
          expect(execute[:workflow].pre_approved_agent_privileges).to match_array([2, 7])
        end
      end

      context 'when governance resolution succeeds' do
        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(payload: {
                agent_privileges: [1, 2],
                pre_approved_agent_privileges: [1],
                pre_approved_tools: ['read_file']
              })
            )
          end
        end

        it 'uses privileges from resolution service' do
          workflow = execute[:workflow]

          expect(workflow.agent_privileges).to match_array([1, 2])
          expect(workflow.pre_approved_agent_privileges).to match_array([1])
        end

        it 'passes the project to ResolutionService when container is a project' do
          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(project: container)
          ).and_call_original

          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(payload: {
                agent_privileges: [1, 2],
                pre_approved_agent_privileges: [1],
                pre_approved_tools: ['read_file']
              })
            )
          end

          execute
        end
      end

      context 'when environment is ambient (background)' do
        let(:params) { { environment: 'ambient', workflow_definition: 'developer/v1' } }

        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(payload: {
                agent_privileges: [1, 2],
                pre_approved_agent_privileges: [1],
                pre_approved_tools: []
              })
            )
          end
        end

        it 'resolves the :background surface when the background-governance flag is enabled' do
          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(surface: :background)
          ).and_call_original

          execute
        end

        it 'passes the ambient environment as the surface when the background-governance flag is disabled' do
          stub_feature_flags(duo_workflow_background_tool_governance: false)

          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(surface: 'ambient')
          ).and_call_original

          execute
        end
      end

      context 'when resolution service fails on every attempt' do
        it 'retries the resolution service up to MAX_GOVERNANCE_RETRIES times' do
          expect_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            expect(instance).to receive(:execute)
              .exactly(described_class::MAX_GOVERNANCE_RETRIES).times
              .and_return(ServiceResponse.error(message: 'something went wrong'))
          end

          execute
        end
      end

      context 'when resolution service fails' do
        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: 'something went wrong')
            )
          end
        end

        it 'fails closed with no tools after retries are exhausted', :aggregate_failures do
          workflow = execute[:workflow]

          expect(workflow.agent_privileges).to eq([])
          expect(workflow.pre_approved_agent_privileges).to eq([])
        end

        it 'logs an error after retries are exhausted' do
          expect(Gitlab::AppLogger).to receive(:error).with(
            hash_including(
              message: "Governance resolution failed after #{described_class::MAX_GOVERNANCE_RETRIES} " \
                "retries, failing closed with no tools"
            )
          )

          execute
        end

        it 'logs a warning on each failed attempt' do
          expect(Gitlab::AppLogger).to receive(:warn).exactly(described_class::MAX_GOVERNANCE_RETRIES).times

          execute
        end
      end

      context 'when resolution service reports an ungoverned surface' do
        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Surface is ungoverned', reason: :ungoverned_surface)
            )
          end
        end

        it 'logs without claiming retries were exhausted' do
          expect(Gitlab::AppLogger).to receive(:error).with(
            hash_including(
              message: 'Governance resolution skipped for an ungoverned surface, failing closed with no tools'
            )
          )

          execute
        end
      end

      context 'when resolution service succeeds after retries' do
        it 'uses privileges from the successful attempt', :aggregate_failures do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: 'transient error'),
              ServiceResponse.error(message: 'transient error'),
              ServiceResponse.success(payload: {
                agent_privileges: [1, 2],
                pre_approved_agent_privileges: [1],
                pre_approved_tools: ['read_file']
              })
            )
          end

          workflow = execute[:workflow]

          expect(workflow.agent_privileges).to match_array([1, 2])
          expect(workflow.pre_approved_agent_privileges).to match_array([1])
        end
      end
    end
  end
end
