# frozen_string_literal: true

# Elasticsearch filters, PostgreSQL sorts: the index stores name and path as analysed
# text and cannot sort on them. Sorting the re-hydrated relation is only sound for a
# complete match set, so a truncated one falls back instead.
module EE
  module Search
    module AdvancedFinders
      module GroupsFinder
        extend ActiveSupport::Concern
        extend ::Gitlab::Utils::Override
        include ::Gitlab::Utils::StrongMemoize
        include ::Namespaces::GroupsFilter

        # An allowed filter that search_options does not map is silently ignored by
        # Elasticsearch, so only add one with its mapping and a parity spec.
        ALLOWED_ES_FILTERS = %i[
          exclude_group_ids
          ids
          include_parent_descendants
          organization
          parent
          search
          visibility
        ].freeze

        # Sorting happens in PostgreSQL, so `sort` never disqualifies Elasticsearch.
        CONTROL_KEYS = %i[sort allow_similarity_sort].freeze

        # GraphQL sends with_statistics on every request and defaults all_available to
        # true, so counting their no-op values as filters would keep every GraphQL
        # request on PostgreSQL. Not lumped in with archived or active, where false is a
        # real filter.
        NO_OP_WHEN_FALSY = %i[
          filter_expired_saml_session_groups
          owned
          top_level_only
          with_knowledge_graph_enabled
          with_statistics
        ].freeze
        NO_OP_WHEN_TRUTHY = %i[all_available].freeze

        # GroupsFinder reads these with a truthy-default `fetch`, so an explicit nil
        # narrows exactly like false and must not be skipped as a no-op.
        TRUTHY_BY_DEFAULT = %i[all_available include_ancestors].freeze

        # Callers paginate the returned relation, so the match set is fetched up front.
        RESULT_LIMIT = 1_000

        # Group.search reads the routes table's full name and path unless a parent narrows
        # it, so the field set has to follow the same switch or the backends diverge.
        SEARCH_FIELDS = %w[name^3 path^2].freeze
        ROUTE_SEARCH_FIELDS = %w[name^3 full_name^2 path^2 full_path].freeze
        BACKFILL_MIGRATION = :backfill_groups_to_elasticsearch

        attr_reader :current_user, :params

        override :use_elasticsearch_finder?
        def use_elasticsearch_finder?
          feature_enabled? &&
            advanced_search_available? &&
            searching? &&
            index_ready? &&
            allowed_filters? &&
            expressible_parent?
        end

        # nil means "fall back to PostgreSQL".
        def execute
          result = search
          return unless result

          ids, total_count = result

          return if total_count > RESULT_LIMIT
          return ::Group.none if ids.empty?

          sort(::Group.id_in(ids).with_route.with_namespace_details)
        end

        private

        def search
          query = ::Search::Elastic::GroupQueryBuilder.build(
            query: params[:search],
            options: search_options
          )

          ::Gitlab::Search::Client.execute_search(query: query, options: search_options) do |raw|
            mapper = ::Search::Elastic::ResponseMapper.new(raw, search_options)
            next if mapper.failed?

            [mapper.results.map { |hit| hit.dig(:_source, :id) }, mapper.total_count]
          end
        rescue ::Elasticsearch::Transport::Transport::Error, ::Faraday::Error => e
          ::Gitlab::ErrorTracking.track_exception(e, class: self.class.name)

          nil
        end

        def search_options
          {
            current_user: current_user,
            klass: ::Group,
            index_name: ::Search::Elastic::References::Group.index,
            # Narrows the index's default field set, which also matches description.
            fields: search_fields,
            page: 1,
            per_page: RESULT_LIMIT,
            # Only the id is read out of each hit, and RESULT_LIMIT hits is a large payload.
            source_fields: [:id],
            visibility_levels: visibility_levels,
            ids: params[:ids],
            organization_id: organization_id,
            # The index stores the group's own archived flag, so leave archived filtering
            # to the by_archived default and let `archived` force a PostgreSQL fallback.
            include_archived: true
          }.merge(search_level_options).compact
        end
        strong_memoize_attr :search_options

        def search_fields
          params[:parent].blank? ? ROUTE_SEARCH_FIELDS : SEARCH_FIELDS
        end

        # GroupsFinder passes `organization` to `in_organization`, which accepts a record or
        # an id, so an id has to map here too or the filter would be dropped by `compact`.
        def organization_id
          organization = params[:organization]

          organization.respond_to?(:id) ? organization.id : organization
        end

        # A non-Group parent would otherwise widen silently to a global search.
        def expressible_parent?
          params[:parent].nil? || params[:parent].is_a?(::Group)
        end

        # root_ancestor_ids routes the query to one shard. search_level: :group matches the
        # whole subtree, which is only correct when include_parent_descendants is set.
        def search_level_options
          parent = params[:parent]
          return { search_level: :global, excluded_ids: params[:exclude_group_ids] } unless parent

          options = {
            search_level: :group,
            group_ids: [parent.id],
            root_ancestor_ids: [parent.root_ancestor.id],
            excluded_ids: Array(params[:exclude_group_ids])
          }

          if params[:include_parent_descendants]
            options.merge(excluded_ids: options[:excluded_ids] + [parent.id])
          else
            options.merge(parent_id: parent.id)
          end
        end

        # GroupsFinder also requires membership_bounded_scope?, which is false for every
        # param set eligible here, so similarity would order differently on the two paths.
        override :can_sort_by_similarity?
        def can_sort_by_similarity?
          false
        end

        # An unfiltered listing matches everything, so on any real instance it exceeds
        # RESULT_LIMIT and execute throws the hits away. Decline up front rather than pay
        # a round trip in front of the PostgreSQL query that runs anyway.
        def searching?
          params[:search].present?
        end

        def allowed_filters?
          (constraining_params - ALLOWED_ES_FILTERS).empty?
        end

        # params may be ActionController::Parameters, which is not Enumerable, so read
        # each key rather than iterating pairs.
        def constraining_params
          params.keys.filter_map do |key|
            value = params[key]
            key = key.to_sym

            next if CONTROL_KEYS.include?(key)
            next if value.nil? && TRUTHY_BY_DEFAULT.exclude?(key)
            next if NO_OP_WHEN_TRUTHY.include?(key) && value
            next if NO_OP_WHEN_FALSY.include?(key) && !value

            key
          end
        end

        def feature_enabled?
          ::Feature.enabled?(:advanced_groups_finder_elasticsearch, current_user)
        end

        def advanced_search_available?
          ::Gitlab::CurrentSettings.elasticsearch_search? &&
            !::Gitlab::CurrentSettings.advanced_search_indexing_paused?
        end

        def index_ready?
          ::Elastic::DataMigrationService.migration_has_finished?(BACKFILL_MIGRATION)
        end
      end
    end
  end
end
