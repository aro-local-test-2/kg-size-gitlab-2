# frozen_string_literal: true

module Ai
  class RunFlowScheduleWorker
    include ApplicationWorker

    data_consistency :sticky

    sidekiq_options retry: true
    feature_category :code_suggestions
    deduplicate :until_executed, including_scheduled: true
    idempotent!

    concurrency_limit -> { 100 }

    UNEXPECTED_ERROR_MESSAGE = 'Flow execution failed unexpectedly'

    SKIPPED_RUN_REASONS = %i[
      flow_disabled_by_feature_flag
      non_human_trigger_not_permitted
      usage_quota_exceeded
    ].freeze

    def perform(schedule_id, options = {})
      schedule = ::Ai::FlowSchedule.find_by_id(schedule_id)

      error = validation_error(schedule, options)
      return log_error(schedule_id, error) if error

      advance_next_run_at!(schedule) if options['scheduling']

      execute_flow(schedule)
    end

    private

    def validation_error(schedule, options)
      return 'Schedule not found' unless schedule

      return 'Schedule is not active, skipping scheduled run' unless schedule.active?
      return 'Flow trigger not found for schedule' unless schedule.flow_trigger

      project = schedule.project
      return 'Project not found for schedule' unless project
      return 'Project or ancestors are archived' if project.self_or_ancestors_archived?

      if project.deletion_in_progress_or_scheduled_in_hierarchy_chain?
        return 'Project, namespace or ancestors are scheduled for deletion'
      end

      return 'Schedule next run time is in future' if options['scheduling'] && schedule.next_run_at&.future?

      nil
    end

    def advance_next_run_at!(schedule)
      # Advance next_run_at BEFORE execution to prevent duplicate runs
      # if the worker is retried or the cron fires again while executing.
      schedule.schedule_next_run!
    end

    def execute_flow(schedule)
      flow_trigger = schedule.flow_trigger
      project = schedule.project

      # Paused, not failed: skip quietly so pausing doesn't burn through
      # MAX_CONSECUTIVE_FAILURES and auto-deactivate the schedule.
      return log_error(schedule.id, 'Flow trigger is not active, skipping scheduled run') unless flow_trigger.active?

      response = ::Ai::FlowTriggers::RunService.new(
        project: project,
        flow_trigger: flow_trigger,
        trigger_source: :scheduled,
        flow_schedule: schedule
      ).execute({ event: :scheduled, input: schedule.description })

      # RunService returns [response, workflow] or just response
      response, _workflow = response if response.is_a?(Array)

      if response&.success?
        schedule.record_success!
      elsif skipped_run?(response)
        log_error(schedule.id, "#{join_message(response.message)}, skipping scheduled run")
      else
        handle_failure(schedule, response&.message || 'Unknown execution error')
      end
    rescue StandardError => e
      track_error(schedule, e)
      handle_failure(schedule, UNEXPECTED_ERROR_MESSAGE)
    end

    def skipped_run?(response)
      response.present? && SKIPPED_RUN_REASONS.include?(response.reason)
    end

    def join_message(message)
      message.is_a?(String) ? message : Array(message).join(', ')
    end

    def handle_failure(schedule, error_message)
      error_message = join_message(error_message)
      schedule.record_failure!(error_message)

      if schedule.deactivated_by_failures?
        log_error(schedule.id,
          "Schedule deactivated after #{Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES} consecutive failures, " \
            "error_message: #{error_message}")
        NotificationService.new.ai_flow_schedule_deactivated(schedule)
      else
        log_error(schedule.id, error_message)
        NotificationService.new.ai_flow_schedule_failed(schedule)
      end
    end

    def log_error(schedule_id, message)
      Gitlab::AppLogger.error(
        message: 'Failed to execute AI flow schedule',
        schedule_id: schedule_id,
        error_message: message
      )
    end

    def track_error(schedule, error)
      Gitlab::ErrorTracking.track_exception(
        error,
        schedule_id: schedule.id,
        flow_trigger_id: schedule.ai_flow_trigger_id
      )
    end
  end
end
