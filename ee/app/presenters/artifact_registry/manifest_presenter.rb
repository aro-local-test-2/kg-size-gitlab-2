# frozen_string_literal: true

module ArtifactRegistry
  # The manifest value object carries no image id and no back-reference to its read
  # context, so this presenter is how the referrers connection (keyed on the image id
  # and digest pair) reaches that context.
  class ManifestPresenter < ::Gitlab::View::Presenter::Delegated
    presents ::ArtifactRegistry::ManifestDetail

    # All three are required rather than optional: the referrers connection with any one missing
    # would fail only once it reached the client, far from the resolver that dropped it.
    def initialize(subject, repository:, organization:, image_id:) # rubocop:disable Lint/UselessMethodDefinition -- pins the three attributes as required keywords the **attributes parent leaves optional
      super
    end

    # Nothing evaluates this today because the organization-rooted field skips the ability.
    # It matters only if that skip is removed: the delegate would otherwise resolve to the
    # bare value object, which has no policy class, making DeclarativePolicy.class_for raise.
    def declarative_policy_subject
      organization
    end
  end
end
