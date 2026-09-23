# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::Adapters::Webhook, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # On the root group, so the examples also cover a hook that reaches the flow
  # through the namespace hierarchy rather than sitting on the project itself.
  # Reloadable: some examples clear the capability flag.
  let_it_be_with_reload(:hook) { create(:group_hook, group: group, duo_flow_callback_enabled: true) }

  let(:hook_id) { hook.id }
  let(:ctx) { { 'adapter' => 'webhook', 'hook_id' => hook_id } }

  subject(:adapter) { described_class.from_callback_context(ctx) }

  # Every guard in find_hook, asserted through the same observable outcome.
  shared_examples 'does not deliver' do
    it 'enqueues nothing' do
      expect(Ai::Messaging::WebhookDeliveryWorker).not_to receive(:perform_async)

      adapter.on_flow_started(callback_context: ctx, workflow: workflow)
    end
  end

  describe '.adapter_key' do
    it { expect(described_class.adapter_key).to eq('webhook') }
  end

  describe '.from_callback_context' do
    it 'builds an adapter carrying the hook id from the context' do
      expect(adapter.build_callback_context).to eq('adapter' => 'webhook', 'hook_id' => hook_id)
    end

    context 'when the context carries a client_reference' do
      let(:ctx) { { 'adapter' => 'webhook', 'hook_id' => hook_id, 'client_reference' => 'autoflow-run-1' } }

      it 'carries it through to build_callback_context' do
        expect(adapter.build_callback_context).to eq(
          'adapter' => 'webhook', 'hook_id' => hook_id, 'client_reference' => 'autoflow-run-1'
        )
      end
    end
  end

  describe '#on_flow_started' do
    it 'enqueues a flow.started delivery carrying the workflow id and base payload', :aggregate_failures do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |id, wf_id, base_payload|
        expect(id).to eq(hook_id)
        # Record data is refetched in the worker from this id, not carried here.
        expect(wf_id).to eq(workflow.id)
        expect(base_payload['object_kind']).to eq('duo_workflow')
        expect(base_payload['version']).to eq('1')
        expect(base_payload['event']).to eq('flow.started')
        expect(base_payload['event_id']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
        expect(base_payload.keys).not_to include('project', 'user', 'workflow')
      end

      adapter.on_flow_started(callback_context: ctx, workflow: workflow)
    end

    context 'when the callback context carries a client_reference' do
      let(:ctx) { { 'adapter' => 'webhook', 'hook_id' => hook_id, 'client_reference' => 'autoflow-run-1' } }

      it 'echoes it back in the payload' do
        expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, _wf_id, base_payload|
          expect(base_payload['client_reference']).to eq('autoflow-run-1')
        end

        adapter.on_flow_started(callback_context: ctx, workflow: workflow)
      end
    end

    context 'when no hook id was persisted in the context' do
      let(:hook_id) { nil }

      it_behaves_like 'does not deliver'
    end

    context 'when the hook no longer exists' do
      let(:hook_id) { non_existing_record_id }

      it_behaves_like 'does not deliver'
    end

    context 'when the capability flag was cleared after the flow started' do
      before do
        hook.update!(duo_flow_callback_enabled: false)
      end

      it_behaves_like 'does not deliver'
    end

    context 'when the instance is in silent mode' do
      before do
        stub_application_setting(silent_mode_enabled: true)
      end

      it_behaves_like 'does not deliver'
    end

    # duo_flow_callback_enabled is on the shared web_hooks table, so a system hook
    # can carry it. Set here so the example exercises the hook-type guard rather
    # than being rejected earlier by the capability guard.
    context 'when the hook is a system hook rather than a project or group hook' do
      let_it_be(:system_hook) { create(:system_hook, duo_flow_callback_enabled: true) }

      let(:hook_id) { system_hook.id }

      it_behaves_like 'does not deliver'
    end
  end

  describe '#deliver_result' do
    it 'enqueues a flow.completed delivery carrying the final message', :aggregate_failures do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, workflow_id, base_payload|
        expect(workflow_id).to eq(workflow.id)
        expect(base_payload['event']).to eq('flow.completed')
        expect(base_payload['result']).to eq('message' => 'All done')
      end

      adapter.deliver_result(callback_context: ctx, message: 'All done', workflow: workflow)
    end

    it 'returns truthy so CallbackWorker marks the outcome delivered' do
      allow(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async).and_return('jid-1')

      expect(adapter.deliver_result(callback_context: ctx, message: 'All done', workflow: workflow)).to be_truthy
    end

    it 'returns falsey when the hook is not deliverable, so CallbackWorker re-attempts' do
      hook.update!(duo_flow_callback_enabled: false)

      expect(adapter.deliver_result(callback_context: ctx, message: 'All done', workflow: workflow)).to be_falsey
    end
  end

  describe '#on_flow_completed' do
    it 'enqueues nothing, because deliver_result already sent flow.completed' do
      expect(Ai::Messaging::WebhookDeliveryWorker).not_to receive(:perform_async)

      adapter.on_flow_completed(callback_context: ctx, workflow: workflow)
    end
  end

  describe '#on_flow_failed' do
    it 'enqueues a flow.failed delivery with the error as an object', :aggregate_failures do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, workflow_id, base_payload|
        expect(workflow_id).to eq(workflow.id)
        expect(base_payload['event']).to eq('flow.failed')
        expect(base_payload['error']).to eq('reason' => 'flow_failed')
      end

      adapter.on_flow_failed(callback_context: ctx, error: :flow_failed, workflow: workflow)
    end

    it 'includes a message when the failure carried one' do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, _wf_id, base_payload|
        expect(base_payload['error']).to eq('reason' => 'boom', 'message' => 'boom')
      end

      adapter.on_flow_failed(callback_context: ctx, error: StandardError.new('boom'), workflow: workflow)
    end

    it 'passes no workflow id when there is no workflow', :aggregate_failures do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, workflow_id, _base_payload|
        expect(workflow_id).to be_nil
      end

      adapter.on_flow_failed(callback_context: ctx, error: :flow_failed, workflow: nil)
    end
  end

  describe '#deliver_error' do
    it 'enqueues a flow.failed delivery', :aggregate_failures do
      expect(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) do |_id, _wf_id, base_payload|
        expect(base_payload['event']).to eq('flow.failed')
        expect(base_payload['error']).to eq('reason' => 'service_account_error')
      end

      adapter.deliver_error(callback_context: ctx, error: :service_account_error)
    end
  end

  describe 'event_id' do
    def event_id_from
      base_payload = nil
      allow(Ai::Messaging::WebhookDeliveryWorker).to receive(:perform_async) { |_id, _wf, e| base_payload = e }
      yield
      base_payload['event_id']
    end

    it 'is stable across redeliveries of the same (workflow, event, hook)' do
      first = event_id_from { adapter.on_flow_started(callback_context: ctx, workflow: workflow) }
      second = event_id_from { adapter.on_flow_started(callback_context: ctx, workflow: workflow) }

      expect(first).to eq(second)
    end

    it 'differs between event types for the same workflow' do
      started = event_id_from { adapter.on_flow_started(callback_context: ctx, workflow: workflow) }
      failed = event_id_from do
        adapter.on_flow_failed(callback_context: ctx, error: :flow_failed, workflow: workflow)
      end

      expect(started).not_to eq(failed)
    end

    it 'differs between two failures that carry no workflow' do
      first = event_id_from { adapter.deliver_error(callback_context: ctx, error: :service_account_error) }
      second = event_id_from { adapter.deliver_error(callback_context: ctx, error: :service_account_error) }

      expect(first).not_to eq(second)
    end

    it 'differs between two hooks receiving the same flow event' do
      other_hook = create(:project_hook, project: project, duo_flow_callback_enabled: true)

      first = event_id_from { adapter.on_flow_started(callback_context: ctx, workflow: workflow) }
      second = event_id_from do
        described_class
          .from_callback_context({ 'hook_id' => other_hook.id })
          .on_flow_started(callback_context: ctx, workflow: workflow)
      end

      expect(first).not_to eq(second)
    end
  end
end
