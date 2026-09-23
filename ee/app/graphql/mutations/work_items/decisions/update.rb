# frozen_string_literal: true

module Mutations
  module WorkItems
    module Decisions
      class Update < BaseMutation
        graphql_name 'WorkItemDecisionUpdate'

        description 'Updates a decision in the decision log of a work item.'

        authorize :update_work_item
        authorize_granular_token permissions: :update_work_item,
          boundaries: [
            { boundary_argument: :id, boundary: :resource_parent, boundary_type: :project },
            { boundary_argument: :id, boundary: :resource_parent, boundary_type: :group }
          ]

        argument :id,
          ::Types::GlobalIDType[::WorkItems::Decision],
          required: true,
          description: 'Global ID of the decision.'

        argument :title, GraphQL::Types::String,
          required: false,
          validates: { allow_blank: false },
          description: 'Question being decided.'

        argument :description, GraphQL::Types::String,
          required: false,
          validates: { allow_blank: false },
          description: 'Context of the decision.'

        argument :resolution_rationale, GraphQL::Types::String,
          required: false,
          validates: { allow_blank: false },
          description: 'Reasoning for the resolution. Can only be updated on resolved decisions.'

        argument :resolved_by_id, ::Types::GlobalIDType[::User],
          required: false,
          validates: { allow_blank: false },
          prepare: ->(global_id, _ctx) { global_id.model_id },
          description: 'Global ID of the user who resolved the decision. Can only be updated on resolved decisions.'

        argument :resolving_note_id, ::Types::GlobalIDType[::Note],
          required: false,
          validates: { allow_blank: false },
          prepare: ->(global_id, _ctx) { global_id.model_id },
          description: 'Global ID of the comment that resolved the decision. Can only be updated on resolved decisions.'

        argument :discussion_id, ::Types::GlobalIDType[::Discussion],
          required: false,
          validates: { allow_blank: false },
          # The model stores and validates the bare 40-char discussion SHA
          prepare: ->(global_id, _ctx) { global_id.model_id },
          description: 'Global ID of the originating discussion thread.'

        argument :source_link, GraphQL::Types::String,
          required: false,
          validates: { allow_blank: false },
          description: 'URL of the comment, discussion, or external resource that prompted the decision.'

        validates at_least_one_of: [
          :title, :description, :resolution_rationale, :discussion_id, :source_link, :resolved_by_id, :resolving_note_id
        ]

        field :decision, ::Types::WorkItems::DecisionType,
          null: true,
          description: 'Decision after mutation.'

        def resolve(id:, **args)
          decision = ::Gitlab::Graphql::Lazy.force(GitlabSchema.find_by_gid(id))
          raise_resource_not_available_error! unless decision

          authorize!(decision.work_item)

          # get_widget covers type registration, ai_workflows licensing, and
          # the decision_log feature flag
          raise_resource_not_available_error! unless decision.work_item.get_widget(:decision_log)

          response = ::WorkItems::Decisions::UpdateService.new(
            decision: decision,
            current_user: current_user,
            params: args
          ).execute

          {
            decision: response.success? ? response.payload[:decision] : decision.reset,
            errors: response.errors
          }
        end
      end
    end
  end
end
