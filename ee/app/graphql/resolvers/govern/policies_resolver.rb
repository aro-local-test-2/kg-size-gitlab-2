# frozen_string_literal: true

module Resolvers
  module Govern
    class PoliciesResolver < BaseResolver
      UnmappedReasonError = Class.new(StandardError)

      UNMAPPED_REASON_MESSAGE = 'Could not complete the policy store request'

      type [::Types::Govern::PolicyType], null: true

      argument :trigger_type, GraphQL::Types::String,
        required: false,
        experiment: { milestone: '19.4' },
        description: 'Return only the policies that respond to this trigger. ' \
          'Valid values are the ids in the policy store triggers catalog.'

      # Int, not GlobalID: GovernPolicy.id is a plain integer owned by the policy
      # store, mirroring the REST policy_id parameter.
      argument :ids, [GraphQL::Types::Int],
        required: false,
        validates: { length: { maximum: Types::BaseArgument::MAX_ARRAY_SIZE } },
        experiment: { milestone: '19.4' },
        description: 'Return only the policies with these IDs. Unknown IDs are ignored; ' \
          'an empty list returns no policies. ' \
          "Maximum is #{Types::BaseArgument::MAX_ARRAY_SIZE} IDs."

      # PolicyStoreType serves Group and Organization parents.
      #
      # Runs once per container node; needs a batch API on the store before a
      # persistent (non in-memory) repository lands, or lists across containers N+1.
      # Pagination is tracked in https://gitlab.com/gitlab-org/gitlab/-/work_items/608267.
      def resolve(trigger_type: nil, ids: nil)
        return unless supported_container?

        response = ::Security::SecurityOrchestrationPolicies::PolicyStore::ListService
          .new(container: object, current_user: current_user, trigger_type: trigger_type, ids: ids)
          .execute

        if response.error?
          return if [:experiment_not_active, :forbidden].include?(response.reason)

          raise GraphQL::ExecutionError, response.message if response.reason == :invalid

          # Mirror REST: track the unmapped reason and surface a generic error rather
          # than collapsing service failures into the same null the gates produce.
          ::Gitlab::ErrorTracking.track_exception(
            UnmappedReasonError.new("Unmapped policy store reason: #{response.reason}"),
            service_message: response.message
          )

          raise GraphQL::ExecutionError, UNMAPPED_REASON_MESSAGE
        end

        response.payload[:policies]
      end

      private

      def supported_container?
        object.is_a?(::Organizations::Organization) || object.is_a?(::Group)
      end
    end
  end
end
