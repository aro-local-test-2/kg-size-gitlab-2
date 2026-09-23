# frozen_string_literal: true

module Emails
  module Ai
    module FlowSchedules
      def ai_flow_schedule_deactivated_email(schedule, recipient)
        raise ArgumentError, "recipient must be a single User, got #{recipient.class}" if recipient.is_a?(Array)

        @schedule = schedule
        @project = schedule.project
        @recipient = recipient

        email_with_layout(
          to: recipient.notification_email_for(@project.group),
          subject: subject(
            format(s_('AiFlowSchedules|Flow schedule deactivated: %{description}'),
              description: schedule.description)
          )
        )
      end

      def ai_flow_schedule_failure_email(schedule, recipient)
        raise ArgumentError, "recipient must be a single User, got #{recipient.class}" if recipient.is_a?(Array)

        @schedule = schedule
        @project = schedule.project
        @recipient = recipient

        email_with_layout(
          to: recipient.notification_email_for(@project.group),
          subject: subject(
            format(s_('AiFlowSchedules|Flow schedule failed: %{description}'),
              description: schedule.description)
          )
        )
      end
    end
  end
end
