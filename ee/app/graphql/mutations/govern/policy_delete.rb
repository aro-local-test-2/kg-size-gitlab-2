# frozen_string_literal: true

module Mutations
  module Govern
    class PolicyDelete < ::Mutations::BaseMutation
      graphql_name 'GovernPolicyDelete'
      description 'Deletes a policy from the policy store for an organization.'

      include PolicyStoreMutation

      authorize :delete_govern_policy
      authorize_granular_token permissions: :delete_govern_policy,
        boundary: :instance,
        boundary_type: :instance

      argument :organization_id, ::Types::GlobalIDType[::Organizations::Organization],
        required: true,
        description: 'Global ID of the organization the policy belongs to.'

      # Policy store policies are value objects with plain integer ids, not
      # ActiveRecord models with a GlobalID - see Types::Govern::PolicyType#id.
      argument :id, GraphQL::Types::Int,
        required: true,
        description: 'ID of the policy to delete.'

      def resolve(organization_id:, id:)
        organization = authorized_find!(organization_id: organization_id)

        response = ::Security::SecurityOrchestrationPolicies::PolicyStore::DestroyService
          .new(container: organization, current_user: current_user, policy_id: id)
          .execute

        if response.error?
          # The experiment gate acts as if the API does not exist, while a missing
          # policy surfaces as a user-facing error on the payload. :forbidden is
          # intentionally unmapped: authorized_find! already checks the same ability.
          raise_resource_not_available_error! if response.reason == :experiment_not_active

          track_unmapped_reason!(response) unless response.reason == :not_found

          return { errors: [response.message] }
        end

        { errors: [] }
      end
    end
  end
end
