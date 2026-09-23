# frozen_string_literal: true

module Types
  module WorkItems
    module Widgets
      # rubocop:disable Graphql/AuthorizeTypes -- authorized via parent work item
      class AgentPlanType < BaseObject
        graphql_name 'WorkItemWidgetAgentPlan'
        description 'Represents an agent plan widget.'

        authorize_granular_token skip_reason: :parent_authorizes

        implements ::Types::WorkItems::WidgetInterface

        # Wraps the generated `content_html_resolver` (defined below by `markdown_field`) so it
        # also tracks the agent plan read. Prepending keeps `super` pointing at the generated
        # resolver.
        module ContentHtmlTracking
          def content_html_resolver
            super.tap { track_agent_plan_read(object) }
          end
        end
        prepend ContentHtmlTracking

        # `markdown_field` generates its own resolver and takes no feature-flag argument, so the
        # gate has to wrap it. Without this the rendered feedback would be readable while
        # `workplan_score` is disabled, even though the raw field is gated.
        module ReadinessScoreFeedbackHtmlGating
          def readiness_score_feedback_html_resolver
            return unless workplan_score_enabled?

            # `markdown_field` renders nil markdown as "", but the field contract promises null
            # when no feedback exists.
            super.presence
          end
        end
        prepend ReadinessScoreFeedbackHtmlGating

        def self.authorization_scopes
          super + [:ai_workflows]
        end

        # Fires a single `work_item_agent_plan_read` internal event per (request, work item).
        # Skips when:
        # - the agent plan has no content (don't count opens of work items that never had a plan)
        # - there is no authenticated user (TrackingService requires a User)
        # - the event was already tracked for this work item in the current request
        def self.track_agent_plan_read(widget, current_user)
          return unless widget&.content.present?
          return unless current_user.is_a?(User)

          work_item = widget.work_item
          guard_key = [:agent_plan_read_tracked, work_item.id]

          if ::Gitlab::SafeRequestStore.active?
            return if ::Gitlab::SafeRequestStore[guard_key]

            ::Gitlab::SafeRequestStore[guard_key] = true
          end

          ::Gitlab::WorkItems::Instrumentation::TrackingService.new(
            work_item: work_item,
            current_user: current_user,
            event: ::Gitlab::WorkItems::Instrumentation::EventActions::AGENT_PLAN_READ,
            extra_properties: {
              source: ::Gitlab::WorkItems::Instrumentation::TrackingService.current_source
            }
          ).execute
        end

        field :ai_planning_enabled, GraphQL::Types::Boolean,
          null: false,
          scopes: [:api, :read_api, :ai_workflows],
          description: 'Indicates whether AI planning is enabled for the work item.',
          method: :ai_planning_enabled_for_widget

        # The work item's agent plan content may be stored in object storage, so each call
        # to `content` or `content_html` can cost a network round-trip. We cap call count so
        # that, for example, listing many work items with their agent plans is impossible.
        field :content, GraphQL::Types::String,
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          description: 'Content of the agent plan. ' \
            'This field can only be resolved for one work item in any single request.' do
          extension ::Gitlab::Graphql::Limit::FieldCallCount, limit: 1
        end

        field :readiness_score, GraphQL::Types::Int,
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          experiment: { milestone: '19.3' },
          description: 'Readiness score of the agent plan (0-100). ' \
            'Null when the score is not yet available. ' \
            'Only available when the `workplan_score` feature flag is enabled.'

        # Reading this field triggers an object storage round-trip; cap to one work item per request.
        field :readiness_score_feedback, GraphQL::Types::String, # rubocop:disable GraphQL/ExtractType -- distinct scalars, not a logical sub-grouping
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          experiment: { milestone: '19.4' },
          description: 'Markdown feedback explaining the readiness score. ' \
            'Null when no feedback is available. ' \
            'Only available when the `workplan_score` feature flag is enabled. ' \
            'This field can only be resolved for one work item in any single request.' do
          extension ::Gitlab::Graphql::Limit::FieldCallCount, limit: 1
        end

        field :generation_status, ::Types::WorkItems::Widgets::AgentPlanGenerationStatusEnum,
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          experiment: { milestone: '19.4' },
          description: 'Status of the asynchronous workplan generation flow for the work item. ' \
            'Reflects the most recent `workplan/v1` Duo Agent Platform workflow, if any; creation ' \
            'of that workflow is currently gated by the `duo_workplan_async_flow` feature flag.'

        markdown_field :content_html,
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          extensions: [::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 }],
          description: 'GitLab Flavored Markdown rendering of `content`. ' \
            'This field can only be resolved for one work item in any single request.' do |widget|
          widget.work_item.agent_plan
        end

        markdown_field :readiness_score_feedback_html,
          null: true,
          scopes: [:api, :read_api, :ai_workflows],
          experiment: { milestone: '19.4' },
          extensions: [::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 }],
          description: 'GitLab Flavored Markdown rendering of `readiness_score_feedback`. ' \
            'Only available when the `workplan_score` feature flag is enabled. ' \
            'This field can only be resolved for one work item in any single request.' do |widget|
          widget.work_item.agent_plan
        end

        def content
          object.content.tap do |value|
            track_agent_plan_read(object) if value.present?
          end
        end

        def readiness_score
          return unless workplan_score_enabled?

          object.readiness_score
        end

        def readiness_score_feedback
          # Guard before touching the attribute: reading it triggers an object storage round-trip.
          return unless workplan_score_enabled?

          object.readiness_score_feedback
        end

        def generation_status
          BatchLoader::GraphQL.for(object.work_item.id).batch do |work_item_ids, loader|
            ::WorkItems::Widgets::AgentPlan.generation_statuses_for(work_item_ids).each do |work_item_id, status|
              loader.call(work_item_id, status)
            end
          end
        end

        private

        def workplan_score_enabled?
          Feature.enabled?(:workplan_score, object.work_item.namespace&.root_ancestor)
        end

        def track_agent_plan_read(widget)
          self.class.track_agent_plan_read(widget, current_user)
        end
      end
      # rubocop:enable Graphql/AuthorizeTypes
    end
  end
end
