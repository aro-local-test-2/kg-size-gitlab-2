# frozen_string_literal: true

module ArtifactRegistry
  # Provisions an artifact registry namespace for an organization.
  #
  # The organization uniqueness constraint is the concurrency guard: a losing
  # racer's insert is rescued and resolved to the winning row, so two same-slug
  # requests produce one row and both succeed, and a repeat request is idempotent.
  class ProvisionNamespaceService
    # service_credential stays mandatory: whatever the caller injects now travels
    # in the AR service-token header, so it must be the mounted secret.
    def initialize(organization:, slug:, service_credential:)
      @organization = organization
      @slug = slug.to_s
      @service_credential = service_credential
    end

    def execute
      # An already-activated organization resolves to its existing mapping before
      # any slug or billing-anchor check, so re-activation is idempotent even if
      # the top-level groups changed or a different slug is submitted.
      existing = organization.artifact_registry_namespace_mapping
      return ServiceResponse.success(payload: { namespace_mapping: existing }) if existing

      validator = SlugValidator.new(slug)
      return validator.result unless validator.valid?

      billing_group = resolve_billing_group
      return billing_group unless billing_group.is_a?(::Group)

      provision(billing_group)
    end

    private

    attr_reader :organization, :slug, :service_credential

    def provision(billing_group)
      logger.info(**log_base_data.merge(message: 'provision_namespace request', slug: slug,
        Labkit::Fields::GL_ROOT_NAMESPACE_ID => billing_group.id))

      ar_namespace = client.provision_namespace(
        slug: slug,
        platform: Client::PLATFORM,
        entity_type: Client::ENTITY_TYPE_ORGANIZATION,
        entity_id: organization.uuid,
        billing_entity_type: Client::BILLING_ENTITY_TYPE_GROUP,
        billing_entity_id: billing_group.id
      )

      logger.info(**log_base_data.merge(message: 'provision_namespace response', ar_namespace_id: ar_namespace.id))

      mapping = create_or_resolve_mapping(ar_namespace.id)
      return mapping_lost_error if mapping.nil?

      # Hand back the namespace already fetched so the caller reads status and
      # created_at from it rather than a second GET on a cache the new row has
      # not warmed yet.
      ServiceResponse.success(payload: { namespace_mapping: mapping, ar_namespace: ar_namespace })
    rescue Client::ApiError => e
      handle_api_error(e)
    rescue Client::UnavailableError => e
      ServiceResponse.error(message: e.message, reason: :service_unavailable)
    end

    # A concurrent same-slug request can win the organization uniqueness guard
    # first: the validation raises RecordInvalid, the DB index raises
    # RecordNotUnique, and either way the winning row already holds the mapping.
    # Only that taken-organization case is resolved; any other invalidity (e.g. a
    # blank ar_namespace_id) is a real error and re-raises.
    def create_or_resolve_mapping(ar_namespace_id)
      NamespaceMapping.create!(organization: organization, ar_namespace_id: ar_namespace_id)
    rescue ActiveRecord::RecordNotUnique
      organization.reset.artifact_registry_namespace_mapping
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:organization, :taken)

      organization.reset.artifact_registry_namespace_mapping
    end

    def resolve_billing_group
      top_level_groups = organization.groups.top_level.limit(2).to_a

      case top_level_groups.length
      when 0
        ServiceResponse.error(message: 'organization has no top-level groups', reason: :no_billing_anchor)
      when 1
        top_level_groups.first
      else
        ServiceResponse.error(
          message: 'organization has more than one top-level group',
          reason: :multiple_billing_anchors
        )
      end
    end

    def mapping_lost_error
      ServiceResponse.error(
        message: 'namespace mapping was removed during a concurrent request',
        reason: :mapping_lost
      )
    end

    def handle_api_error(error)
      case error.status
      when 409
        ServiceResponse.error(message: error.message, reason: :conflict)
      when 422
        ServiceResponse.error(message: error.message, reason: :unprocessable)
      else
        ServiceResponse.error(message: error.message, reason: :api_error)
      end
    end

    def log_base_data
      {
        Labkit::Fields::CLASS_NAME => self.class.name,
        Labkit::Fields::GL_ORGANIZATION_ID => organization.id
      }
    end

    def client
      @client ||= Client.new(service_credential: service_credential)
    end

    def logger
      @logger ||= Logger.build
    end
  end
end
