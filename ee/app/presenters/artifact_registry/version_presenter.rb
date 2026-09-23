# frozen_string_literal: true

module ArtifactRegistry
  # Pairs a version value object with the repository and organization it was read through. The
  # value object holds no back-reference, so a child field mounted on the version details type --
  # the files connection and the statistics field -- has no other way to reach the slug, the
  # repository name and format, and the memoized client its own read needs.
  class VersionPresenter < ::Gitlab::View::Presenter::Delegated
    presents ::ArtifactRegistry::Version

    # Repository and organization are required rather than optional attributes: a child field
    # with either one missing would fail only once it reached the client, far from the resolver
    # that dropped it.
    def initialize(subject, repository:, organization:) # rubocop:disable Lint/UselessMethodDefinition -- pins the two attributes as required keywords the **attributes parent leaves optional
      super
    end

    # Points type authorization at the organization, which governs reading a version, exactly as
    # RepositoryPresenter does. Nothing evaluates it today: the organization-rooted fields skip
    # this ability. It matters if that skip goes -- the inherited delegate resolves to the bare
    # value object, which has no policy class, so DeclarativePolicy.class_for would raise rather
    # than deny.
    def declarative_policy_subject
      organization
    end
  end
end
