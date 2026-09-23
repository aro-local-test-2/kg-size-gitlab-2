# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Runs a failed or stopped workflow again as a new session with the same flow,
    # goal, noteable, source, privileges and trigger. The original record is left as
    # it is: reusing its id would let a workload from the old run that is still alive
    # write into the new one.
    class RestartWorkflowService
      LEASE_TTL = 15.seconds

      # Everything the flow execution path would otherwise default or leave unset.
      # `execution_mode` is deliberately absent: CreateWorkflowService only accepts it
      # from a sealed classification, and the new session runs in the background anyway.
      COPIED_ATTRIBUTES = %i[
        agent_privileges pre_approved_agent_privileges image web_search_enabled
        trigger_source trigger_flow_trigger_id trigger_flow_schedule_id trigger_event_type
        source_type source_link
      ].freeze

      def initialize(workflow:, current_user:, item_consumer:, service_account:)
        @workflow = workflow
        @current_user = current_user
        @item_consumer = item_consumer
        @service_account = service_account
      end

      def execute
        unless @current_user.can?(:restart_duo_workflow, @workflow)
          return ServiceResponse.error(message: 'Can not restart workflow', reason: :forbidden)
        end

        # Overlapping requests (a double click, a client retry) would each start a
        # session. The lease is kept on success so a repeat within the TTL is rejected too.
        lease_uuid = Gitlab::ExclusiveLease.new(lease_key, timeout: LEASE_TTL.to_i).try_obtain
        unless lease_uuid
          return ServiceResponse.error(message: 'Workflow is already being restarted', reason: :conflict)
        end

        result = ::Ai::Catalog::Flows::ExecuteService.new(
          project: @workflow.project,
          current_user: @current_user,
          params: flow_params
        ).execute

        if result.error?
          Gitlab::ExclusiveLease.cancel(lease_key, lease_uuid)
          return result
        end

        new_workflow = result.payload[:workflow]
        notify_messaging_adapter(new_workflow)
        audit_event(new_workflow)

        ServiceResponse.success(payload: { workflow: new_workflow, workload_id: result.payload[:workload_id] })
      end

      private

      def lease_key
        "duo_workflows_restart:#{@workflow.id}"
      end

      def flow_params
        {
          item_consumer: @item_consumer,
          service_account: @service_account,
          execute_workflow: true,
          event_type: @workflow.trigger_event_type || 'api_execution',
          user_prompt: @workflow.goal,
          issue_id: @workflow.issue&.iid,
          merge_request_id: @workflow.merge_request&.iid,
          messaging_callback_context: messaging_callback_context,
          workflow_attributes: @workflow.slice(*COPIED_ATTRIBUTES).symbolize_keys
        }
      end

      def messaging_callback_context
        context = @workflow.messaging_callback_context
        return if context.blank?

        context.except(*::Ai::Messaging::Adapters::Base::SESSION_STATE_KEYS)
      end

      # The mention and Slack pipelines fire this hook once the flow is enqueued so
      # the adapter can link the triggering note and post its progress marker.
      # Restart enqueues through ExecuteService directly, so fire it here.
      def notify_messaging_adapter(new_workflow)
        context = new_workflow.messaging_callback_context
        return if context.blank?

        adapter_class = ::Ai::Messaging::AdapterRegistry[context['adapter']]
        return unless adapter_class

        adapter_class.from_callback_context(context).on_flow_enqueued(callback_context: context, workflow: new_workflow)
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(e, workflow_id: new_workflow.id)
      end

      def audit_event(new_workflow)
        ::Gitlab::Audit::Auditor.audit(
          name: 'duo_session_restarted',
          author: @current_user,
          scope: @workflow.project,
          target: @workflow,
          target_details: "#{@workflow.workflow_definition} session #{@workflow.id} restarted as #{new_workflow.id}",
          message: 'Restarted Duo session'
        )
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(e, workflow_id: @workflow.id)
      end
    end
  end
end
