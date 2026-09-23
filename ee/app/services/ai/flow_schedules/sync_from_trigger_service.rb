# frozen_string_literal: true

module Ai
  module FlowSchedules
    # Synchronizes Ai::FlowSchedule records from a flow trigger's filter JSON.
    #
    # When a flow trigger includes event_type :scheduled (9) and has schedule
    # config in filter["scheduled"], this service creates or updates the
    # corresponding FlowSchedule. When the scheduled event type is removed,
    # it destroys any existing schedules.
    #
    # Called after every trigger write path: FlowTriggers::CreateService and
    # UpdateService, and Catalog::ItemConsumers::CreateService (which creates
    # triggers via nested attributes). Self-gates on the ai_flow_schedules
    # feature flag and tolerates a nil trigger so callers need no guards.
    class SyncFromTriggerService
      include ::Gitlab::ExclusiveLeaseHelpers

      SCHEDULED_EVENT_TYPE = ::Ai::FlowTrigger::EVENT_TYPES[:scheduled]
      SCHEDULE_FILTER_KEY = 'scheduled'
      LOCK_TTL = 10.seconds
      LOCK_RETRIES = 2
      LOCK_SLEEP = 0.1.seconds

      def initialize(trigger:)
        @trigger = trigger
      end

      def execute
        return ServiceResponse.success unless @trigger
        return ServiceResponse.success unless Feature.enabled?(:ai_flow_schedules, @trigger.project)

        # Serializes concurrent syncs for the same trigger,
        # preventing two near-simultaneous writes from both seeing
        # no existing schedule and each creating a duplicate.
        in_lock(lock_key, ttl: LOCK_TTL, retries: LOCK_RETRIES, sleep_sec: LOCK_SLEEP) do
          if has_scheduled_event_type? && schedule_config.present?
            upsert_schedule
          elsif !has_scheduled_event_type?
            remove_schedules
          else
            ServiceResponse.success
          end
        end
      rescue Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError
        ServiceResponse.error(message: 'Could not acquire lock to sync flow schedule')
      end

      private

      def lock_key
        "ai_flow_schedules:sync_from_trigger:#{@trigger.id}"
      end

      def has_scheduled_event_type?
        @trigger.event_types&.include?(SCHEDULED_EVENT_TYPE)
      end

      def schedule_config
        @trigger.filter&.dig(SCHEDULE_FILTER_KEY)
      end

      def upsert_schedule
        conversion = CronConverterService.new(schedule_config).execute
        return conversion if conversion.error?

        cron = conversion.payload[:cron]
        cron_timezone = conversion.payload[:cron_timezone]

        schedule = @trigger.flow_schedules.first

        if schedule
          if schedule.update(cron: cron, cron_timezone: cron_timezone)
            ServiceResponse.success(payload: { flow_schedule: schedule })
          else
            ServiceResponse.error(message: schedule.errors.full_messages.to_sentence)
          end
        else
          schedule = @trigger.flow_schedules.build(
            project: @trigger.project,
            cron: cron,
            cron_timezone: cron_timezone,
            description: @trigger.description,
            active: true
          )

          if schedule.save
            ServiceResponse.success(payload: { flow_schedule: schedule })
          else
            ServiceResponse.error(message: schedule.errors.full_messages.to_sentence)
          end
        end
      end

      def remove_schedules
        @trigger.flow_schedules.destroy_all # rubocop:disable Cop/DestroyAll -- small bounded set (plan-limited)
        ServiceResponse.success
      end
    end
  end
end
