# frozen_string_literal: true

module WorkItems
  module Widgets
    class AgentPlan < Base
      def self.required_user_ability
        :update_work_item
      end

      # Status of the most recent workplan generation run for each given work item, in
      # a single query, so GraphQL can batch the lookup across a work item list.
      #
      # `:completed` describes the run, not the work item: the agent writes plan
      # content through a separate update (`WorkItems::Callbacks::AgentPlan`) that can
      # fail to land, and content that is present may come from an earlier run or a
      # manual edit. Callers asking whether a plan exists must read `content`.
      #
      # @param work_item_ids [Array<Integer>]
      # @return [Hash<Integer, Symbol>] one entry per requested ID
      def self.generation_statuses_for(work_item_ids)
        latest_workflows = ::Ai::DuoWorkflows::Workflow
          .with_workflow_definition(::Ai::DuoWorkflows::GenerateWorkplanService::WORKFLOW_DEFINITION_REFERENCE)
          .for_issue(work_item_ids)
          .latest_per_issue
          .index_by(&:issue_id)

        work_item_ids.index_with do |work_item_id|
          latest_workflows[work_item_id]&.progress_status || :not_started
        end
      end

      delegate :content, :content_html, :readiness_score, :readiness_score_feedback, :readiness_score_feedback_html,
        to: :agent_plan_record, allow_nil: true

      def ai_planning_enabled_for_widget
        agent_plan_record&.ai_planning_enabled || false
      end

      private

      def agent_plan_record
        work_item.agent_plan
      end
    end
  end
end
