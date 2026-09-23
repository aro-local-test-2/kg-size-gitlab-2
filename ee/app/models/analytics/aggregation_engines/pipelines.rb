# frozen_string_literal: true

module Analytics
  module AggregationEngines
    class Pipelines < Gitlab::Database::Aggregation::ClickHouse::Engine
      self.table_name = 'siphon_p_ci_pipelines'

      SOURCES = ::Enums::Ci::Pipeline.sources.freeze
      STATUSES = ::Ci::HasStatus::AVAILABLE_STATUSES.freeze
      COMPLETED_STATUSES = ::Ci::HasStatus::COMPLETED_STATUSES.freeze

      dimensions do
        column :status, :string, description: 'Pipeline status'
        column :source, :string, description: 'Pipeline source',
          formatter: ->(value) { SOURCES.key(value)&.to_s }
        column :ref, :string, description: 'Pipeline ref'
        column :project_id, :integer, description: 'Project', association: {
          finder: ->(ids) { Project.where(id: ids).index_by(&:id) }
        }
        # Pipelines started by a schedule, a trigger token, or an integration have no user.
        column :user_id, :integer, description: 'User who triggered the pipeline', association: true
        date_bucket :started_at, :date, description: 'Pipeline start date'
        date_bucket :finished_at, :date, description: 'Pipeline finish date'
      end

      metrics do
        count description: 'Total number of pipelines, optionally filtered by source or status',
          parameters: {
            source: { type: :string, in: SOURCES.keys.map(&:to_s), array: true,
                      description: 'Only count pipelines with the given sources.',
                      formatter: ->(values) { values.filter_map { |source| SOURCES[source.to_sym] } } },
            status: { type: :string, in: STATUSES, array: true,
                      description: 'Only count pipelines with the given statuses.' }
          }

        # DEPRECATED: use the `duration` measurement instead
        quantile :duration, :float, ->(_params) {
          sql('duration')
        }, description: 'Pipeline duration quantile in seconds', parameters: {
          quantile: { type: :float, in: 0.0..1.0 }
        }

        rate :outcome,
          numerator_if: ->(params) {
            statuses = Array.wrap(params[:status]) & COMPLETED_STATUSES
            return sql('FALSE') if statuses.empty?

            sql("status IN (#{statuses.map { |s| "'#{s}'" }.join(', ')})")
          },
          denominator_if: ->(_params) { sql("status IN (#{COMPLETED_STATUSES.map { |s| "'#{s}'" }.join(', ')})") },
          description: 'Rate of pipelines with the given status among completed pipelines',
          parameters: {
            status: { type: :string, in: COMPLETED_STATUSES, array: true }
          }
      end

      measurement :duration, :integer, ->(_params) { sql('duration') },
        description: 'Pipeline duration in seconds'

      filters do
        exact_match :status, :string, description: 'Filter by one or many pipeline statuses'
        exact_match :source, :string, description: 'Filter by one or many pipeline sources',
          formatter: ->(values) { Array.wrap(values).filter_map { |v| SOURCES[v.to_sym] } }
        exact_match :ref, :string, description: 'Filter by one or many pipeline refs'
        exact_match :user_id, :string, description: 'Filter by one or many user Global IDs',
          formatter: gid_formatter
        range :started_at, :datetime, description: 'Filter by pipeline start timestamp'
        range :finished_at, :datetime, description: 'Filter by pipeline finish timestamp'
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
