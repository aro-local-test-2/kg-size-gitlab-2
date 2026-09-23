# frozen_string_literal: true

module Ai
  module Messaging
    # Runs one turn of a server-side flow for a messaging surface and delivers
    # its answer.
    #
    # Unlike most workers this one blocks for the whole turn: it holds the HTTP
    # connection to Workhorse, which holds the gRPC stream to the Duo Workflow
    # Service. That is the job. It exists as a worker of its own, rather than
    # inline in the surface's event worker, so the run is not bounded by that
    # worker's own retry semantics and so its fleet concurrency can be capped.
    #
    # Delivery is inline rather than event-driven because a turn ends at
    # :input_required, which fires no event: unlike a CI-executed flow there is
    # no WorkflowFinishedEvent or WorkloadFinishedEvent for CallbackWorker to
    # ride. Live progress still flows through ProgressDeliveryWorker, driven by
    # the checkpoints the flow writes as it runs.
    #
    # rubocop:disable Scalability/IdempotentWorker -- a turn is not idempotent: re-running resumes the flow from its last checkpoint
    class ServerSideTurnWorker
      include ApplicationWorker
      include ::Ai::Messaging::ResultDelivery

      feature_category :duo_agent_platform
      data_consistency :sticky
      urgency :low
      worker_has_external_dependencies!
      # Default delay rather than a longer one: someone is waiting in the surface
      # for this turn, and consecutive deferrals already back off 2x up to 30
      # minutes, so a long base delay compounds into abandoning the turn.
      defer_on_database_health_signal :gitlab_main, [:duo_workflows_workflows]

      # Each job pins a Sidekiq thread for a whole turn, so the usual assumption
      # that jobs are short does not hold. Provisional until real traffic informs
      # a better number: sidekiq_concurrency_limit_queue_jobs, labelled by worker,
      # reports how many turns are waiting on this limit.
      concurrency_limit -> { 50 }

      # A turn interrupted by a deploy is re-pushed by Sidekiq and resumes from
      # the flow's last checkpoint, so a duplicate job is wasteful rather than
      # harmful; Workhorse rejects the second one while the first still holds the
      # workflow lock.
      deduplicate :until_executed

      # goal is the message this turn is answering. It is absent for the first
      # turn, whose message is the workflow's own goal, and present for every
      # turn after it: a session's goal stays the message that opened it, the
      # way it does for a chat session driven from a browser.
      def perform(workflow_id, approval = nil, goal = nil)
        workflow = ::Ai::DuoWorkflows::Workflow.find_by_id(workflow_id)
        return unless workflow

        result = ::Ai::DuoWorkflows::ServerSideExecutionService.new(
          workflow: workflow, goal: goal.presence || workflow.goal, approval: approval
        ).execute

        # A run parked on an approval has produced no answer yet, and the surface
        # cannot answer it until the approval work lands. Delivering the last
        # message here would also claim the delivery and so suppress the real
        # answer once the run resumes and finishes.
        return if result.success? && workflow.awaiting_approval?

        with_adapter(workflow) do |adapter, callback_context|
          next deliver_success(adapter, callback_context, workflow) if result.success?

          deliver_failure(adapter, callback_context, workflow, result.reason || :flow_failed)
        end
      end
    end
    # rubocop:enable Scalability/IdempotentWorker
  end
end
