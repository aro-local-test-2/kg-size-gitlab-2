# frozen_string_literal: true

module Analytics
  module AggregationEngines
    class AgentPlatformSessions < Gitlab::Database::Aggregation::ClickHouse::Engine
      self.table_name = 'agent_platform_sessions'

      transient(:is_finished) { sql('anyIfMerge(finished_event_at) IS NOT NULL') }
      transient(:created_event_at) { sql('anyIfMerge(created_event_at)') }
      # `project_id` is outside the table sort key, so it must be read through an aggregate to keep
      # the inner query at one row per session. A session always belongs to a single project.
      transient(:project_id) { sql('any(project_id)') }

      measurement :duration, :integer, -> {
        sql("dateDiff('seconds', anyIfMerge(created_event_at), anyIfMerge(finished_event_at))")
      }, description: 'Session duration in seconds'

      dimensions do
        column :flow_type, :string, description: 'Type of session'
        column :user_id, :integer, description: 'Session owner', association: true
        # Sessions that are not scoped to a project store `0`, which resolves to no project.
        column :project_id, :integer, transient(:project_id),
          description: 'Project the session ran in', association: true
        date_bucket :created_event_at, :date, transient(:created_event_at),
          description: 'Session creation date'
      end

      metrics do
        count description: 'Total number of sessions'
        count :finished, if: transient(:is_finished), description: 'Number of finished sessions'
        count :users, :integer, -> { sql('user_id') }, distinct: true, description: 'Number of unique users'
        count :features, :integer, -> { sql('flow_type') }, distinct: true,
          description: 'Number of unique features (flow types)'

        mean :duration, :float, transient(:duration), description: 'Average session duration in seconds'

        rate :completion, numerator_if: transient(:is_finished), description: 'Session completion rate'

        quantile :duration, :float, transient(:duration), description: 'Session duration quantile in seconds',
          parameters: {
            quantile: { type: :float, in: 0.0..1.0 }
          }
      end

      filters do
        exact_match :user_id, :string, description: 'Filter by one or many user Global IDs',
          formatter: gid_formatter
        exact_match :flow_type, :string, description: 'Filter by one or many flow types'
        exact_match :project_id, :string, description: 'Filter by one or many project Global IDs',
          formatter: gid_formatter
        range :created_event_at, :datetime, transient(:created_event_at),
          merge_column: true,
          description: 'Filter by session creation timestamp'
        metric_range :features_count, :integer, description: 'Filter by the number of unique features.'
      end

      def self.prepare_base_aggregation_scope(objects)
        builder = ClickHouse::Client::QueryBuilder.new(table_name)

        conditions = Array.wrap(objects).map do |object|
          namespace = object.is_a?(Project) ? object.project_namespace : object

          builder.func('startsWith', [
            builder[:namespace_path], Arel::Nodes.build_quoted(namespace.traversal_path(with_organization: false).to_s)
          ])
        end

        raise ArgumentError, 'at least one scope object is required' if conditions.empty?

        builder.where(conditions.reduce(:or))
      end
    end
  end
end
