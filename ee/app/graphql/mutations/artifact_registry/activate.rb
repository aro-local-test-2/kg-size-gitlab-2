# frozen_string_literal: true

module Mutations
  module ArtifactRegistry
    # Provisions an organization's registry: the mutation the owner's setup page
    # calls. Extends the Artifact Registry mutation base, overriding its
    # membership floor with update_organization because only an owner may claim a
    # slug; the base supplies the flag gate, the organization, the error mapping,
    # and the standard errors array.
    #
    # Arguments are the organization and the requested slug only. The billing
    # anchor is derived server-side from the organization's top-level group, so a
    # permanent value never reaches a form field or a mutation argument.
    #
    # A slug refusal and the zero-or-several-top-level-groups refusal are
    # expected recoverable outcomes, so they populate the payload's errors rather
    # than raising.
    class Activate < Base
      graphql_name 'ArtifactRegistryActivate'
      description 'Activates an Artifact Registry for an organization by claiming a slug.'

      # Matches the sibling Artifact Registry mutations: the call carries a service
      # credential with no user identity, and the organization owns no group or
      # project to scope a granular token against.
      authorize_granular_token skip_reason: :external_service_authorizes

      argument :slug, GraphQL::Types::String,
        required: true,
        description: "Slug to claim, Artifact Registry's immutable identifier for the namespace."

      field :registry, ::Types::ArtifactRegistry::RegistryType,
        null: true,
        experiment: { milestone: '19.4' },
        # Artifact Registry authorized the provision, and the owner-only gate
        # below already implies the read ability the type would check on the
        # organization the presenter carries, so that check is skipped.
        skip_type_authorization: [:read_artifact_registry],
        description: 'Registry provisioned. Null when the request was refused.'

      private

      # Claiming a slug is an owner-only write, so the base's read-ability floor is
      # raised to update_organization. That ability implies the read the base would
      # otherwise check, so it is the only gate this mutation needs.
      def ensure_artifact_registry_available!
        raise_resource_not_available_error! unless artifact_registry_enabled?

        organization = artifact_registry_organization
        raise_resource_not_available_error! unless current_user&.can?(:update_organization, organization)
      end

      def resolve_artifact_registry(slug:)
        response = ::ArtifactRegistry::ProvisionNamespaceService.new(
          organization: artifact_registry_organization, slug: slug,
          service_credential: ::ArtifactRegistry::ServiceCredential.new
        ).execute

        return { registry: registry_for(response.payload) } if response.success?

        # An unavailable service is terminal; the shared error mapping renders it as
        # service-unavailable. Every other refusal (a rejected slug, a missing or
        # ambiguous billing anchor) is recoverable, so the setup form can show it
        # and stay editable.
        raise ::ArtifactRegistry::Client::UnavailableError, response.message if response.reason == :service_unavailable

        errors << response.message
        { registry: nil }
      end

      # A fresh provision hands back the namespace it just fetched, so the registry
      # is built from it with no second read. An already-activated organization
      # carries no namespace, so its status is resolved from the cache instead.
      def registry_for(payload)
        mapping = payload[:namespace_mapping]
        namespace = payload[:ar_namespace]
        return resolved_registry(mapping) unless namespace

        present_registry(
          ::ArtifactRegistry::NamespaceMapping::Registry.new(
            ar_namespace_id: mapping.ar_namespace_id, slug: namespace.slug,
            status: namespace.status, created_at: namespace.created_at
          )
        )
      end

      # Resolving the existing mapping reads its cached status, which can itself
      # fail; a failure comes back as a marker rather than a raise, so it is
      # re-raised as its typed exception for the shared error mapping to render,
      # exactly as the query resolver does.
      def resolved_registry(mapping)
        result = mapping.registry
        return present_registry(result) unless result.is_a?(::ArtifactRegistry::NamespaceMapping::ResolutionFailure)

        raise result.to_client_error
      end
    end
  end
end
