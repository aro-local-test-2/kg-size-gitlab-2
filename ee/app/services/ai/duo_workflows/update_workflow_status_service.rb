# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class UpdateWorkflowStatusService
      include Concerns::WorkflowEventTracking

      TRACKABLE_EVENT_STATUSES = {
        'start' => 'agent_platform_session_started',
        'finish' => 'agent_platform_session_finished',
        'drop' => 'agent_platform_session_dropped',
        'stop' => 'agent_platform_session_stopped',
        'resume' => 'agent_platform_session_resumed'
      }.freeze

      # The only workflow_definition that should push work item subscription
      # updates today (see #notify_work_item_of_status_change). Unlike the
      # duo_workplan_async_flow feature flag, this identity check is permanent:
      # it keeps scoping the trigger to workplan even after the flag is
      # eventually removed.
      WORKPLAN_WORKFLOW_DEFINITION = 'workplan/v1'

      AUDIT_EVENT_CONFIG = {
        'start' => { name: 'duo_session_started', message: 'Started Duo session' },
        'finish' => { name: 'duo_session_finished', message: 'Completed Duo session' },
        'drop' => { name: 'duo_session_failed', message: 'Duo session failed' },
        'stop' => { name: 'duo_session_stopped', message: 'Duo session stopped' },
        'resume' => { name: 'duo_session_resumed', message: 'Resumed Duo session' }
      }.freeze

      def initialize(workflow:, status_event:, current_user:, summary: nil, reason: nil)
        @workflow = workflow
        @status_event = status_event
        @current_user = current_user
        @summary = summary
        @reason = reason
      end

      def execute
        return error_response("Can not update workflow", :unauthorized) unless authorized?

        handle_status_event
      end

      private

      def authorized?
        return true if @current_user.can?(:update_duo_workflow, @workflow)

        @status_event == 'stop' && @current_user.can?(:stop_duo_workflow, @workflow)
      end

      def cancel_associated_pipelines_async
        ::Ai::DuoWorkflows::CancelAssociatedPipelinesWorker.perform_async(@workflow.id, @current_user.id)
      end

      def handle_status_event
        workflow_events = ::Ai::DuoWorkflows::Workflow.state_machines[:status].events.map { |event| event.name.to_s }

        unless workflow_events.include?(@status_event)
          return error_response("Can not update workflow status, unsupported event: #{@status_event}")
        end

        if ::Ai::DuoWorkflows::Workflow.target_status_for_event(@status_event.to_sym) == @workflow.status_name
          return ServiceResponse.success(payload: { workflow: @workflow },
            message: "Workflow already in status #{@workflow.human_status_name}")
        end

        unless @workflow.status_events.include?(@status_event.to_sym)
          return error_response("Can not #{@status_event} workflow that has status #{@workflow.human_status_name}")
        end

        cancel_associated_pipelines_async if @status_event == 'stop'

        @workflow.summary = @summary if @summary
        @workflow.fire_status_event(@status_event)
        send_notifications

        track_agent_platform_session_event

        audit_event_for_status_change

        update_workflow_system_note(@workflow)
        notify_work_item_of_status_change

        # Presented, so the subscription publishes whatever row the GraphQL event
        # surface currently reads (legacy checkpoint or header).
        latest_checkpoint = @workflow.present.latest_checkpoint
        GraphqlTriggers.workflow_events_updated(latest_checkpoint) if latest_checkpoint

        unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?
          Ai::DuoWorkflows::SyncSessionArtifactWorker.perform_async(@workflow.id)
        end

        ServiceResponse.success(payload: { workflow: @workflow }, message: "Workflow status updated")
      end

      def track_agent_platform_session_event
        event_name = TRACKABLE_EVENT_STATUSES[@status_event]
        return unless event_name

        track_workflow_event(event_name, @workflow)
      end

      def send_notifications
        return unless @workflow.from_pipeline?

        sync_input_required_todo
        send_input_required_notification
      end

      def sync_input_required_todo
        case @status_event
        when 'require_input'
          ::TodoService.new.duo_workflow_input_required(@workflow)
        when 'resume', 'stop', 'drop'
          ::TodoService.new.resolve_duo_workflow_input_required_todo(@workflow)
        end
      end

      def send_input_required_notification
        return unless @workflow.user_id && @status_event == 'require_input'

        ::Notify.duo_workflow_input_required_email(@workflow.user_id, @workflow.id).deliver_later
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(e, workflow_id: @workflow.id)
      end

      # A work item's widgets (e.g. the Workplan generation status) can depend on
      # a linked workflow's status - including non-terminal ones, since the
      # widget shows a "generating" state as soon as a flow starts (or restarts
      # automatically after a discussion resolves, with no user action in the
      # open view to reflect it locally) - so push a live update on every
      # transition. The workflow's own event stream (below) doesn't reach open
      # work item views.
      #
      # Scoped to the workplan flow specifically: issue_id is already set on
      # other GA flows (e.g. Developer via assign/mention), and those don't need
      # this trigger. The feature flag check is only a rollout kill switch on
      # top of that permanent scoping - safe to drop once the flag is retired.
      # Extend WORKPLAN_WORKFLOW_DEFINITION (or the check below) once other
      # work-item-linked flows want this behavior too.
      def notify_work_item_of_status_change
        work_item = @workflow.work_item
        return unless work_item
        return unless @workflow.workflow_definition == WORKPLAN_WORKFLOW_DEFINITION
        return unless Feature.enabled?(:duo_workplan_async_flow, work_item.root_ancestor)

        GraphqlTriggers.work_item_updated(work_item)
      end

      def error_response(message, reason = :bad_request)
        ServiceResponse.error(message: message, reason: reason)
      end

      def audit_event_for_status_change
        config = AUDIT_EVENT_CONFIG[@status_event]
        return unless config

        audit_context = {
          name: config[:name],
          author: @current_user,
          scope: @workflow.project || @workflow.namespace,
          target: @workflow,
          target_details: "#{@workflow.workflow_definition} session #{@workflow.id}",
          message: config[:message]
        }

        begin
          ::Gitlab::Audit::Auditor.audit(audit_context)
        rescue StandardError => e
          Gitlab::ErrorTracking.track_exception(e, workflow_id: @workflow.id)
        end
      end

      def update_workflow_system_note(workflow)
        noteable = workflow.noteable
        return unless noteable
        return if workflow.suppress_agent_session_note?

        note_author = workflow.service_account

        case @status_event
        when 'finish'
          SystemNoteService.agent_session_completed(
            noteable,
            noteable.project,
            workflow.id,
            note_author
          )
        when 'drop', 'stop'
          note_reason = @reason || (@status_event == 'drop' ? 'dropped' : 'stopped')
          SystemNoteService.agent_session_failed(
            noteable,
            noteable.project,
            workflow.id,
            note_author,
            note_reason
          )
        end
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(
          e,
          workflow_id: workflow.id,
          noteable_type: noteable.class.name,
          noteable_id: noteable.id
        )
      end
    end
  end
end
