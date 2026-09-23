# frozen_string_literal: true

module Types
  module Govern
    # rubocop:disable Graphql/AuthorizeTypes -- Static catalog container; the parent group or organization field gates visibility.
    class PolicyStoreType < BaseObject
      graphql_name 'PolicyStore'
      description 'Catalogs available when creating a policy in the policy store.'

      authorize_granular_token skip_reason: :parent_authorizes

      field :actions, [::Types::Govern::PolicyStoreActionType],
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Actions available when creating a policy in the policy store.'

      field :policies, [::Types::Govern::PolicyType],
        null: true,
        authorize: :read_govern_policy,
        resolver: ::Resolvers::Govern::PoliciesResolver,
        experiment: { milestone: '19.4' },
        description: 'Policies stored in the policy store for the organization or group. ' \
          'Returns `null` when the current user cannot read the policies of the container.'

      field :policy_evaluations, ::Types::Govern::PolicyEvaluationType.connection_type,
        null: true,
        authorize: :read_govern_policy,
        resolver: ::Resolvers::Govern::PolicyEvaluationsResolver,
        experiment: { milestone: '19.4' },
        description: 'Recorded evaluations of the policies stored in the policy store ' \
          'for the organization, newest first. Returns `null` for groups and when the ' \
          'current user cannot read the policies of the organization.'

      field :rules, [::Types::Govern::PolicyStoreRuleType],
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Rule kinds available when creating a policy in the policy store.'

      field :triggers, [::Types::Govern::PolicyStoreTriggerType],
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Triggers available when creating a policy in the policy store.'

      def actions
        ::Gitlab::PolicyStore::Actions::ALL
      end

      def rules
        ::Gitlab::PolicyStore::Rules::ALL
      end

      def triggers
        ::Gitlab::PolicyStore::Triggers::ALL
      end
    end
    # rubocop:enable Graphql/AuthorizeTypes
  end
end
