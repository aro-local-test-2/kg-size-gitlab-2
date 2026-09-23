# frozen_string_literal: true

module WorkItems
  module Decisions
    class CreateService
      include Gitlab::Utils::StrongMemoize

      def initialize(work_item:, current_user:, params: {})
        @work_item = work_item
        @current_user = current_user
        @params = params
      end

      def execute
        error = validate_params
        return ServiceResponse.error(message: error) if error

        decision = create_decision!

        ServiceResponse.success(payload: { decision: decision })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: e.record.errors.full_messages.to_sentence)
      end

      private

      attr_reader :work_item, :current_user, :params

      def validate_params
        return _('Operation not allowed') unless allowed?
        return unless params[:resolution]

        return _('Options are not supported when creating a resolved decision') if options_params.any?

        _('Resolver must have access to the work item') unless resolver&.can?(:read_work_item, work_item)
      end

      # get_widget covers type registration, ai_workflows licensing, and the
      # decision_log feature flag
      def allowed?
        current_user.can?(:update_work_item, work_item) && work_item.get_widget(:decision_log).present?
      end

      def create_decision!
        ApplicationRecord.transaction do
          decision = work_item.decisions.create!(
            author: current_user,
            title: params[:title].presence,
            description: params[:description],
            discussion_id: params[:discussion_id],
            source_link: params[:source_link].presence,
            **resolution_attributes
          )

          options_params.each do |option_params|
            decision.options.create!(option_params.to_h.slice(:content, :description, :recommended))
          end

          create_resolution_option!(decision) if params[:resolution]

          decision
        end
      end

      def create_resolution_option!(decision)
        decision.options.create!(content: params.dig(:resolution, :decision), selected: true)
      end

      def options_params
        Array(params[:options])
      end

      # resolved_at == created_at marks a decision recorded as already
      # resolved, distinguishing it from one resolved after creation
      def resolution_attributes
        return {} unless params[:resolution]

        now = Time.current

        {
          created_at: now,
          resolved_at: now,
          resolved_by: resolver,
          resolution_rationale: params.dig(:resolution, :rationale)
        }
      end

      def resolver
        resolved_by_id = params.dig(:resolution, :resolved_by_id)

        resolved_by_id ? User.find_by_id(resolved_by_id) : current_user
      end
      strong_memoize_attr :resolver
    end
  end
end
