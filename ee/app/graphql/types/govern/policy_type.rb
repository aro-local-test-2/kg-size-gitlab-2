# frozen_string_literal: true

module Types
  module Govern
    # rubocop:disable Graphql/AuthorizeTypes -- Policies are Gitlab::PolicyStore::Policy value
    # objects with no policy of their own; the governPolicies field authorizes against the
    # organization, matching the REST endpoint.
    class PolicyType < BaseObject
      graphql_name 'GovernPolicy'
      description 'Policy stored in the policy store.'

      authorize_granular_token permissions: :read_govern_policy,
        boundary: :instance,
        boundary_type: :instance

      field :id, # rubocop: disable GraphQL/FieldMethod -- method: still resolves via BaseObject#id and its to_global_id; explicit override required
        GraphQL::Types::Int,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'ID of the policy.'

      field :organization_id, GraphQL::Types::Int,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'ID of the organization the policy belongs to.'

      field :namespace_id, GraphQL::Types::Int,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'ID of the namespace the policy is scoped to. Null for organization-wide policies.'

      field :name, GraphQL::Types::String,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Name of the policy.'

      field :description, GraphQL::Types::String,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Description of the policy.'

      field :version, GraphQL::Types::Int,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Version of the policy.'

      field :trigger_type, GraphQL::Types::String,
        null: false,
        experiment: { milestone: '19.4' },
        description: 'Trigger the policy responds to.'

      # The policy content is free-form and owned by the policy store experiment, so the
      # rules, actions, and scope have no fixed shape to type yet. They stay JSON for the
      # experiment stage, mirroring API::Entities::Govern::Policy.
      field :rules, [GraphQL::Types::JSON],
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Rules of the policy.'

      field :policy_rego, GraphQL::Types::String,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Rego program merged from the compiled rules. ' \
          'Null when the rules cannot be merged.'

      field :actions, [GraphQL::Types::JSON],
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Actions of the policy.'

      # rubocop:disable GraphQL/ExtractType -- mirrors the flat API::Entities::Govern::Policy shape;
      # policyRego/policyScope stay flat fields, like the scope pair below.
      field :policy_scope, GraphQL::Types::JSON, # rubocop:disable Graphql/JSONType -- free-form experiment content (see comment)
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Scope of the policy.'
      # rubocop:enable GraphQL/ExtractType

      # rubocop:disable GraphQL/ExtractType -- mirrors the flat API::Entities::Govern::Policy shape;
      # extracting a scope type adds indirection the experiment stage does not need.
      field :scope_rego, GraphQL::Types::String,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Rego expression scoping the policy. Mutually exclusive with policyScope.'

      field :scope_dimensions, [GraphQL::Types::String],
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Dotted context paths scopeRego reads to decide whether the policy applies. ' \
          'Null when scopeRego was authored directly instead of compiled from policyScope.'
      # rubocop:enable GraphQL/ExtractType

      field :mode, GraphQL::Types::String,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Enforcement mode of the policy.'

      field :lifecycle_state, GraphQL::Types::String,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Lifecycle state of the policy.'

      field :created_at, Types::TimeType,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Timestamp of when the policy was created.'

      field :updated_at, Types::TimeType,
        null: true,
        experiment: { milestone: '19.4' },
        description: 'Timestamp of when the policy was last updated.'

      # BaseObject#id builds a GlobalID, which the frozen gem value object lacks.
      def id
        object.id
      end

      # Mirrors API::Entities::Govern::Policy: the program is derived from the rules,
      # and a policy whose rules cannot merge must not fail the whole read.
      def policy_rego
        ::Gitlab::PolicyStore::RuleProgramMerger.new(object.rules).merge
      rescue ::Gitlab::PolicyStore::Error => error
        ::Gitlab::ErrorTracking.track_exception(error, policy_id: object.id)

        nil
      end
    end
    # rubocop:enable Graphql/AuthorizeTypes
  end
end
