# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::CallbackWorker, feature_category: :duo_agent_platform do
  describe '#handle_event' do
    subject(:worker) { described_class.new }

    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }

    let(:callback_context) { { 'adapter' => 'test_adapter', 'channel_id' => 'C123' } }

    let(:workflow) do
      create(:duo_workflows_workflow,
        user: user,
        project: project,
        messaging_callback_context: callback_context)
    end

    let(:workload) { create(:ci_workload) }

    let(:event) do
      Ci::Workloads::WorkloadFinishedEvent.new(
        data: { workload_id: workload.id, status: status }
      )
    end

    let(:status) { 'finished' }

    let(:test_adapter_class) do
      Class.new(Ai::Messaging::Adapters::Base) do
        attr_reader :delivered_results, :delivered_errors, :started_flows, :completed_flows, :failed_flows,
          :approval_requests, :input_requests

        def self.adapter_key
          'test_adapter'
        end

        def self.from_callback_context(_ctx)
          new
        end

        def initialize
          @delivered_results = []
          @delivered_errors = []
          @started_flows = []
          @completed_flows = []
          @failed_flows = []
          @approval_requests = []
          @input_requests = []
        end

        def on_flow_started(callback_context:, workflow:)
          @started_flows << { callback_context: callback_context, workflow: workflow }
        end

        def on_approval_required(callback_context:, workflow:)
          @approval_requests << { callback_context: callback_context, workflow: workflow }
        end

        def on_input_required(callback_context:, workflow:)
          @input_requests << { callback_context: callback_context, workflow: workflow }
        end

        def build_callback_context
          {}
        end

        def deliver_result(callback_context:, message:, workflow:)
          @delivered_results << { callback_context: callback_context, message: message, workflow: workflow }
          true
        end

        def deliver_error(callback_context:, error:)
          @delivered_errors << { callback_context: callback_context, error: error }
        end

        def on_flow_completed(callback_context:, workflow:)
          @completed_flows << { callback_context: callback_context, workflow: workflow }
        end

        def on_flow_failed(callback_context:, error:, workflow: nil)
          @failed_flows << { callback_context: callback_context, error: error, workflow: workflow }
          deliver_error(callback_context: callback_context, error: error)
        end
      end
    end

    let(:test_adapter_instance) { test_adapter_class.new }

    before do
      create(:duo_workflows_workload, workflow: workflow, workload: workload, project: project)

      stub_const('Ai::Messaging::AdapterRegistry::ADAPTERS', { 'test_adapter' => test_adapter_class }.freeze)
      allow(test_adapter_class).to receive(:from_callback_context).and_return(test_adapter_instance)
    end

    context 'when workload does not exist' do
      let(:event) do
        Ci::Workloads::WorkloadFinishedEvent.new(
          data: { workload_id: non_existing_record_id, status: 'finished' }
        )
      end

      it 'returns early without error' do
        expect { worker.handle_event(event) }.not_to raise_error
      end
    end

    context 'when workflow has no messaging_callback_context' do
      before do
        workflow.update_column(:messaging_callback_context, nil)
      end

      it 'skips processing' do
        worker.handle_event(event)
        expect(test_adapter_instance.delivered_results).to be_empty
      end
    end

    context 'when adapter is not registered' do
      let(:callback_context) { { 'adapter' => 'unknown', 'channel_id' => 'C123' } }

      it 'logs a warning and skips processing' do
        expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(adapter: 'unknown'))

        worker.handle_event(event)
        expect(test_adapter_instance.delivered_results).to be_empty
      end
    end

    context 'when flow failed' do
      let(:status) { 'failed' }

      it 'calls on_flow_failed with :flow_failed and the workflow' do
        worker.handle_event(event)

        expect(test_adapter_instance.failed_flows).to contain_exactly(
          hash_including(error: :flow_failed, workflow: workflow)
        )
      end

      it 'claims the delivery so the failure is reported once', :aggregate_failures do
        worker.handle_event(event)
        described_class.new.handle_event(event)

        expect(test_adapter_instance.failed_flows.size).to eq(1)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      context 'when the failure was already delivered' do
        before do
          workflow.merge_messaging_callback_context!('delivered_at' => Time.current.utc.iso8601)
        end

        it 'posts nothing' do
          worker.handle_event(event)

          expect(test_adapter_instance.failed_flows).to be_empty
        end
      end
    end

    context 'when the workload ends while the session waits on the user' do
      let(:states) { Ai::DuoWorkflows::Workflow.state_machine(:status).states }

      before do
        create(:duo_workflows_checkpoint,
          workflow: workflow,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => [
                { 'message_type' => 'agent', 'content' => 'Interim output' },
                { 'message_type' => 'request', 'content' => 'Tool create_issue requires approval' }
              ]
            }
          })
      end

      %i[paused input_required plan_approval_required tool_call_approval_required].each do |paused_status|
        context "with the session in #{paused_status}" do
          before do
            workflow.update_column(:status, states[paused_status].value)
          end

          context 'and the job finished cleanly' do
            it 'treats it as a pause: delivers nothing and claims nothing', :aggregate_failures do
              worker.handle_event(event)

              expect(test_adapter_instance.delivered_results).to be_empty
              expect(test_adapter_instance.failed_flows).to be_empty
              expect(workflow.reload.messaging_callback_context).not_to have_key('delivered_at')
            end
          end

          context 'and the job failed' do
            let(:status) { 'failed' }

            it 'delivers no failure' do
              worker.handle_event(event)

              expect(test_adapter_instance.failed_flows).to be_empty
            end
          end
        end
      end

      it 'still delivers the real answer once the session finishes later', :aggregate_failures do
        workflow.update_column(:status, states[:tool_call_approval_required].value)
        worker.handle_event(event)

        workflow.update_column(:status, states[:finished].value)
        create(:duo_workflows_checkpoint,
          workflow: workflow,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => [
                { 'message_type' => 'agent', 'content' => 'Interim output' },
                { 'message_type' => 'request', 'content' => 'Tool create_issue requires approval' },
                { 'message_type' => 'agent', 'content' => 'Issue created.' }
              ]
            }
          })

        described_class.new.handle_event(
          Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: workflow.id })
        )

        expect(test_adapter_instance.delivered_results).to contain_exactly(
          hash_including(message: 'Issue created.', workflow: workflow)
        )
      end
    end

    context 'when handling a WorkflowFailedEvent' do
      let(:status_event) { 'drop' }
      let(:event) do
        Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow, status_event: status_event)
      end

      it 'calls on_flow_failed with :flow_failed for a drop' do
        worker.handle_event(event)

        expect(test_adapter_instance.failed_flows).to contain_exactly(
          hash_including(error: :flow_failed, workflow: workflow)
        )
      end

      context 'when the session was stopped' do
        let(:status_event) { 'stop' }

        it 'calls on_flow_failed with :flow_stopped' do
          worker.handle_event(event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :flow_stopped, workflow: workflow)
          )
        end
      end

      it 'claims the delivery so the CI backstop does not report the failure again', :aggregate_failures do
        worker.handle_event(event)
        described_class.new.handle_event(
          Ci::Workloads::WorkloadFinishedEvent.new(data: { workload_id: workload.id, status: 'failed' })
        )

        expect(test_adapter_instance.failed_flows.size).to eq(1)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      context 'when the outcome was already delivered' do
        before do
          workflow.merge_messaging_callback_context!('delivered_at' => Time.current.utc.iso8601)
        end

        it 'posts nothing' do
          worker.handle_event(event)

          expect(test_adapter_instance.failed_flows).to be_empty
        end
      end

      context 'when the workflow does not exist' do
        let(:event) do
          Ai::DuoWorkflows::WorkflowFailedEvent.build(
            workflow: instance_double(Ai::DuoWorkflows::Workflow, id: non_existing_record_id), status_event: 'drop'
          )
        end

        it 'returns early without error' do
          expect { worker.handle_event(event) }.not_to raise_error
          expect(test_adapter_instance.failed_flows).to be_empty
        end
      end

      context 'when on_flow_failed raises an error' do
        before do
          allow(test_adapter_instance).to receive(:on_flow_failed).and_raise(StandardError, 'failed hook failed')
        end

        it 'tracks the exception without re-raising' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)

          expect { worker.handle_event(event) }.not_to raise_error
        end
      end
    end

    context 'when handling a WorkflowApprovalRequiredEvent' do
      let(:event) do
        Ai::DuoWorkflows::WorkflowApprovalRequiredEvent.build(workflow: workflow)
      end

      it 'calls on_approval_required with the workflow' do
        worker.handle_event(event)

        expect(test_adapter_instance.approval_requests).to contain_exactly(
          hash_including(callback_context: callback_context, workflow: workflow)
        )
      end

      it 'does not claim the delivery' do
        worker.handle_event(event)

        expect(workflow.reload.messaging_callback_context).not_to have_key('delivered_at')
      end

      context 'when the workflow does not exist' do
        let(:event) do
          Ai::DuoWorkflows::WorkflowApprovalRequiredEvent.build(
            workflow: instance_double(Ai::DuoWorkflows::Workflow, id: non_existing_record_id)
          )
        end

        it 'returns early without error' do
          expect { worker.handle_event(event) }.not_to raise_error
          expect(test_adapter_instance.approval_requests).to be_empty
        end
      end

      context 'when the workflow has no messaging_callback_context' do
        before do
          workflow.update_column(:messaging_callback_context, nil)
        end

        it 'skips processing' do
          worker.handle_event(event)
          expect(test_adapter_instance.approval_requests).to be_empty
        end
      end

      context 'when on_approval_required raises an error' do
        before do
          allow(test_adapter_instance).to receive(:on_approval_required).and_raise(StandardError, 'hook failed')
        end

        it 'tracks the exception without re-raising' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)

          expect { worker.handle_event(event) }.not_to raise_error
        end
      end
    end

    context 'when handling a WorkflowInputRequiredEvent' do
      let(:event) do
        Ai::DuoWorkflows::WorkflowInputRequiredEvent.build(workflow: workflow)
      end

      it 'calls on_input_required with the workflow' do
        worker.handle_event(event)

        expect(test_adapter_instance.input_requests).to contain_exactly(
          hash_including(callback_context: callback_context, workflow: workflow)
        )
      end

      # The session continues after this pause, so a claim here would suppress the
      # answer the next turn produces.
      it 'does not claim the delivery' do
        worker.handle_event(event)

        expect(workflow.reload.messaging_callback_context).not_to have_key('delivered_at')
      end

      context 'when the workflow has no messaging_callback_context' do
        before do
          workflow.update_column(:messaging_callback_context, nil)
        end

        it 'skips processing' do
          worker.handle_event(event)

          expect(test_adapter_instance.input_requests).to be_empty
        end
      end

      context 'when on_input_required raises an error' do
        before do
          allow(test_adapter_instance).to receive(:on_input_required).and_raise(StandardError, 'hook failed')
        end

        it 'tracks the exception without re-raising' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)

          expect { worker.handle_event(event) }.not_to raise_error
        end
      end
    end

    context 'when handling a WorkflowStartedEvent' do
      let(:event) do
        Ai::DuoWorkflows::WorkflowStartedEvent.new(data: { workflow_id: workflow.id })
      end

      it 'calls on_flow_started with the workflow' do
        worker.handle_event(event)

        expect(test_adapter_instance.started_flows).to contain_exactly(
          hash_including(workflow: workflow)
        )
      end

      context 'when the workflow does not exist' do
        let(:event) do
          Ai::DuoWorkflows::WorkflowStartedEvent.new(data: { workflow_id: non_existing_record_id })
        end

        it 'returns early without error' do
          expect { worker.handle_event(event) }.not_to raise_error
          expect(test_adapter_instance.started_flows).to be_empty
        end
      end

      context 'when the workflow has no messaging_callback_context' do
        before do
          workflow.update_column(:messaging_callback_context, nil)
        end

        it 'skips processing' do
          worker.handle_event(event)
          expect(test_adapter_instance.started_flows).to be_empty
        end
      end

      context 'when on_flow_started raises an error' do
        before do
          allow(test_adapter_instance).to receive(:on_flow_started).and_raise(StandardError, 'started hook failed')
        end

        it 'tracks the exception without re-raising' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)

          expect { worker.handle_event(event) }.not_to raise_error
        end
      end
    end

    context 'when deliver_result raises an error' do
      let(:event) do
        Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: workflow.id })
      end

      before do
        create(:duo_workflows_checkpoint,
          workflow: workflow,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => [
                { 'message_type' => 'agent', 'content' => 'Result' }
              ]
            }
          })

        allow(test_adapter_instance).to receive(:deliver_result).and_raise(StandardError, 'delivery failed')
      end

      it 'tracks the exception once, releases the claim, and raises for a Sidekiq retry', :aggregate_failures do
        # Returns its trackers, as the real method does: a swallowed error must read as a
        # failed delivery on the tracker's return value, not on a happens-to-be-nil stub.
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .at_least(:once).and_return([::Gitlab::ErrorTracking::Logger])

        expect { worker.handle_event(event) }.to raise_error(described_class::DeliveryRetryError)

        context_after = workflow.reload.messaging_callback_context
        expect(test_adapter_instance.completed_flows).to be_empty
        expect(context_after).to have_key('delivered_at')
        expect(context_after['delivered_at']).to be_nil
      end
    end

    context 'when on_flow_completed raises an error' do
      let(:event) do
        Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: workflow.id })
      end

      before do
        create(:duo_workflows_checkpoint,
          workflow: workflow,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => [
                { 'message_type' => 'agent', 'content' => 'Result' }
              ]
            }
          })

        allow(test_adapter_instance).to receive(:on_flow_completed).and_raise(StandardError, 'completed hook failed')
      end

      it 'tracks the exception without re-raising' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        expect { worker.handle_event(event) }.not_to raise_error
      end
    end

    context 'when handling a WorkflowFinishedEvent' do
      let(:finished_event) do
        Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: workflow.id })
      end

      context 'with a final agent message in checkpoints' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => 'I fixed the pipeline.' }
                ]
              }
            })
        end

        it 'delivers the result to the adapter', :aggregate_failures do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results).to contain_exactly(
            hash_including(message: 'I fixed the pipeline.', workflow: workflow)
          )
        end

        it 'calls on_flow_completed' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.completed_flows).to contain_exactly(
            hash_including(workflow: workflow)
          )
        end

        it 'records the delivery on the workflow' do
          worker.handle_event(finished_event)

          expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
        end

        it 'does not deliver again on the WorkloadFinishedEvent' do
          worker.handle_event(finished_event)
          worker.handle_event(event)

          expect(test_adapter_instance.delivered_results.size).to eq(1)
        end

        it 'does not deliver again when the event is redelivered' do
          worker.handle_event(finished_event)
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results.size).to eq(1)
        end

        context 'when the adapter reports a failed delivery' do
          before do
            allow(test_adapter_instance).to receive(:deliver_result).and_return(false)
          end

          it 'releases the claim, logs, and raises for a Sidekiq retry', :aggregate_failures do
            expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
              message: 'Duo Messaging: Result delivery failed; released claim for Sidekiq retry',
              workflow_id: workflow.id
            ))

            expect { worker.handle_event(finished_event) }
              .to raise_error(described_class::DeliveryRetryError)

            context_after = workflow.reload.messaging_callback_context
            expect(context_after).to have_key('delivered_at')
            expect(context_after['delivered_at']).to be_nil
            expect(test_adapter_instance.completed_flows).to be_empty
          end

          it 'delivers the answer on the WorkloadFinishedEvent instead', :aggregate_failures do
            expect { worker.handle_event(finished_event) }
              .to raise_error(described_class::DeliveryRetryError)
            allow(test_adapter_instance).to receive(:deliver_result).and_call_original

            worker.handle_event(event)

            expect(test_adapter_instance.delivered_results).to contain_exactly(
              hash_including(message: 'I fixed the pipeline.', workflow: workflow)
            )
            expect(test_adapter_instance.completed_flows).to contain_exactly(
              hash_including(workflow: workflow)
            )
          end
        end

        context 'when the backstop event arrives while delivery is in flight' do
          it 'delivers exactly once', :aggregate_failures do
            interleaved = false
            allow(test_adapter_instance).to receive(:deliver_result).and_wrap_original do |original, **kwargs|
              unless interleaved
                interleaved = true
                # The WorkloadFinishedEvent job lands mid-delivery, as in production
                # when the agent container exits right after its final message.
                described_class.new.handle_event(event)
              end

              original.call(**kwargs)
            end

            worker.handle_event(finished_event)

            expect(test_adapter_instance.delivered_results.size).to eq(1)
            expect(test_adapter_instance.completed_flows.size).to eq(1)
          end
        end

        context 'when the backstop skips mid-delivery and the delivery then fails' do
          it 'raises from the failing job and the retry redelivers exactly once', :aggregate_failures do
            failed_once = false
            allow(test_adapter_instance).to receive(:deliver_result).and_wrap_original do |original, **kwargs|
              next original.call(**kwargs) if failed_once

              failed_once = true
              # The backstop lands mid-delivery: the claim is held, so it skips at the
              # guard and is spent. The failing winner must raise for its Sidekiq retry.
              described_class.new.handle_event(event)
              false
            end

            expect { worker.handle_event(finished_event) }
              .to raise_error(described_class::DeliveryRetryError)

            expect(test_adapter_instance.delivered_results).to be_empty

            # The Sidekiq retry re-entering handle_event.
            worker.handle_event(finished_event)

            expect(test_adapter_instance.delivered_results.size).to eq(1)
            expect(test_adapter_instance.completed_flows.size).to eq(1)
          end
        end

        context 'when the claim is lost to a concurrent job' do
          before do
            allow_next_found_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
              allow(instance).to receive(:claim_messaging_callback_delivery).and_wrap_original do |original|
                # A concurrent job claims between this job's guard read and its UPDATE,
                # so the original claim runs its real conditional SQL and loses.
                Ai::DuoWorkflows::Workflow.where(id: instance.id).update_all(
                  Arel.sql(%q(messaging_callback_context = messaging_callback_context ||
                    '{"delivered_at": "2026-08-20T00:00:00Z"}'::jsonb))
                )

                original.call
              end
            end
          end

          it 'stands down without delivering or raising', :aggregate_failures do
            expect { worker.handle_event(finished_event) }.not_to raise_error

            expect(test_adapter_instance.delivered_results).to be_empty
            expect(test_adapter_instance.completed_flows).to be_empty
          end
        end

        context 'when a failed delivery released the claim as JSON null' do
          before do
            workflow.merge_messaging_callback_context!('delivered_at' => nil)
          end

          it 'claims again and delivers on the retried event' do
            worker.handle_event(finished_event)

            expect(test_adapter_instance.delivered_results.size).to eq(1)
          end
        end
      end

      context 'when the last agent message is empty but an earlier one has content' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => 'I fixed the pipeline.' },
                  { 'message_type' => 'agent', 'content' => '' }
                ]
              }
            })
        end

        it 'delivers the last non-empty agent message' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results).to contain_exactly(
            hash_including(message: 'I fixed the pipeline.')
          )
        end
      end

      context 'when the last agent message has nil content but an earlier one has content' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => 'I fixed the pipeline.' },
                  { 'message_type' => 'agent', 'content' => nil }
                ]
              }
            })
        end

        it 'delivers the last non-empty agent message' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results).to contain_exactly(
            hash_including(message: 'I fixed the pipeline.')
          )
        end
      end

      context 'when the last agent message has tool_calls but an earlier one has content' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => 'I fixed the pipeline.' },
                  { 'message_type' => 'agent', 'content' => 'Marking todos done',
                    'tool_calls' => [{ 'name' => 'complete_todo' }] }
                ]
              }
            })
        end

        it 'delivers the last agent message without tool calls' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results).to contain_exactly(
            hash_including(message: 'I fixed the pipeline.')
          )
        end
      end

      context 'when all agent messages have empty content' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => '' },
                  { 'message_type' => 'agent', 'content' => nil }
                ]
              }
            })
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end

        it 'does not report the error again on the WorkloadFinishedEvent' do
          worker.handle_event(finished_event)
          worker.handle_event(event)

          expect(test_adapter_instance.failed_flows.size).to eq(1)
        end
      end

      context 'when all agent messages have tool_calls' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' },
                  { 'message_type' => 'agent', 'content' => 'Working',
                    'tool_calls' => [{ 'name' => 'do_thing' }] }
                ]
              }
            })
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when the notifications read gate is on' do
        let(:workflow) do
          create(:duo_workflows_workflow,
            user: user, project: project, messaging_callback_context: callback_context,
            incremental_checkpoints_enabled: true)
        end

        before do
          create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', parent_ts: nil,
            current_thread: 0, channel_keys: %w[ui_chat_log])
          header_log = [{ 'message_type' => 'user', 'content' => 'header' }]
          create(:duo_workflows_checkpoint, workflow: workflow, project: project, thread_ts: 'ts-1',
            current_thread: 0, checkpoint: { 'channel_values' => { 'ui_chat_log' => header_log } })
          create(:duo_workflows_checkpoint_blob,
            workflow: workflow, thread_ts: 'ts-1', current_thread: 0, channel: 'ui_chat_log',
            version: '1', write_type: 'json', step_action: 'conversation', workflow_created_at: workflow.created_at,
            data: Zlib::Deflate.deflate(::Gitlab::Json.dump(
              [{ 'message_type' => 'agent', 'content' => 'From incremental blob.' }])))
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_notifications: project)
        end

        it 'delivers the message reconstructed from incremental blobs' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.delivered_results).to contain_exactly(
            hash_including(message: 'From incremental blob.')
          )
        end
      end

      context 'when latest checkpoint has nil checkpoint data' do
        let(:checkpoint_record) do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: { 'channel_values' => {} })
        end

        before do
          checkpoint_record
          allow(checkpoint_record).to receive(:checkpoint).and_return(nil)
          allow(workflow.checkpoints).to receive(:latest).and_return(checkpoint_record)
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when checkpoint has no channel_values' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: { 'some_other_key' => 'value' })
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when chat log contains only user messages' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: {
              'channel_values' => {
                'ui_chat_log' => [
                  { 'message_type' => 'user', 'content' => 'Fix CI' }
                ]
              }
            })
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when checkpoints have no agent message' do
        before do
          create(:duo_workflows_checkpoint,
            workflow: workflow,
            project: project,
            checkpoint: { 'channel_values' => { 'ui_chat_log' => [] } })
        end

        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when no checkpoints exist' do
        it 'calls on_flow_failed with :no_response and the workflow' do
          worker.handle_event(finished_event)

          expect(test_adapter_instance.failed_flows).to contain_exactly(
            hash_including(error: :no_response, workflow: workflow)
          )
        end
      end

      context 'when the workflow does not exist' do
        let(:finished_event) do
          Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: non_existing_record_id })
        end

        it 'returns early without error' do
          expect { worker.handle_event(finished_event) }.not_to raise_error
          expect(test_adapter_instance.delivered_results).to be_empty
        end
      end

      context 'when the workflow has no messaging_callback_context' do
        before do
          workflow.update_column(:messaging_callback_context, nil)
        end

        it 'skips processing' do
          worker.handle_event(finished_event)
          expect(test_adapter_instance.delivered_results).to be_empty
        end
      end

      context 'when a WorkloadFinishedEvent reports a non-finished status' do
        let(:status) { 'failed' }

        context 'and the workflow already finished' do
          before do
            finished_value = Ai::DuoWorkflows::Workflow.state_machines[:status].states[:finished].value
            workflow.update_column(:status, finished_value)
          end

          context 'and the reply was already delivered' do
            before do
              workflow.merge_messaging_callback_context!('delivered_at' => Time.current.utc.iso8601)
            end

            it 'posts nothing over the already-delivered reply', :aggregate_failures do
              worker.handle_event(event)

              expect(test_adapter_instance.failed_flows).to be_empty
              expect(test_adapter_instance.delivered_results).to be_empty
            end
          end

          context 'and the reply was never delivered' do
            before do
              create(:duo_workflows_checkpoint,
                workflow: workflow,
                project: project,
                checkpoint: {
                  'channel_values' => {
                    'ui_chat_log' => [
                      { 'message_type' => 'agent', 'content' => 'I fixed the pipeline.' }
                    ]
                  }
                })
            end

            it 'delivers the answer rather than a failure', :aggregate_failures do
              worker.handle_event(event)

              expect(test_adapter_instance.delivered_results).to contain_exactly(
                hash_including(message: 'I fixed the pipeline.', workflow: workflow)
              )
              expect(test_adapter_instance.failed_flows).to be_empty
            end
          end
        end

        context 'and the workflow has not finished' do
          it 'delivers the failure' do
            worker.handle_event(event)

            expect(test_adapter_instance.failed_flows).to contain_exactly(
              hash_including(error: :flow_failed, workflow: workflow)
            )
          end
        end
      end
    end
  end

  describe 'worker configuration' do
    it { expect(described_class.get_feature_category).to eq(:duo_agent_platform) }

    it 'declares external dependencies' do
      expect(described_class.worker_has_external_dependencies?).to be(true)
    end

    it 'caps Sidekiq retries' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end

    it 'keeps expected delivery retries out of Sentry and the execution SLI' do
      expect(described_class::DeliveryRetryError.new).to be_a(::Gitlab::SidekiqMiddleware::RetryError)
    end
  end

  describe '.sidekiq_retries_exhausted' do
    it 'warns with the identifiers and error class from the job' do
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
        message: 'Duo Messaging: retries exhausted; giving up',
        error_class: 'Ai::Messaging::ResultDelivery::DeliveryRetryError',
        workflow_id: 123
      ))

      described_class.sidekiq_retries_exhausted_block.call(
        { 'args' => ['Ai::DuoWorkflows::WorkflowFinishedEvent', { 'workflow_id' => 123 }] },
        described_class::DeliveryRetryError.new
      )
    end

    it 'handles the batched data shape from the event store subscriber' do
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
        message: 'Duo Messaging: retries exhausted; giving up',
        workload_id: 456
      ))

      described_class.sidekiq_retries_exhausted_block.call(
        { 'args' => ['Ci::Workloads::WorkloadFinishedEvent', [{ 'workload_id' => 456, 'status' => 'finished' }]] },
        described_class::DeliveryRetryError.new
      )
    end
  end

  describe 'event subscription' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }
    let_it_be(:workload) { create(:ci_workload) }

    before do
      create(:duo_workflows_workload, workflow: workflow, workload: workload, project: project)
    end

    it_behaves_like 'subscribes to event' do
      let(:event) do
        Ci::Workloads::WorkloadFinishedEvent.new(data: { workload_id: workload.id, status: 'finished' })
      end
    end

    it_behaves_like 'subscribes to event' do
      let(:event) { Ai::DuoWorkflows::WorkflowStartedEvent.new(data: { workflow_id: workflow.id }) }
    end

    it_behaves_like 'subscribes to event' do
      let(:event) { Ai::DuoWorkflows::WorkflowFinishedEvent.new(data: { workflow_id: workflow.id }) }
    end

    it_behaves_like 'subscribes to event' do
      let(:event) { Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow, status_event: 'drop') }
    end

    it_behaves_like 'subscribes to event' do
      let(:event) { Ai::DuoWorkflows::WorkflowApprovalRequiredEvent.build(workflow: workflow) }
    end
  end
end
