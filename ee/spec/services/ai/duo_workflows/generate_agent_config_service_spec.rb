# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::GenerateAgentConfigService, feature_category: :duo_agent_platform do
  include ExclusiveLeaseHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:service) { described_class.new(project: project, current_user: user) }
  let(:workflow) { build_stubbed(:duo_workflows_workflow, id: 77) }
  let(:execute_result) { ServiceResponse.success(payload: { workflow: workflow }) }
  let(:consumer) { instance_double(Ai::Catalog::ItemConsumer, active_service_account: nil) }
  let(:consumer_scope) { double('consumer_scope') } # rubocop:disable RSpec/VerifiedDoubles -- AR named scopes are not instance methods on ActiveRecord::Relation
  let(:catalog_item) { instance_double(Ai::Catalog::Item, consumers: consumer_scope) }
  let(:foundational_flow) { instance_double(Ai::Catalog::FoundationalFlow, catalog_item: catalog_item) }
  let(:tracker) { instance_double(Ai::DuoWorkflow::AgentConfigWorkflowTracker, active_workflow: nil, track: true) }
  let(:flow_service) { instance_double(Ai::Catalog::Flows::ExecuteService, execute: execute_result) }
  let(:agent_config_present) { false }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(true)
    allow_next_instance_of(Gitlab::DuoAgentPlatform::Config) do |config|
      allow(config).to receive(:config_present?).and_return(agent_config_present)
    end
    allow(Ai::DuoWorkflow::AgentConfigWorkflowTracker).to receive(:new).with(project).and_return(tracker)
    allow(Ai::Catalog::FoundationalFlow).to receive(:developer_v1).and_return(foundational_flow)
    allow(consumer_scope).to receive(:for_projects).with(project).and_return(consumer_scope)
    allow(consumer_scope).to receive(:first).and_return(consumer)
    allow(Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(flow_service)
  end

  describe '#execute' do
    it 'starts the developer flow with the agent config goal and tracks the workflow', :aggregate_failures do
      goal = Ai::Catalog::GoalTemplates::Developer.resolve(
        event_type: :init_execution_env,
        resource: project,
        user_input: nil,
        params: { triggered_by_username: user.username }
      )

      expect(Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: project,
        current_user: user,
        params: {
          item_consumer: consumer,
          user_prompt: goal,
          event_type: 'web',
          execute_workflow: true,
          service_account: nil
        }
      ).and_return(flow_service)

      result = service.execute

      expect(result).to be_success
      expect(result.payload).to eq(workflow_id: 77)
      expect(tracker).to have_received(:track).with(workflow)
    end

    context 'when no project-level consumer exists' do
      before do
        allow(consumer_scope).to receive(:first).and_return(nil)
      end

      it 'passes a nil consumer to the flow' do
        expect(Ai::Catalog::Flows::ExecuteService).to receive(:new)
          .with(hash_including(params: hash_including(item_consumer: nil, service_account: nil)))
          .and_return(flow_service)

        service.execute
      end
    end

    context 'when the developer flow has no catalog item' do
      let(:foundational_flow) { instance_double(Ai::Catalog::FoundationalFlow, catalog_item: nil) }

      it 'passes a nil consumer to the flow' do
        expect(Ai::Catalog::Flows::ExecuteService).to receive(:new)
          .with(hash_including(params: hash_including(item_consumer: nil, service_account: nil)))
          .and_return(flow_service)

        service.execute
      end
    end

    context 'when the user lacks duo_workflow access' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(false)
      end

      it 'returns an error without starting a flow', :aggregate_failures do
        expect(Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('You have insufficient permissions')
      end
    end

    context 'when the agent configuration file already exists' do
      let(:agent_config_present) { true }

      it 'returns an error without starting a flow', :aggregate_failures do
        expect(Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('The agent configuration file already exists.')
      end
    end

    context 'when a generation workflow is already active' do
      let(:active_workflow) { build_stubbed(:duo_workflows_workflow, id: 55) }

      before do
        allow(tracker).to receive(:active_workflow).and_return(active_workflow)
      end

      it 'returns an error carrying the active workflow id', :aggregate_failures do
        expect(Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('An agent configuration run is already in progress.')
        expect(result.payload[:workflow_id]).to eq(55)
      end
    end

    context 'when the lease is already taken' do
      before do
        stub_exclusive_lease_taken("duo_agent_config_generation:#{project.id}")
      end

      it 'returns an error without starting a flow', :aggregate_failures do
        expect(Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('An agent configuration run is already in progress.')
      end
    end

    context 'when the flow fails to start' do
      let(:execute_result) { ServiceResponse.error(message: ['boom']) }

      it 'returns the first flow error as a string and tracks nothing', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('boom')
        expect(tracker).not_to have_received(:track)
      end
    end
  end
end
