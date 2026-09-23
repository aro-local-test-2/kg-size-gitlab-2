# frozen_string_literal: true

module Organizations
  module ArtifactRegistryHelper
    def artifact_registry_repositories_app_data(organization, slug)
      {
        organization_gid: organization.to_global_id,
        slug: slug,
        base_path: artifact_registry_repositories_organization_path(organization, slug),
        client_base_url: artifact_registry_client_base_url
      }.to_json
    end

    def artifact_registry_setup_app_data(organization)
      {
        organization_path: organization.path,
        client_base_url: artifact_registry_client_base_url
      }.to_json
    end

    private

    # Nil unless ArtifactRegistry::Configuration.configured?, which is the same predicate the
    # Artifact Registry routes gate on, so a view that renders always carries an origin rather
    # than composing a package-manager URL from a value the gate refused.
    def artifact_registry_client_base_url
      ::ArtifactRegistry::Configuration.client_base_url
    end
  end
end
