# frozen_string_literal: true

module Types
  module Govern
    # rubocop:disable Graphql/AuthorizeTypes -- Evaluations have no policy class of their
    # own; the policyEvaluations field authorizes against the organization, matching the
    # policies field.
    class PolicyEvaluationType < BaseObject
      graphql_name 'GovernPolicyEvaluation'
      description 'Recorded evaluation of a policy stored in the policy store.'

      # The Policy Store's stat tiles need totals, not pages: without a count on
      # the connection they would have to fetch every row they claim to count.
      connection_type_class ::Types::CountableConnectionType

      authorize_granular_token permissions: :read_govern_policy,
        boundary: :instance,
        boundary_type: :instance

      field :id, ::Types::GlobalIDType[::Govern::PolicyEvaluation],
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Global ID of the evaluation.'

      # Integer to match GovernPolicy.id, which stays an integer while the
      # policy store surfaces mirror the REST API.
      field :policy_id, GraphQL::Types::Int,
        null: false,
        method: :govern_policy_id,
        experiment: { milestone: '19.4' },
        description: 'ID of the policy that was evaluated.'

      field :trigger_type, ::Types::Govern::PolicyEvaluationTriggerTypeEnum,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Trigger that started the evaluation.'

      field :mode, ::Types::Govern::PolicyEvaluationModeEnum,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Enforcement mode of the policy at the time of the evaluation.'

      field :verdict, ::Types::Govern::PolicyEvaluationVerdictEnum,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Verdict the evaluation produced.'

      # rubocop:disable GraphQL/ExtractType -- policyVersion snapshots the version at evaluation
      # time; nesting it with policyId under a policy field would misrepresent it as live policy data.
      field :policy_version, GraphQL::Types::Int,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Version of the policy at the time of the evaluation.'
      # rubocop:enable GraphQL/ExtractType

      field :evaluated_at, Types::TimeType,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Timestamp of when the policy was evaluated.'

      field :project_id, GraphQL::Types::Int,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'ID of the project the evaluation ran for. ' \
          'Null when the evaluation was not scoped to a project.'

      field :environment_id, GraphQL::Types::Int,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'ID of the environment the evaluation ran for. ' \
          'Null when the evaluation was not scoped to an environment.'

      field :user_id, GraphQL::Types::Int,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'ID of the user whose operation triggered the evaluation. ' \
          'Null when the evaluation was not triggered by a user.'

      field :violations, [::Types::Govern::PolicyViolationType],
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Violations the evaluation produced.'
    end
    # rubocop:enable Graphql/AuthorizeTypes
  end
end
