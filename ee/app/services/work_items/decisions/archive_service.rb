# frozen_string_literal: true

module WorkItems
  module Decisions
    class ArchiveService
      def initialize(decision:, current_user:)
        @decision = decision
        @work_item = decision.work_item
        @current_user = current_user
      end

      def execute
        error = validate_archival
        return ServiceResponse.error(message: error) if error

        now = Time.current
        # update_columns: archived_at has no validations, and update! would
        # re-run unrelated ones on a record the archive never changes
        decision.update_columns(archived_at: now, updated_at: now)

        ServiceResponse.success(payload: { decision: decision })
      end

      private

      attr_reader :decision, :work_item, :current_user

      def validate_archival
        return _('Operation not allowed') unless allowed?
        return _('Decision is already archived') if decision.archived_at?

        _('Only resolved decisions can be archived') unless decision.resolved_at?
      end

      # get_widget covers type registration, ai_workflows licensing, and the
      # decision_log feature flag
      def allowed?
        current_user.can?(:update_work_item, work_item) && work_item.get_widget(:decision_log).present?
      end
    end
  end
end
