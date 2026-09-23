# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ExecuteRunService, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:service_account) { create(:user, :service_account) }

  let(:workflow_definition) { 'developer/v1' }
  let(:workflow) do
    create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
      workflow_definition: workflow_definition)
  end

  let(:event) { { type: :input, text: 'Fix the pipeline' } }
  let(:runtime) { nil }
  let(:start_result) { ServiceResponse.success(payload: { workload_id: 123 }) }

  subject(:result) { described_class.new(workflow, event: event, runtime: runtime).execute }

  before do
    allow(::Ai::ServiceAccountMemberAddService).to receive(:new).and_return(
      instance_double(::Ai::ServiceAccountMemberAddService, execute: ServiceResponse.success)
    )
    allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(
      instance_double(
        ::Ai::DuoWorkflows::WorkflowContextGenerationService,
        generate_oauth_token_with_composite_identity_support: ServiceResponse.success(payload: {
          oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
        }),
        generate_workflow_token: ServiceResponse.success(payload: { token: 'workflow-token' }),
        duo_agent_platform_feature_setting: nil
      )
    )
    allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})
    allow(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).and_return(
      instance_double(::Ai::DuoWorkflows::StartWorkflowService, execute: start_result)
    )
  end

  describe '.runtime_for' do
    subject(:resolved) { described_class.runtime_for(definition, override: override) }

    let(:definition) { 'slack_assistant/v1' }
    let(:override) { nil }

    context 'with a valid override' do
      let(:override) { 'ci' }

      it 'returns the override' do
        expect(resolved).to eq(:ci)
      end
    end

    context 'with an unknown override' do
      let(:override) { :bogus }

      it 'returns nil' do
        expect(resolved).to be_nil
      end
    end

    context 'without an override' do
      it 'infers Workhorse from a none coding environment' do
        expect(resolved).to eq(:workhorse)
      end

      context 'with a full coding environment' do
        let(:definition) { 'developer/v1' }

        it 'infers CI' do
          expect(resolved).to eq(:ci)
        end
      end
    end
  end

  describe '#execute' do
    context 'with a first-turn event for a CI flow' do
      it 'infers CI and starts the workflow', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload).to include(workflow: workflow, workload_id: 123)
        expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new)
      end

      it 'provisions the CI service account' do
        result

        expect(::Ai::ServiceAccountMemberAddService).to have_received(:new).with(project, service_account)
      end

      it 'runs against the default branch when the session has no merge request' do
        result

        expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(source_branch: project.default_branch_or_main)
        )
      end

      context 'when the session is linked to a merge request' do
        let(:merge_request) { create(:merge_request, source_project: project, source_branch: 'feature-branch') }
        let(:workflow) do
          create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
            workflow_definition: workflow_definition, merge_request: merge_request)
        end

        it 'runs against the merge request source branch' do
          result

          expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
            workflow: workflow,
            params: hash_including(source_branch: 'feature-branch')
          )
        end
      end
    end

    context 'with a first-turn event for a Workhorse flow' do
      let(:workflow_definition) { 'slack_assistant/v1' }

      it 'infers Workhorse and enqueues the turn worker' do
        expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async).with(workflow.id, nil, nil)
        expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

        expect(result).to be_success
      end
    end

    context 'with an approval event for a CI flow' do
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :approval, approved: true, message: nil } }

      it 'uses the derived CI runtime and resumes with the approval', :aggregate_failures do
        resume_service = instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: start_result)
        allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resume_service)

        expect(result).to be_success
        expect(::Ai::DuoWorkflows::ResumeWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(human_approval: true, human_message: nil)
        )
      end

      it 'accepts an approval event without a message' do
        resume_service = instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: start_result)
        allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resume_service)

        response = described_class.new(workflow, event: { type: :approval, approved: true }).execute

        expect(response).to be_success
      end
    end

    context 'with an approval event for a Workhorse flow' do
      let(:workflow_definition) { 'slack_assistant/v1' }
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :approval, approved: false, message: 'Do not proceed' } }

      it 'uses the derived Workhorse runtime and forwards the rejection' do
        expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async)
          .with(workflow.id, { 'rejection' => { 'message' => 'Do not proceed' } }, nil)

        expect(result).to be_success
      end

      it 'uses the previous CI workload runtime when present', :aggregate_failures do
        resume_service = instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: start_result)
        allow(workflow).to receive(:last_runtime).and_return(:ci)
        allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resume_service)

        expect(::Ai::Messaging::ServerSideTurnWorker).not_to receive(:perform_async)
        expect(result).to be_success
      end

      context 'with a plan approval event' do
        let(:workflow) do
          create(:duo_workflows_workflow, :plan_approval_required, user: user, project: project,
            service_account: service_account, workflow_definition: workflow_definition)
        end

        let(:event) { { type: :approval, approved: true } }

        it 'resumes through the same approval payload' do
          expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async)
            .with(workflow.id, { 'approval' => {} }, nil)

          expect(result).to be_success
        end
      end

      context 'with an input event replying to input_required' do
        let(:workflow) do
          create(:duo_workflows_workflow, :input_required, user: user, project: project,
            service_account: service_account, workflow_definition: workflow_definition)
        end

        let(:event) { { type: :input, text: 'Please continue' } }

        it 'forwards the reply text to the worker' do
          expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async)
            .with(workflow.id, nil, 'Please continue')

          expect(result).to be_success
        end
      end
    end

    context 'with an input event replying to input_required on CI' do
      let(:workflow) do
        create(:duo_workflows_workflow, :input_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :input, text: 'Please continue' } }

      it 'forwards the reply text as the fresh goal', :aggregate_failures do
        resume_service = instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: start_result)
        allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resume_service)

        expect(result).to be_success
        expect(::Ai::DuoWorkflows::ResumeWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(goal: 'Please continue')
        )
      end
    end

    context 'with an approval event carrying a text key' do
      let(:workflow_definition) { 'slack_assistant/v1' }
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :approval, approved: true, text: 'ignore me' } }

      it 'is invalid: approval carries no text channel', :aggregate_failures do
        expect(::Ai::Messaging::ServerSideTurnWorker).not_to receive(:perform_async)

        expect(result).to be_error
        expect(result.reason).to eq(:invalid_event)
      end
    end

    context 'with an unsupported runtime override' do
      let(:workflow_definition) { 'developer/v1' }
      let(:runtime) { :workhorse }

      it 'fails before provisioning or starting a run', :aggregate_failures do
        expect(::Ai::ServiceAccountMemberAddService).not_to receive(:new)

        expect(result).to be_error
        expect(result.reason).to eq(:unsupported_environment)
      end
    end

    context 'with an explicit continuation runtime that differs from the derived runtime' do
      let(:workflow_definition) { 'slack_assistant/v1' }
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :approval, approved: true, message: nil } }
      let(:runtime) { :ci }

      it 'returns :runtime_mismatch', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:runtime_mismatch)
      end
    end

    context 'with an unknown runtime override' do
      let(:runtime) { :bogus }

      it 'returns :runtime_unknown', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:runtime_unknown)
      end
    end

    context 'with an invalid event' do
      let(:event) { { type: :input, text: 'Fix the pipeline', extra: true } }

      it 'returns :invalid_event', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:invalid_event)
      end
    end

    context 'with an unresolvable flow runtime' do
      before do
        allow(::Ai::Catalog::CodingEnvironment).to receive(:resolve).and_return(nil)
      end

      it 'returns :runtime_unknown', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:runtime_unknown)
      end
    end

    context 'with a runtime override matching the derived last runtime' do
      let(:workflow_definition) { 'slack_assistant/v1' }
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: user, project: project,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:event) { { type: :approval, approved: true, message: nil } }
      let(:runtime) { :workhorse }

      it 'continues on that runtime' do
        expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async)

        expect(result).to be_success
      end
    end

    context 'when the run service itself fails' do
      let(:start_result) { ServiceResponse.error(message: 'nope', reason: :execute_workflow_failed) }

      it 'returns the error' do
        expect(result).to be_error
        expect(result.reason).to eq(:execute_workflow_failed)
      end
    end

    context 'when the CI workflow is not project-level' do
      let(:workflow) do
        create(:duo_workflows_workflow, :created, user: user, namespace: project.namespace,
          service_account: service_account, workflow_definition: workflow_definition)
      end

      let(:runtime) { :ci }

      it 'returns :invalid_ci_session', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:invalid_ci_session)
      end
    end

    context 'when the CI workflow has no service account' do
      let(:workflow) do
        create(:duo_workflows_workflow, :created, user: user, project: project,
          service_account: nil, workflow_definition: workflow_definition)
      end

      let(:runtime) { :ci }

      it 'returns :invalid_ci_session', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:invalid_ci_session)
      end
    end

    context 'when service account provisioning fails' do
      before do
        allow(::Ai::ServiceAccountMemberAddService).to receive(:new).and_return(
          instance_double(::Ai::ServiceAccountMemberAddService,
            execute: ServiceResponse.error(message: 'member add failed'))
        )
      end

      it 'returns :service_account_error without starting the run', :aggregate_failures do
        expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

        expect(result).to be_error
        expect(result.reason).to eq(:service_account_error)
      end
    end

    context 'when the service account enforces composite identity' do
      before do
        allow(service_account).to receive(:composite_identity_enforced?).and_return(true)
        ai_settings = instance_double(::Ai::Setting, duo_workflow_oauth_application: oauth_application)
        allow(::Ai::Setting).to receive(:for_organization_read_only).and_return(ai_settings)
        allow(::Gitlab::Auth::Identity).to receive(:link_from_web_request)
      end

      let(:oauth_application) { instance_double(Doorkeeper::Application) }

      it 'links the composite identity before provisioning', :aggregate_failures do
        expect(result).to be_success
        expect(::Gitlab::Auth::Identity).to have_received(:link_from_web_request).with(
          service_account: service_account, scoped_user: user
        )
      end

      context 'without an OAuth application configured' do
        let(:oauth_application) { nil }

        it 'skips the identity link and still runs', :aggregate_failures do
          expect(result).to be_success
          expect(::Gitlab::Auth::Identity).not_to have_received(:link_from_web_request)
        end
      end

      context 'when the workflow has no user' do
        before do
          # user_id is NOT NULL at the database level, so stub the association
          allow(workflow).to receive(:user).and_return(nil)
        end

        it 'skips the identity link and still runs', :aggregate_failures do
          expect(result).to be_success
          expect(::Gitlab::Auth::Identity).not_to have_received(:link_from_web_request)
        end
      end
    end

    context 'when the oauth token cannot be generated' do
      before do
        allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(
          instance_double(
            ::Ai::DuoWorkflows::WorkflowContextGenerationService,
            generate_oauth_token_with_composite_identity_support: ServiceResponse.error(message: 'no token')
          )
        )
      end

      it 'returns the error without starting the run', :aggregate_failures do
        expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

        expect(result).to be_error
      end
    end

    context 'when the workflow token cannot be generated' do
      before do
        allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(
          instance_double(
            ::Ai::DuoWorkflows::WorkflowContextGenerationService,
            generate_oauth_token_with_composite_identity_support: ServiceResponse.success(payload: {
              oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
            }),
            generate_workflow_token: ServiceResponse.error(message: 'no token')
          )
        )
      end

      it 'returns the error without starting the run', :aggregate_failures do
        expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

        expect(result).to be_error
      end
    end
  end
end
