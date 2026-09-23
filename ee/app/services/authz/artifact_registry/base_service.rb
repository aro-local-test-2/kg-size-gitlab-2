# frozen_string_literal: true

module Authz
  module ArtifactRegistry
    class BaseService
      include ::Gitlab::Utils::StrongMemoize

      TOKEN_AUDIENCE = %w[gitlab-iam-data-access].freeze

      private

      attr_reader :current_user, :organization

      # Membership, not the home organization. A user is owned by exactly one
      # organization but can be a member of several, and at launch everyone
      # stays owned by the default one while gaining membership of the
      # organizations their groups move into. Ownership is deliberately not
      # required here: IAM's AuthorizeWrite already accepts an organization
      # owner or a caller holding the right grant, so demanding ownership would
      # reject grant holders before IAM ever sees the request.
      def caller_in_organization?
        current_user.member_of_organization?(organization)
      end

      # IAM cannot check a parent claim itself and believes whatever Rails
      # names, so a parent is only named once AR confirms the resource. Use
      # this method to produce a parent; structural_ancestor_for only answers
      # what sits above.
      def verified_ancestor_for(resource_id)
        ancestor = structural_ancestor_for(resource_id)
        return unless ancestor

        # Skips AR entirely when there is no ancestor to claim, so a request
        # naming only the namespace never calls out.
        return unless verified_repository_ids.include?(resource_id)

        ancestor
      end

      # A repository's parent is the organization's Artifact Registry namespace.
      # Naming it lets IAM accept an admin role held on the namespace, which is
      # how someone administers the whole organization's registry. The namespace
      # and the organization sit at the top, so they name no parent.
      #
      # Nothing targets the organization's own resource today, so the first
      # guard is for a future caller that does. The namespace is not above the
      # organization, so naming it as the organization's parent would be wrong
      # rather than merely useless.
      #
      # Structural only. It says nothing about whether the caller may name the
      # resource it returns, which is why verified_ancestor_for wraps it.
      def structural_ancestor_for(resource_id)
        return if resource_id == organization.uuid
        return if resource_id == artifact_registry_namespace_id

        artifact_registry_namespace_id
      end

      # One batched call per request, regardless of size. What a failure means
      # is the subclass's call, so this defers to on_verification_failure
      # instead of deciding here.
      def verified_repository_ids
        candidate_repository_ids.to_set - verification_failures
      # ArgumentError because the client's own input guards raise it.
      rescue ::ArtifactRegistry::Client::Error, ArgumentError => e
        on_verification_failure(e)
      end
      strong_memoize_attr :verified_repository_ids

      # Raw on purpose. A verdict naming an id nobody submitted means AR is
      # confused, not that everything passed. Subtracting it from the
      # candidates would lose that distinction.
      def verification_failures
        return Set.new if candidate_repository_ids.empty?

        artifact_registry_client.verify_repositories(
          namespace_id: artifact_registry_namespace_id,
          repository_ids: candidate_repository_ids
        ).to_set
      end
      strong_memoize_attr :verification_failures

      # The namespace names no parent, so it is excluded rather than verified.
      # These ids can never exceed ArtifactRegistry::Client::MAX_VERIFICATION_BATCH
      # because bulk mutations cap collections at Types::BaseArgument::MAX_ARRAY_SIZE.
      def candidate_repository_ids
        namespace_id = artifact_registry_namespace_id
        return [] unless namespace_id

        submitted_resource_ids.uniq - [namespace_id]
      end
      strong_memoize_attr :candidate_repository_ids

      # Grant fails closed here because writing an unverified resource
      # creates access. Revoke overrides this default because removing
      # access must keep working even when AR cannot answer.
      def on_verification_failure(error)
        raise error
      end

      def submitted_resource_ids
        raise NotImplementedError, "#{self.class} must implement #submitted_resource_ids"
      end

      def artifact_registry_namespace_id
        organization.artifact_registry_namespace_mapping&.ar_namespace_id
      end
      strong_memoize_attr :artifact_registry_namespace_id

      def artifact_registry_client
        ::ArtifactRegistry::Client.new(current_user: current_user)
      end

      def token
        ::Authn::TokenExchange::TokenIssuer.new(
          audiences: TOKEN_AUDIENCE,
          user: current_user,
          organization: organization
        ).token
      end

      # A single-item request needs no position, so return its bare message.
      # With several, prefix each with its position and resource so the caller
      # can tell which items to fix. Subclasses define request_items (the
      # submitted collection) and position_error_format (the verb wording).
      def validation_error(errors)
        # Precondition, not a runtime case: every caller establishes that it has
        # something to report before formatting it. Named here so a future caller
        # that does not gets this rather than a nil dereference.
        raise ArgumentError, 'validation_error needs at least one error' if errors.empty?

        return errors.first[:message] if request_items.size == 1

        errors.map do |error|
          format(position_error_format, error.slice(:number, :resource_id, :message))
        end.join("\n")
      end

      # Translates a client failure reason into a user-facing message. The
      # client stays transport-only and reports a reason; the wording lives
      # here. These three reasons read the same for every operation; the rest
      # are verb-specific and live in the subclasses.
      def iam_error_message(reason)
        case reason
        when :unauthenticated
          s_('ArtifactRegistry|Could not authenticate with the Artifact Registry service.')
        when :unavailable
          s_('ArtifactRegistry|The Artifact Registry service is unavailable.')
        when :timeout
          s_('ArtifactRegistry|The Artifact Registry service did not respond in time.')
        else
          fallback_error_message(reason)
        end
      end

      def client
        raise NotImplementedError, "#{self.class} must implement #client"
      end

      def error(message, reason: nil)
        ServiceResponse.error(message: message, reason: reason)
      end
    end
  end
end
