# frozen_string_literal: true

module WorkItems
  module Decisions
    class UpdateService
      include Gitlab::Utils::StrongMemoize

      UPDATABLE_ATTRIBUTES = %i[
        title description resolution_rationale discussion_id source_link resolved_by_id resolving_note_id
      ].freeze
      RESOLUTION_ATTRIBUTES = %i[resolution_rationale resolved_by_id resolving_note_id].freeze

      def initialize(decision:, current_user:, params: {})
        @decision = decision
        @work_item = decision.work_item
        @current_user = current_user
        @params = params
      end

      def execute
        error = validate_params
        return ServiceResponse.error(message: error) if error

        decision.update!(update_attributes)

        ServiceResponse.success(payload: { decision: decision })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: e.record.errors.full_messages.to_sentence)
      end

      private

      attr_reader :decision, :work_item, :current_user, :params

      def validate_params
        return _('Operation not allowed') unless allowed?
        return _('Archived decisions cannot be updated') if decision.archived_at?
        return _('No attributes to update') if update_attributes.empty?
        return blank_attributes_error if blank_attributes.any?
        return resolution_attributes_error if resolution_attributes.any? && !decision.resolved_at?
        return _('Resolver must have access to the work item') if resolver_provided? && !valid_resolver?

        _('Note cannot resolve this decision') if resolving_note_provided? && !valid_resolving_note?
      end

      # get_widget covers type registration, ai_workflows licensing, and the
      # decision_log feature flag
      def allowed?
        current_user.can?(:update_work_item, work_item) && work_item.get_widget(:decision_log).present?
      end

      def update_attributes
        params.slice(*UPDATABLE_ATTRIBUTES)
      end

      # A provided attribute may be replaced but never cleared; omitted
      # attributes are left untouched
      def blank_attributes
        update_attributes.select { |_, value| value.blank? }.keys
      end

      def resolution_attributes
        update_attributes.slice(*RESOLUTION_ATTRIBUTES).keys
      end

      def blank_attributes_error
        format(_("%{attributes} can't be blank"), attributes: human_attribute_names(blank_attributes))
      end

      def resolution_attributes_error
        format(
          _('%{attributes} can only be updated on resolved decisions'),
          attributes: human_attribute_names(resolution_attributes)
        )
      end

      def human_attribute_names(attributes)
        attributes.map { |attribute| decision.class.human_attribute_name(attribute) }.to_sentence
      end

      def resolver_provided?
        update_attributes.key?(:resolved_by_id)
      end

      def valid_resolver?
        resolver&.can?(:read_work_item, work_item)
      end

      def resolver
        User.find_by_id(update_attributes[:resolved_by_id])
      end
      strong_memoize_attr :resolver

      def resolving_note_provided?
        update_attributes.key?(:resolving_note_id)
      end

      def valid_resolving_note?
        note = Note.find_by_id(update_attributes[:resolving_note_id])

        note.present? && current_user.can?(:read_note, note) && decision.resolvable_by_note?(note)
      end
    end
  end
end
