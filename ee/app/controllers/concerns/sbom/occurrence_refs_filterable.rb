# frozen_string_literal: true

module Sbom
  # Routes a dependency list request to the Sbom::OccurrenceRef Elasticsearch index or to
  # Postgres, and rejects an advanced filter that neither backend can answer.
  #
  # Including classes must supply #filterable_namespace, the Group or Project the request is
  # scoped to.
  #
  # Filters have to be keyed by symbol. A symbol Hash and ActionController::Parameters both
  # answer, but `params.permit(...).to_h` gives string keys and reads as no filter at all.
  #
  # Consumers call #validate_advanced_filters! first, then ask #use_elasticsearch? which
  # backend to use.
  module OccurrenceRefsFilterable
    extend ActiveSupport::Concern
    include ::Gitlab::Utils::StrongMemoize

    # Filters no Postgres finder can apply; asking for one is what moves a request onto
    # Elasticsearch.
    ADVANCED_FILTERS = %i[malware].freeze

    private

    # The Postgres fallback drops an advanced filter rather than applying it, so an
    # unavailable filter has to fail loudly instead of answering with an unfiltered list.
    def validate_advanced_filters!(filters)
      requested = requested_advanced_filters(filters)

      return if requested.empty?

      validate_policy_violations_conflict!(requested, filters)

      return if advanced_filters_available?

      raise ::Gitlab::Graphql::Errors::ArgumentError,
        "The #{requested.to_sentence} filter is not available."
    end

    # No backend can handle both: Elasticsearch supports advanced filters but lacks
    # policy_violations data; Postgres has policy_violations but lacks advanced filters.
    def validate_policy_violations_conflict!(requested, filters)
      return if filters[:policy_violations].blank?

      raise ::Gitlab::Graphql::Errors::ArgumentError,
        "The policy_violations filter cannot be combined with the #{requested.to_sentence} filter."
    end

    def use_elasticsearch?(filters)
      advanced_filters_requested?(filters) && advanced_filters_available?
    end

    def advanced_filters_requested?(filters)
      requested_advanced_filters(filters).any?
    end

    # `malware: false` is a filter in its own right, so presence is the wrong test.
    def requested_advanced_filters(filters)
      ADVANCED_FILTERS.reject { |filter| filters[filter].nil? }
    end

    def advanced_filters_available?
      read_advanced_dependency_management? && malware_filter_enabled?
    end

    # No separate index-readiness check: Sbom::AdvancedDependencyManagementPolicy already
    # prevents this ability when the OccurrenceRef index cannot serve reads.
    def read_advanced_dependency_management?
      ::Ability.allowed?(current_user, :read_advanced_dependency_management, filterable_namespace)
    end
    strong_memoize_attr :read_advanced_dependency_management?

    def malware_filter_enabled?
      Feature.enabled?(:malicious_packages_dependency_list_filtering, filterable_namespace, type: :beta)
    end
    strong_memoize_attr :malware_filter_enabled?

    def filterable_namespace
      raise NotImplementedError, "#{self.class} must implement #filterable_namespace"
    end
  end
end
