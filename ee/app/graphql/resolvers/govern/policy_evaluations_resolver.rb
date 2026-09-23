# frozen_string_literal: true

module Resolvers
  module Govern
    class PolicyEvaluationsResolver < BaseResolver
      include LooksAhead

      type ::Types::Govern::PolicyEvaluationType.connection_type, null: true

      argument :policy_id, GraphQL::Types::Int,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the evaluations of the policy with the given ID.'

      argument :mode, ::Types::Govern::PolicyEvaluationModeEnum,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the evaluations that ran in the given enforcement mode.'

      argument :verdict, ::Types::Govern::PolicyEvaluationVerdictEnum,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the evaluations that produced the given verdict.'

      argument :evaluated_after, Types::TimeType,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the evaluations that ran at or after the given timestamp.'

      argument :evaluated_before, Types::TimeType,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the evaluations that ran at or before the given timestamp.'

      # PolicyStoreType serves Group and Organization parents, but only
      # organizations hold evaluations today, mirroring the policies field.
      def resolve_with_lookahead(**args)
        return unless object.is_a?(::Organizations::Organization)

        apply_lookahead(
          ::Govern::PolicyEvaluationsFinder.new(organization: object, params: args).execute
        )
      end

      private

      def preloads
        { violations: [:violations] }
      end
    end
  end
end
