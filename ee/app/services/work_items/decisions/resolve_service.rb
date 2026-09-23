# frozen_string_literal: true

module WorkItems
  module Decisions
    class ResolveService
      def initialize(decision:, current_user:, params: {})
        @decision = decision
        @work_item = decision.work_item
        @current_user = current_user
        @params = params
      end

      def execute
        error = validate_resolution
        return ServiceResponse.error(message: error) if error

        resolve_decision!

        ServiceResponse.success(payload: { decision: decision })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: e.record.errors.full_messages.to_sentence)
      end

      private

      attr_reader :decision, :work_item, :current_user, :params

      def validate_resolution
        return _('Operation not allowed') unless allowed?
        return _('Decision is already resolved') if decision.resolved_at
        return _('Note cannot resolve this decision') unless valid_resolving_note?
        return _('Selected options must belong to the decision') unless valid_selected_options?

        _('Resolution rationale is required when rejecting all options') if rationale_missing_for_rejection?
      end

      def valid_selected_options?
        selected_options.size == selected_option_ids.uniq.size
      end

      def rationale_missing_for_rejection?
        rejecting_all_options? && params[:resolution_rationale].blank?
      end

      # get_widget covers type registration, ai_workflows licensing, and the
      # decision_log feature flag
      def allowed?
        current_user.can?(:update_work_item, work_item) && work_item.get_widget(:decision_log).present?
      end

      def resolving_note
        params[:resolving_note]
      end

      def valid_resolving_note?
        return true if resolving_note.nil?

        current_user.can?(:read_note, resolving_note) && decision.resolvable_by_note?(resolving_note)
      end

      def resolve_decision!
        ApplicationRecord.transaction do
          select_options!

          decision.update!(
            resolved_at: Time.current,
            resolved_by: current_user,
            resolution_rationale: params[:resolution_rationale],
            resolving_note: resolving_note
          )
        end
      end

      def selected_option_ids
        Array(params[:selected_option_ids])
      end

      # A decision with no options at all has nothing to reject
      def rejecting_all_options?
        selected_options.empty? && decision.options.exists?
      end

      def selected_options
        @selected_options ||= decision.options.id_in(selected_option_ids)
      end

      def select_options!
        # update_all: the selected flag has no validations, and per-record
        # update! would revalidate unrelated attributes on legacy rows
        selected_options.update_all(selected: true, updated_at: Time.current)
      end
    end
  end
end
