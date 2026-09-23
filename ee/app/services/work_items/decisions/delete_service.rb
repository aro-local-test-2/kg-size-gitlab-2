# frozen_string_literal: true

module WorkItems
  module Decisions
    class DeleteService
      def initialize(decision:, current_user:)
        @decision = decision
        @work_item = decision.work_item
        @current_user = current_user
      end

      def execute
        error = validate_deletion
        return ServiceResponse.error(message: error) if error

        decision.destroy!

        ServiceResponse.success(payload: { decision: decision })
      end

      private

      attr_reader :decision, :work_item, :current_user

      # Resolved decisions are part of the audit trail: they can only be
      # archived, or cascade-deleted with the work item
      def validate_deletion
        return _('Operation not allowed') unless allowed?
        return _('Archived decisions cannot be deleted') if decision.archived_at?

        _('Resolved decisions cannot be deleted') if decision.resolved_at?
      end

      # get_widget covers type registration, ai_workflows licensing, and the
      # decision_log feature flag
      def allowed?
        current_user.can?(:update_work_item, work_item) && work_item.get_widget(:decision_log).present?
      end
    end
  end
end
