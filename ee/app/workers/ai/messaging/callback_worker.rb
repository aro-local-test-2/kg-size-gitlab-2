# frozen_string_literal: true

module Ai
  module Messaging
    # Sole EventStore subscriber for messaging-lifecycle events (@GitLabDuo note
    # replies and Slack): resolves the adapter from the workflow's
    # messaging_callback_context and fires the matching lifecycle hook inline.
    # Marked as having external dependencies because some adapters (e.g. Slack)
    # call third-party APIs.
    #
    # rubocop:disable Scalability/IdempotentWorker -- EventStore::Subscriber includes idempotent
    class CallbackWorker
      include Gitlab::EventStore::Subscriber
      include ::Ai::Messaging::ResultDelivery

      feature_category :duo_agent_platform

      # :sticky is the preferred consistency for jobs that should run as fast as possible: replicas
      # are guaranteed caught up to the enqueue point and the job falls back to the primary otherwise,
      # so there is no reschedule delay on replica lag.
      data_consistency :sticky
      worker_has_external_dependencies!

      # Without this the DeliveryRetryError raise would inherit Sidekiq's default 25.
      sidekiq_options retry: 3

      sidekiq_retries_exhausted do |job, exception|
        # Runs outside the job context and Sidekiq swallows raises from this block, so
        # keep it a bare log. Array.wrap: Subscriber can batch the data arg. error_class
        # says what exhausted the shared retry budget (a dropped delivery vs anything else).
        data = Array.wrap(job['args'].second).first.to_h

        Gitlab::AppLogger.warn(
          message: 'Duo Messaging: retries exhausted; giving up',
          error_class: exception&.class&.name,
          workflow_id: data['workflow_id'],
          workload_id: data['workload_id']
        )
      end

      def handle_event(event)
        case event
        when ::Ci::Workloads::WorkloadFinishedEvent
          handle_workload_finished(event)
        when ::Ai::DuoWorkflows::WorkflowStartedEvent
          handle_workflow_started(event)
        when ::Ai::DuoWorkflows::WorkflowFinishedEvent
          handle_workflow_finished(event)
        when ::Ai::DuoWorkflows::WorkflowFailedEvent
          handle_workflow_failed(event)
        when ::Ai::DuoWorkflows::WorkflowApprovalRequiredEvent
          handle_workflow_approval_required(event)
        when ::Ai::DuoWorkflows::WorkflowInputRequiredEvent
          handle_workflow_input_required(event)
        end
      end

      private

      def handle_workload_finished(event)
        workload = ::Ci::Workloads::Workload.find_by_id(event.data[:workload_id])
        unless workload
          log_skip('Workload not found', workload_id: event.data[:workload_id])
          return
        end

        workflow = workload.latest_workflow
        unless workflow
          log_skip('No workflow associated with workload', workload_id: event.data[:workload_id])
          return
        end

        with_adapter(workflow) do |adapter, callback_context|
          # On CI a pause ends the job cleanly; claiming here would swallow the real answer later.
          if workflow.awaiting_user?
            log_skip('Workload ended while the session waits on the user', workflow_id: workflow.id)
            next
          end

          if event.data[:status] == 'finished' || workflow.finished?
            # Success normally rides the earlier WorkflowFinishedEvent; this is the last
            # event for the run, so it is the backstop when that delivery never landed.
            deliver_success(adapter, callback_context, workflow)
          else
            deliver_failure(adapter, callback_context, workflow, :flow_failed)
          end
        end
      end

      def handle_workflow_finished(event)
        with_workflow(event) do |workflow|
          with_adapter(workflow) do |adapter, callback_context|
            deliver_success(adapter, callback_context, workflow)
          end
        end
      end

      def handle_workflow_started(event)
        with_workflow(event) do |workflow|
          with_adapter(workflow) do |adapter, callback_context|
            handle_error do
              adapter.on_flow_started(callback_context: callback_context, workflow: workflow)
            end
          end
        end
      end

      def handle_workflow_failed(event)
        error = event.event_data[:status_event] == 'stop' ? :flow_stopped : :flow_failed

        with_workflow(event) do |workflow|
          with_adapter(workflow) do |adapter, callback_context|
            deliver_failure(adapter, callback_context, workflow, error)
          end
        end
      end

      def handle_workflow_approval_required(event)
        with_workflow(event) do |workflow|
          with_adapter(workflow) do |adapter, callback_context|
            handle_error do
              adapter.on_approval_required(callback_context: callback_context, workflow: workflow)
            end
          end
        end
      end

      def handle_workflow_input_required(event)
        with_workflow(event) do |workflow|
          with_adapter(workflow) do |adapter, callback_context|
            handle_error do
              adapter.on_input_required(callback_context: callback_context, workflow: workflow)
            end
          end
        end
      end

      def with_workflow(event)
        workflow_id = event.event_data[:workflow_id]

        workflow = ::Ai::DuoWorkflows::Workflow.find_by_id(workflow_id)
        unless workflow
          log_skip('Workflow not found', workflow_id: workflow_id)
          return
        end

        yield(workflow)
      end
    end
    # rubocop:enable Scalability/IdempotentWorker
  end
end
