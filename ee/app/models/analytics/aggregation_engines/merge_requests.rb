# frozen_string_literal: true

module Analytics
  module AggregationEngines
    class MergeRequests < Gitlab::Database::Aggregation::ClickHouse::Engine
      self.table_name = 'merge_requests'

      MERGED_STATE_ID = ::Issuable::STATE_ID_MAP[:merged]

      transient(:merge_duration_ms) do
        sql(
          'multiIf(isNotNull(metric_merged_at),
          toUnixTimestamp64Milli(assumeNotNull(metric_merged_at)) - toUnixTimestamp64Milli(created_at),
          NULL)'
        )
      end

      dimensions do
        column :target_branch, :string, description: 'Target branch of the merge request'
        column :state_id, :string, description: 'Merge request state',
          formatter: ->(value) { ::Issuable::STATE_ID_MAP.key(value)&.to_s }
        column :author_id, :integer, description: 'Merge request author', association: { model: ::User }
        date_bucket :created_at, :date, description: 'Merge request creation date'
        date_bucket :metric_merged_at, :date, description: 'Merge request merge date'
        column :created_by_duo, :boolean,
          description: 'Whether the merge request was created by a GitLab Duo session'
      end

      metrics do
        count description: 'Total number of merge requests'

        count :throughput, :integer,
          if: ->(_params) { sql("state_id = #{MERGED_STATE_ID}") },
          description: 'Number of merged merge requests'

        rate :acceptance,
          numerator_if: ->(_params) { sql("state_id = #{MERGED_STATE_ID}") },
          description: 'Share of merge requests that were merged'

        # DEPRECATED: use the `time_to_merge` measurement instead
        quantile :time_to_merge, :float, transient(:merge_duration_ms),
          description: 'Time to merge quantile in milliseconds',
          parameters: {
            quantile: { type: :float, in: 0.0..1.0,
                        description: 'Quantile level between 0.0 and 1.0 (e.g. 0.5 for median)' }
          }
      end

      measurement :time_to_merge, :integer, -> {
        sql('multiIf(isNotNull(metric_merged_at), toInt64(ceil(
            (toUnixTimestamp64Milli(assumeNotNull(metric_merged_at)) - toUnixTimestamp64Milli(created_at)) / 1000
          )), NULL)')
      }, description: 'Time to merge in seconds'

      filters do
        exact_match :target_branch, :string, description: 'Filter by one or many target branches'
        exact_match :state_id, :string, description: 'Filter by one or many states (opened, closed, merged, locked)',
          formatter: ->(values) { Array.wrap(values).filter_map { |v| ::Issuable::STATE_ID_MAP[v.to_sym] } }
        exact_match :author_id, :string, description: 'Filter by one or many author Global IDs',
          formatter: gid_formatter
        exact_match :created_by_duo, :boolean,
          description: 'Filter by whether the merge request was created by a GitLab Duo Agent Platform session'
        range :created_at, :datetime, description: 'Filter by merge request creation timestamp'
        range :metric_merged_at, :datetime, description: 'Filter by merge timestamp'
      end

      def self.prepare_base_aggregation_scope(objects)
        builder = ClickHouse::Client::QueryBuilder.new(table_name)

        conditions = Array.wrap(objects).map do |object|
          namespace = object.is_a?(Project) ? object.project_namespace : object

          builder.func('startsWith', [
            builder[:traversal_path],
            Arel::Nodes.build_quoted(namespace.traversal_path(with_organization: true).to_s)
          ])
        end

        raise ArgumentError, 'at least one scope object is required' if conditions.empty?

        builder.where(conditions.reduce(:or))
      end
    end
  end
end
