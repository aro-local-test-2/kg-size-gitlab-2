# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ResumeWorkplanService, feature_category: :duo_agent_platform do
  include ExclusiveLeaseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:requester) { create(:user, developer_of: project) }
  let_it_be(:other_developer) { create(:user, developer_of: project) }
  let_it_be(:oauth_token) { create(:oauth_access_token, user: requester, scopes: [:api]) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
      service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
  end

  let_it_be(:question_note) do
    create(:discussion_note_on_work_item, :resolved, noteable: work_item, project: project, author: requester,
      note: 'Which auth provider should this use?')
  end

  let_it_be(:reply_note) do
    create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
      note: 'Use Okta')
  end

  let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

  let(:current_user) { requester }
  let(:workflow_service_token_result) { ServiceResponse.success(payload: { token: 'service-token' }) }
  let(:workflow_oauth_token_result) { ServiceResponse.success(payload: { oauth_access_token: oauth_token }) }
  let(:resumed) { instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: ServiceResponse.success) }
  let(:workload_pipeline_status) { :success }

  subject(:result) { described_class.new(work_item: work_item, current_user: current_user).execute }

  before do
    allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
      allow(service).to receive_messages(
        generate_workflow_token: workflow_service_token_result,
        generate_oauth_token_with_composite_identity_support: workflow_oauth_token_result,
        duo_agent_platform_feature_setting: nil
      )
    end

    allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})

    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow(current_user).to receive(:allowed_to_use?).and_return(true)
    project.project_setting.update!(duo_features_enabled: true, duo_remote_flows_enabled: true)

    # `resumable` also requires the previous workload's pipeline to have
    # finished, so give whichever workflow is under test one. Built per example
    # rather than in a `let_it_be`, since several contexts define their own.
    pipeline = create(:ci_pipeline, workload_pipeline_status, project: project)
    workload = create(:ci_workload, pipeline: pipeline, project: project)
    workflow.workflows_workloads.create!(workload: workload, project: project)
  end

  it 'resumes the workflow with the replies as goal, and no approval decision', :aggregate_failures do
    expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new) do |args|
      expect(args[:workflow]).to eq(workflow)
      expect(args[:params]).to include(
        goal: 'Q: Which auth provider should this use? A: Use Okta',
        workflow_id: workflow.id,
        service_account: service_account,
        workflow_oauth_token: oauth_token.plaintext_token,
        workflow_service_token: 'service-token'
      )
      expect(args[:params]).not_to have_key(:human_approval)
      expect(args[:params]).not_to have_key(:human_message)

      resumed
    end

    expect(result).to be_success
    expect(result.payload[:workflow]).to eq(workflow)
  end

  context 'when the work item has no workplan workflow' do
    let_it_be(:work_item) { create(:work_item, project: project) }

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end
  end

  context 'when the latest workplan workflow is not resumable' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :running, project: project, user: requester, issue_id: work_item.id,
        workflow_definition: 'workplan/v1')
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:not_resumable)
    end
  end

  context 'when the workload pipeline for the previous run has not finished' do
    let(:workload_pipeline_status) { :running }

    it 'refuses rather than starting a second pipeline for the session', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:not_resumable)
    end
  end

  %i[plan_approval_required tool_call_approval_required].each do |status|
    context "when the latest workplan workflow is waiting in #{status}" do
      let_it_be(:work_item) { create(:work_item, project: project) }
      let_it_be(:workflow) do
        create(:duo_workflows_workflow, status, project: project, user: requester, issue_id: work_item.id,
          workflow_definition: 'workplan/v1')
      end

      it 'refuses rather than resuming without a decision', :aggregate_failures do
        expect(workflow.resumable?).to be(true)
        expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

        expect(result).to be_error
        expect(result.reason).to eq(:not_resumable)
      end
    end
  end

  context 'when the project does not allow running Duo flows in CI' do
    before do
      project.project_setting.update!(duo_remote_flows_enabled: false)
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
      expect(result.message).to eq(described_class::EXECUTE_DENIED_ERROR)
    end
  end

  # Managing the work item is the boundary, not having started the flow, so a
  # teammate can carry on a conversation someone else began.
  context 'when the user manages the work item but did not start the flow' do
    let(:current_user) { other_developer }

    it 'resumes' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(duo_workplan_async_flow: false)
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:feature_disabled)
    end
  end

  context 'when the feature flag is enabled for the root group only' do
    before do
      stub_feature_flags(duo_workplan_async_flow: group)
    end

    it 'resumes' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the feature flag is enabled for the project only' do
    before do
      stub_feature_flags(duo_workplan_async_flow: project)
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:feature_disabled)
    end
  end

  context 'when the work item does not belong to a project' do
    let_it_be(:work_item) { create(:work_item, :group_level, namespace: group) }

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:project_required)
    end
  end

  context 'when another resume is already in progress' do
    before do
      stub_exclusive_lease_taken("duo_workflows_resume_workplan:#{workflow.id}",
        timeout: described_class::LEASE_TTL.to_i)
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:resume_in_progress)
    end
  end

  context 'when the workflow stops awaiting input before the lease is obtained' do
    before do
      # Simulates a concurrent resume between the pre-lease check and the lease;
      # status 3 is `:finished` (see the workflow factory trait). The re-check
      # after the lease reads the reloaded record, so it sees the new status.
      allow(Gitlab::ExclusiveLease).to receive(:new).and_wrap_original do |method, *args, **kwargs|
        workflow.update_column(:status, 3)
        method.call(*args, **kwargs)
      end
    end

    it 'returns an error without resuming', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:not_resumable)
    end
  end

  context 'when the workflow definition resolves to a foundational flow' do
    let(:resolved_params) { { flow_config_id: 'workplan', flow_config_schema_version: 'v1', flow_version: 'v1' } }

    before do
      allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
        .with('workplan/v1', project, user: requester)
        .and_return(resolved_params)
    end

    it 'binds the service token to the same flow ID it passes to the resume', :aggregate_failures do
      expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
        expect(service).to receive(:generate_workflow_token).with(flow_config_id: 'workplan')
          .and_return(workflow_service_token_result)
        allow(service).to receive_messages(
          generate_oauth_token_with_composite_identity_support: workflow_oauth_token_result,
          duo_agent_platform_feature_setting: nil
        )
      end

      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new) do |args|
        expect(args[:params]).to include(resolved_params)

        resumed
      end

      expect(result).to be_success
    end
  end

  # Not reachable for `workplan/v1` today - the flow is always registered - and
  # minting unbound here is the fail-closed gap tracked in
  # https://gitlab.com/gitlab-org/gitlab/-/work_items/628405.
  context 'when the resolver returns no flow params' do
    it 'mints an unbound service token' do
      expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
        expect(service).to receive(:generate_workflow_token).with(flow_config_id: nil)
          .and_return(workflow_service_token_result)
        allow(service).to receive_messages(
          generate_oauth_token_with_composite_identity_support: workflow_oauth_token_result,
          duo_agent_platform_feature_setting: nil
        )
      end
      allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the workflow service token cannot be generated' do
    let(:workflow_service_token_result) { ServiceResponse.error(message: 'Service token generation failed') }

    it 'surfaces the error instead of resuming with blank credentials', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.message).to eq('Service token generation failed')
    end
  end

  context 'when the OAuth token cannot be generated' do
    let(:workflow_oauth_token_result) { ServiceResponse.error(message: 'OAuth token generation failed') }

    it 'surfaces the error instead of resuming with blank credentials', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.message).to eq('OAuth token generation failed')
    end
  end

  context 'when a question was answered but its discussion is still unresolved' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:reply_note) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: 'Use Okta')
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'resumes anyway, since the user asked for it' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: 'Q: Which auth provider? A: Use Okta'))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when no question has been answered' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'resumes with the no-answers message rather than an empty goal' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: described_class::NO_REPLIES_MESSAGE))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the question or replies are multi-line markdown' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, :resolved, noteable: work_item, project: project, author: requester,
        note: "Which auth provider?\n\n<!--duo:options [\"Okta\"] duo:recommended 1-->")
    end

    let_it_be(:reply_note) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: "Use Okta.\n\n- with SSO enforced")
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'flattens the message to a single line, leaving the markdown intact' do
      expected_goal = 'Q: Which auth provider? <!--duo:options ["Okta"] duo:recommended 1--> ' \
        'A: Use Okta. - with SSO enforced'

      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: expected_goal))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the question or replies contain shell metacharacters' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, :resolved, noteable: work_item, project: project, author: requester,
        note: %q(What's the trigger for a pause (e.g. "On Hold")?))
    end

    let_it_be(:reply_note) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: "It's status-based; see rules & docs.")
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    # The goal travels as a CI variable set with `expand: false` and the sandbox
    # wrapper passes it by reference, so nothing here reaches a shell as code.
    it 'passes them through untouched' do
      expected_goal = %q(Q: What's the trigger for a pause (e.g. "On Hold")? ) +
        %q(A: It's status-based; see rules & docs.)

      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: expected_goal))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  # Anyone can post a reply, but a Guest's should not reach the flow - it
  # runs under the owner's push access, so only replies from users above
  # Guest count toward the goal.
  context 'when a reply comes from a Guest alongside a trusted reply' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:guest) { create(:user, guest_of: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:guest_reply) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: guest,
        note: 'Okta, we already pay for it')
    end

    let_it_be(:developer_reply) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: other_developer,
        note: 'Use Okta')
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'excludes the Guest reply, keeping the trusted one' do
      expected_goal = 'Q: Which auth provider? A: Use Okta'

      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: expected_goal))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the only reply comes from a Guest' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:guest) { create(:user, guest_of: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:guest_reply) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: guest,
        note: 'Okta, we already pay for it')
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'falls back to the no-replies message' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: described_class::NO_REPLIES_MESSAGE))
        .and_return(resumed)

      expect(result).to be_success
    end
  end

  context 'when the flow posted more than one note' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:flow_follow_up) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: 'Still waiting on an answer here')
    end

    let_it_be(:reply_note) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: 'Use Okta')
    end

    let_it_be(:trigger_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Hey @duo please plan this')
    end

    let_it_be(:trigger_reply) do
      create(:note, in_reply_to: trigger_note, noteable: work_item, project: project, author: requester,
        note: 'Thanks')
    end

    let_it_be(:question_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }
    let_it_be(:follow_up_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: flow_follow_up) }
    let_it_be(:trigger_link) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: trigger_note, link_type: :triggered)
    end

    it 'asks once per discussion and never feeds the flow its own notes back', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new) do |args|
        goal = args[:params][:goal]

        expect(goal).to eq('Q: Which auth provider? A: Use Okta')
        expect(goal).not_to include('Still waiting on an answer here')
        expect(goal).not_to include('Hey @duo please plan this')

        resumed
      end

      expect(result).to be_success
    end
  end

  # A failed or stopped run leaves its questions open on the work item, and
  # the next run does not ask them again - so their answers have to travel
  # with the resume of whichever run is current.
  context 'when an earlier run was stopped with its question still open' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:stopped_workflow) do
      create(:duo_workflows_workflow, :stopped, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:earlier_question) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    let_it_be(:earlier_reply) do
      create(:note, in_reply_to: earlier_question, noteable: work_item, project: project, author: requester,
        note: 'Use Okta')
    end

    let_it_be(:current_question) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which region?')
    end

    let_it_be(:earlier_link) do
      create(:duo_workflows_workflow_note, workflow: stopped_workflow, note: earlier_question)
    end

    let_it_be(:current_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: current_question) }

    it 'forwards the answer to the earlier run instead of the no-replies message' do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new)
        .with(workflow: workflow, params: hash_including(goal: 'Q: Which auth provider? A: Use Okta'))
        .and_return(resumed)

      expect(result).to be_success
    end

    it 'keeps the questions in the order asked and never feeds the new run its own follow-up back',
      :aggregate_failures do
      create(:note, in_reply_to: current_question, noteable: work_item, project: project, author: requester,
        note: 'EU')
      follow_up = create(:note, in_reply_to: earlier_question, noteable: work_item, project: project,
        author: requester, note: 'Thanks, noted.')
      create(:duo_workflows_workflow_note, workflow: workflow, note: follow_up)

      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new) do |args|
        goal = args[:params][:goal]

        expect(goal).to eq('Q: Which auth provider? A: Use Okta Q: Which region? A: EU')
        expect(goal).not_to include('Thanks, noted.')

        resumed
      end

      expect(result).to be_success
    end
  end

  context 'when the replies are long enough to overflow the goal env var' do
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :input_required, project: project, user: requester, issue_id: work_item.id,
        service_account: service_account, workflow_definition: 'workplan/v1', environment: :ambient)
    end

    let_it_be(:question_note) do
      create(:discussion_note_on_work_item, noteable: work_item, project: project, author: requester,
        note: 'Which auth provider?')
    end

    # Multibyte, so the byte cap binds before the character cap.
    let_it_be(:reply_note) do
      create(:note, in_reply_to: question_note, noteable: work_item, project: project, author: requester,
        note: 'é' * (::Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH + 1_000))
    end

    let_it_be(:workflow_note_link) { create(:duo_workflows_workflow_note, workflow: workflow, note: question_note) }

    it 'caps the goal by both characters and bytes', :aggregate_failures do
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new) do |args|
        goal = args[:params][:goal]

        expect(goal.length).to be <= ::Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH
        expect(goal.bytesize).to be <= ::Ai::DuoWorkflows::Workflow::GOAL_MAX_BYTESIZE
        expect(goal).to start_with('Q: Which auth provider? A: ')

        resumed
      end

      expect(result).to be_success
    end
  end

  context 'when building the flow metadata' do
    it 'keeps the flow bound to the user who started it' do
      expect(::Gitlab::DuoWorkflow::Client).to receive(:metadata)
        .with(requester, namespace: project.root_ancestor, project: project)
        .and_call_original

      allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(resumed)

      expect(result).to be_success
    end
  end
end
