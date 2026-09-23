# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::ServerSideTurnWorker, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:callback_context) { { 'adapter' => 'slack', 'channel_id' => 'C1' } }

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, :running, user: user, project: project,
      workflow_definition: 'slack_assistant/v1', goal: 'What does this project do?')
  end

  let(:adapter) { instance_double(Ai::Messaging::Adapters::Slack) }
  let(:execution_result) { ServiceResponse.success(payload: { workflow: workflow }) }

  subject(:worker) { described_class.new }

  before do
    workflow.update!(messaging_callback_context: callback_context)

    allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_return(adapter)
    allow(adapter).to receive_messages(deliver_result: true, on_flow_completed: nil, on_flow_failed: nil)

    allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
      allow(service).to receive(:execute).and_return(execution_result)
    end
  end

  describe '#perform' do
    it 'runs the turn with the goal recorded on the workflow' do
      expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
        .with(workflow: workflow, goal: workflow.goal, approval: nil).and_call_original

      worker.perform(workflow.id)
    end

    it 'forwards an approval so a resume runs through the same worker' do
      approval = { 'approval' => { 'approved' => true } }

      expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
        .with(workflow: workflow, goal: workflow.goal, approval: approval).and_call_original

      worker.perform(workflow.id, approval)
    end

    context 'when the turn paused for an approval' do
      before do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { 'channel_values' => { 'ui_chat_log' => [
            { 'message_type' => 'agent', 'content' => 'I need to run a command first.' }
          ] } })

        workflow.require_tool_call_approval!
      end

      # Delivering here would post an interim message and claim the delivery,
      # suppressing the real answer once the run resumes and finishes.
      it 'delivers nothing and leaves the delivery unclaimed', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
        expect(adapter).not_to have_received(:on_flow_completed)
        expect(adapter).not_to have_received(:on_flow_failed)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
      end
    end

    context 'when the turn is answering a later message' do
      it 'runs the turn with that message rather than the session goal' do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
          .with(workflow: workflow, goal: 'And who maintains it?', approval: nil).and_call_original

        worker.perform(workflow.id, nil, 'And who maintains it?')
      end
    end

    context 'when the turn produced an answer' do
      before do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { 'channel_values' => { 'ui_chat_log' => [
            { 'message_type' => 'user', 'content' => 'What does this project do?' },
            { 'message_type' => 'agent', 'content' => 'It runs GitLab.' }
          ] } })

        workflow.require_input!
      end

      it 'delivers it and marks the flow completed', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).to have_received(:deliver_result)
          .with(callback_context: callback_context, message: 'It runs GitLab.', workflow: workflow)
        expect(adapter).to have_received(:on_flow_completed)
      end

      it 'claims the delivery so live progress stops re-rendering over the answer' do
        worker.perform(workflow.id)

        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      it 'does not deliver twice when the job is retried' do
        worker.perform(workflow.id)
        worker.perform(workflow.id)

        expect(adapter).to have_received(:deliver_result).once
      end
    end

    context 'when the turn failed' do
      let(:execution_result) { ServiceResponse.error(message: 'locked', reason: :workflow_locked) }

      it 'reports the reason to the surface', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).to have_received(:on_flow_failed)
          .with(callback_context: callback_context, error: :workflow_locked, workflow: workflow)
        expect(adapter).not_to have_received(:deliver_result)
      end

      it 'claims the delivery so the failure is reported once' do
        worker.perform(workflow.id)

        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      it 'does not report again when the drop event reaches CallbackWorker' do
        worker.perform(workflow.id)
        workflow.reload.drop!

        expect(adapter).to have_received(:on_flow_failed).once
      end

      context 'when the outcome was already delivered' do
        before do
          workflow.claim_messaging_callback_delivery
        end

        it 'reports nothing' do
          worker.perform(workflow.id)

          expect(adapter).not_to have_received(:on_flow_failed)
        end
      end
    end

    context 'when the workflow no longer exists' do
      it 'does nothing' do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)

        worker.perform(non_existing_record_id)
      end
    end

    context 'when the workflow has no messaging callback context' do
      before do
        workflow.update!(messaging_callback_context: nil)
      end

      it 'still runs the turn, but delivers nothing', :aggregate_failures do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new).and_call_original

        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
      end
    end
  end
end
