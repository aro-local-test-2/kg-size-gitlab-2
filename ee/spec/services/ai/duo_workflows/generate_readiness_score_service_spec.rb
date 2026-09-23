# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::GenerateReadinessScoreService, feature_category: :duo_agent_platform do
  include ExclusiveLeaseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :small_repo, group: group) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  subject(:result) { described_class.new(work_item: work_item, current_user: current_user).execute }

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(workplan_score: false)
    end

    it 'returns a feature_disabled error', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:feature_disabled)
    end
  end

  context 'when the work item has no project' do
    let_it_be(:work_item) { create(:work_item, :epic, namespace: group) }

    it 'returns a project_required error', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:project_required)
    end
  end

  context 'when the readiness score flow is unavailable' do
    before do
      allow(::Ai::Catalog::FoundationalFlow).to receive(:[]).with('readiness_score/v1').and_return(nil)
    end

    it 'returns a flow_unavailable error', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:flow_unavailable)
    end
  end

  context 'when a readiness score workflow is already running for the work item' do
    let_it_be(:running_workflow) do
      create(:duo_workflows_workflow, :running, work_item: work_item, project: project,
        workflow_definition: 'readiness_score/v1')
    end

    it 'returns a workflow_already_running error and does not start a new flow', :aggregate_failures do
      expect(::Ai::DuoWorkflows::CreateAndStartWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:workflow_already_running)
    end
  end

  context 'when another request is already scoring readiness for the work item' do
    before do
      stub_exclusive_lease_taken("duo_workflows_generate_readiness_score:#{work_item.id}", timeout: 2.minutes.to_i)
    end

    it 'returns a workflow_already_running error and does not start a new flow', :aggregate_failures do
      expect(::Ai::DuoWorkflows::CreateAndStartWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:workflow_already_running)
    end
  end

  context 'when the project has no default branch (e.g. an empty repository)' do
    before do
      allow(project).to receive(:default_branch).and_return(nil)
    end

    it 'returns the invalid_source_branch error instead of raising', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_source_branch)
      expect(result.message).to eq('Source branch cannot be blank')
    end
  end

  context 'when a previous readiness score workflow for the work item has already finished' do
    let_it_be(:finished_workflow) do
      create(:duo_workflows_workflow, :finished, work_item: work_item, project: project,
        workflow_definition: 'readiness_score/v1')
    end

    it 'starts a new flow' do
      expect(::Ai::DuoWorkflows::CreateAndStartWorkflowService).to receive(:new)
        .and_return(instance_double(::Ai::DuoWorkflows::CreateAndStartWorkflowService,
          execute: ServiceResponse.success(payload: { workflow: finished_workflow })))

      expect(result).to be_success
    end
  end

  context 'when enabled and the readiness score flow is available' do
    let(:workflow) { instance_double(::Ai::DuoWorkflows::Workflow) }
    let(:downstream) { instance_double(::Ai::DuoWorkflows::CreateAndStartWorkflowService) }
    let(:success_response) { ServiceResponse.success(payload: { workflow: workflow }) }

    it 'starts the readiness score flow with a goal built from the work item', :aggregate_failures do
      expect(::Ai::DuoWorkflows::CreateAndStartWorkflowService).to receive(:new)
        .with(
          container: project,
          resource: work_item,
          current_user: current_user,
          source_branch: project.default_branch,
          workflow_definition: have_attributes(foundational_flow_reference: 'readiness_score/v1'),
          goal: Gitlab::UrlBuilder.build(work_item)
        ).and_return(downstream)
      allow(downstream).to receive(:execute).and_return(success_response)

      expect(result).to be_success
      expect(result.payload[:workflow]).to eq(workflow)
    end
  end
end
