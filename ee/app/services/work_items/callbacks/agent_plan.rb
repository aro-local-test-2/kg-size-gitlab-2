# frozen_string_literal: true

module WorkItems
  module Callbacks
    class AgentPlan < Base
      ALLOWED_PARAMS = %i[content readiness_score readiness_score_feedback].freeze

      def before_create
        handle_agent_plan_change unless excluded_in_new_type?
      end

      def before_update
        if excluded_in_new_type?
          if work_item.agent_plan.present?
            work_item.agent_plan.destroy!
            @agent_plan_event = ::Gitlab::WorkItems::Instrumentation::EventActions::AGENT_PLAN_DESTROY
          end

          return
        end

        handle_agent_plan_change
      end

      def after_save_commit
        return unless @agent_plan_event

        ::Gitlab::WorkItems::Instrumentation::TrackingService.new(
          work_item: work_item,
          current_user: current_user,
          event: @agent_plan_event,
          extra_properties: {
            source: ::Gitlab::WorkItems::Instrumentation::TrackingService.current_source
          }
        ).execute
      end

      private

      def handle_agent_plan_change
        return unless agent_plan_change_requested?
        return unless has_permission?(:update_work_item)

        validate_readiness_score_flag!
        validate_readiness_score_feedback_flag!

        agent_plan = work_item.agent_plan || work_item.build_agent_plan

        apply_content(agent_plan) if params.key?(:content)
        agent_plan.readiness_score = params[:readiness_score] if readiness_score_param?
        agent_plan.readiness_score_feedback = params[:readiness_score_feedback] if readiness_score_feedback_param?
        agent_plan.ai_planning_enabled = true if enable_ai_planning?(agent_plan)

        raise_error(agent_plan.errors.full_messages.join(', ')) unless agent_plan.valid?
      end

      def apply_content(agent_plan)
        # Use content presence rather than row persistence: a score-only call can
        # persist a row with blank content, so persisted? is no longer a reliable
        # proxy for "the plan did not exist yet".
        had_content = agent_plan.content.present?
        content_changed = agent_plan.content != params[:content]
        agent_plan.content = params[:content]

        @agent_plan_event = if content_changed && !had_content
                              ::Gitlab::WorkItems::Instrumentation::EventActions::AGENT_PLAN_CREATE
                            elsif content_changed
                              ::Gitlab::WorkItems::Instrumentation::EventActions::AGENT_PLAN_UPDATE
                            end
      end

      def agent_plan_change_requested?
        params.key?(:content) || params.key?(:readiness_score) ||
          params.key?(:readiness_score_feedback) || ai_planning_requested?
      end

      def validate_readiness_score_flag!
        return if readiness_score_param?
        return unless params.key?(:readiness_score)

        raise_error(
          s_('WorkItems|The readiness_score field requires the workplan_score feature flag to be enabled.')
        )
      end

      def validate_readiness_score_feedback_flag!
        return if readiness_score_feedback_param?
        return unless params.key?(:readiness_score_feedback)

        raise_error(
          s_('WorkItems|The readiness_score_feedback field requires the workplan_score feature flag to be enabled.')
        )
      end

      # The widget is hidden while this flag is false, so anything worth rendering - plan content
      # or a readiness score - has to turn it on, whatever wrote it. Clearing the content does not
      # turn it off: the flag is a one-way opt-in.
      def enable_ai_planning?(agent_plan)
        agent_plan.content.present? || agent_plan.readiness_score.present? || ai_planning_requested?
      end

      def ai_planning_requested?
        params[:ai_planning_enabled] == true &&
          work_item.new_record? &&
          Feature.enabled?(:workplan, work_item.namespace&.root_ancestor)
      end

      # Gated by the same flag as the read path; a score set while disabled could not be read back.
      def readiness_score_param?
        params.key?(:readiness_score) &&
          Feature.enabled?(:workplan_score, work_item.namespace&.root_ancestor)
      end

      def readiness_score_feedback_param?
        params.key?(:readiness_score_feedback) &&
          Feature.enabled?(:workplan_score, work_item.namespace&.root_ancestor)
      end
    end
  end
end
