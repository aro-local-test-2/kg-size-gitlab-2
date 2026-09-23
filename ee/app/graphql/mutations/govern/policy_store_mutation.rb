# frozen_string_literal: true

module Mutations
  module Govern
    # Shared by every policy store mutation: the organization lookup behind
    # authorized_find! and the fallback for service reasons the mutation does
    # not map. Which reasons are user-facing stays in each mutation's resolve.
    module PolicyStoreMutation
      extend ActiveSupport::Concern

      UnmappedReasonError = Class.new(StandardError)

      UNMAPPED_REASON_MESSAGE = 'Could not complete the policy store request'

      private

      # Mirror the policies resolver: track the unmapped reason and surface a generic
      # error rather than rendering an internal service message as user error.
      def track_unmapped_reason!(response)
        ::Gitlab::ErrorTracking.track_exception(
          UnmappedReasonError.new(
            "Unmapped policy store reason: #{response.reason} (#{self.class.graphql_name})"
          ),
          service_message: response.message
        )

        raise GraphQL::ExecutionError, UNMAPPED_REASON_MESSAGE
      end

      def find_object(organization_id:)
        ::GitlabSchema.object_from_id(organization_id, expected_type: ::Organizations::Organization).sync
      end
    end
  end
end
