# frozen_string_literal: true

module Authn
  module TokenExchange
    # Which organization a token should speak for, when the caller cannot say.
    #
    # Package clients (Maven, npm, Docker) send a credential and nothing else,
    # and the organization that owns the account is the wrong answer once a
    # group has moved into a promoted organization: accounts stay owned by the
    # default organization and gain membership of the promoted one.
    #
    # So it is inferred. Under the closed beta every Artifact Registry
    # repository is private (ADR-021), so a caller can only reach artifacts in
    # an organization they hold a role in, which makes the single Artifact
    # Registry organization they belong to the one they must mean. That
    # reasoning stops holding the day public visibility exists, and this should
    # be revisited then.
    #
    # Interim. To be replaced by an explicit identifier sent by glab, see
    # https://gitlab.com/gitlab-org/ops/artifact-registry/-/work_items/977.
    class OrganizationResolver
      # Raised when the caller belongs to more than one Artifact Registry
      # organization, so there is nothing to infer. Refused rather than
      # guessed, since a token naming the wrong organization resolves to a
      # different principal in IAM and silently sees none of the caller's
      # roles.
      AmbiguousOrganizationError = Class.new(StandardError)

      def initialize(user)
        @user = user
      end

      def execute
        # Two is enough to tell "exactly one" from "more than one" without
        # loading every organization the caller belongs to.
        candidates = ::ArtifactRegistry::NamespaceMapping.for_member(@user).limit(2).map(&:organization)

        raise AmbiguousOrganizationError if candidates.size > 1

        candidates.first || fallback_organization
      end

      private

      # No Artifact Registry organization means nothing to reach yet, so the
      # token keeps saying what it has always said.
      # rubocop:disable Gitlab/AvoidUserOrganization -- the fallback is deliberately the account's own organization
      def fallback_organization
        @user.organization
      end
      # rubocop:enable Gitlab/AvoidUserOrganization
    end
  end
end
