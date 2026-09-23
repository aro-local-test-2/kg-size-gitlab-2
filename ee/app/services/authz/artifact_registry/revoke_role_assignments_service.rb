# frozen_string_literal: true

module Authz
  module ArtifactRegistry
    # Revokes a set of Artifact Registry role assignments in a single
    # all-or-nothing delete to the IAM Relationships API.
    #
    # A revocation names an assignee and a resource, no role: IAM stores one
    # ASSIGNMENT per (subject, object), so the pair identifies the assignment
    # and revoking removes whatever role the assignee holds there. Deleting an
    # assignment that does not exist succeeds for a subject IAM has already
    # seen, but IAM fails the whole batch with NOT_FOUND when any subject was
    # never granted anything. Both the single and bulk revoke mutations use
    # this service; the single revoke passes a one-element array.
    class RevokeRoleAssignmentsService < BaseService
      def initialize(current_user:, organization:, revocations:)
        @current_user = current_user
        @organization = organization
        # IAM only accepts canonical lowercase ids, so normalize case here
        # rather than rejecting an uppercase id.
        @revocations = revocations.map do |revocation|
          revocation.merge(resource_id: revocation[:resource_id]&.downcase)
        end
      end

      def execute
        return error(s_('ArtifactRegistry|You must be signed in to revoke a role.')) unless current_user
        return error(s_('ArtifactRegistry|Organization could not be determined.')) unless organization
        # The organization comes from the request context and can be influenced by
        # request headers, so confirm it is the caller's own before scoping the
        # IAM delete to it.
        unless caller_in_organization?
          return error(s_('ArtifactRegistry|You cannot revoke roles in another organization.'))
        end

        return error(s_('ArtifactRegistry|At least one revocation is required.')) if revocations.empty?

        # Validate every revocation and report each invalid one rather than
        # stopping at the first, so a caller fixing a bulk request sees all the
        # problems in one round-trip.
        errors = revocations.each_with_index.filter_map do |revocation, index|
          message = revocation_error(revocation)
          next unless message

          { number: index + 1, resource_id: revocation[:resource_id], message: message }
        end
        return error(validation_error(errors)) if errors.any?

        # Deleting the same key twice is harmless, so duplicates are collapsed
        # rather than rejected the way the grant path must. Deduplicating also
        # keeps revoked_role_count an honest count of distinct assignments.
        keys = revocations.map { |revocation| build_key(revocation) }.uniq

        client.revoke_roles(keys, organization_uuid: organization.uuid, token: token)

        ServiceResponse.success(payload: { revoked_role_count: keys.size })
      rescue ::Authn::IamService::UpdateRelationshipsClient::RequestError => e
        error(iam_error_message(e.reason), reason: e.reason)
      end

      private

      attr_reader :revocations

      alias_method :request_items, :revocations

      # Returns an error message if the revocation is invalid, otherwise nil.
      def revocation_error(revocation)
        assignee, resource_id = revocation.values_at(:assignee, :resource_id)

        # No organization check on the assignee, deliberately, and unlike grant.
        # IAM keys a subject by organization plus user, so this organization's
        # delete can only remove a tuple in its own identity space and naming
        # someone outside it removes nothing. Requiring membership instead
        # would make a role unrevokable the moment someone is removed from the
        # organization, which is exactly when it has to go, because Artifact
        # Registry validates tokens locally and never calls back to Rails
        # (gitlab-org/gitlab#610042). An assignee IAM does not know comes back
        # as this same message through the not_found branch below.
        return s_('ArtifactRegistry|Assignee could not be found.') unless assignee
        return s_('ArtifactRegistry|Resource ID must be a valid UUIDv7.') unless ::Gitlab::UUID.v7?(resource_id)

        nil
      end

      # Builds the IAM delete key for a revocation already validated by
      # revocation_error.
      def build_key(revocation)
        resource_id = revocation[:resource_id]

        # compact drops parent_id when the target has no parent to name, so the
        # key keeps the shape it had before.
        {
          assignee_id: revocation[:assignee].id,
          resource_id: resource_id,
          parent_id: verified_ancestor_for(resource_id)
        }.compact
      end

      def submitted_resource_ids
        revocations.map { |revocation| revocation.fetch(:resource_id) }
      end

      # Grant fails closed when AR cannot verify a resource, because writing an
      # unverified one creates access. Revoke must not. Removing access has to
      # keep working while someone is being offboarded, including when AR is
      # unreachable (gitlab-org/gitlab#610042). So a failure names no parent
      # rather than rejecting the revocation, which leaves the caller needing a
      # role on the repository itself. That is the behaviour before the parent
      # existed, so this can only add a way to succeed.
      def on_verification_failure(error)
        Gitlab::ErrorTracking.track_exception(error)
        Set.new
      end

      def position_error_format
        s_('ArtifactRegistry|Revocation %{number} on resource %{resource_id}: %{message}')
      end

      def client
        ::Authn::IamService::UpdateRelationshipsClient.new
      end

      def fallback_error_message(reason)
        case reason
        when :not_found
          # IAM fails the whole batch with NOT_FOUND when a subject was never
          # granted anything. Same generic message as a missing assignee, so it
          # discloses nothing about who IAM knows.
          s_('ArtifactRegistry|Assignee could not be found.')
        when :permission_denied
          s_('ArtifactRegistry|You are not authorized to revoke this role on this resource.')
        when :invalid_request
          s_('ArtifactRegistry|The role revocation request was invalid.')
        else
          s_('ArtifactRegistry|The role revocation could not be completed.')
        end
      end
    end
  end
end
