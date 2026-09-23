# frozen_string_literal: true

module Analytics
  module AggregationEngines
    class DuoWorkflows < Gitlab::Database::Aggregation::ClickHouse::Engine
      self.table_name = 'duo_workflows_workflows_enriched'

      STATUSES = ::Ai::DuoWorkflows::Workflow.state_machines[:status].states
        .to_h { |state| [state.name.to_s, state.value] }.freeze

      # Per-user activity summary over the selected period: the CTE inherits the
      # request's scope, dedup, and row filters (notably the `created_at` range).
      supporting_cte :user_activity, join_key: :user_id do |qb|
        qb.select(
          qb.count.as('sessions'),
          qb.named_func('uniqExact', [qb[:workflow_definition]]).as('flow_types'),
          qb.named_func('uniqExact', [qb.named_func('toDate', [qb[:created_at]])]).as('active_days')
        )
      end

      dimensions do
        column :workflow_definition, :string, description: 'Type of flow'
        column :status, :string, description: 'Flow status',
          formatter: ->(value) { STATUSES.key(value) }
        column :project_id, :integer,
          description: 'Project the flow ran in. Returns `null` for flows not scoped to a project',
          association: true
        column :user_id, :integer, description: 'Flow owner', association: true
        traversal_path :group_id, :integer, -> { sql('traversal_path') },
          association: {
            finder: ->(ids) { Group.id_in(ids).with_route.index_by(&:id) },
            preloader: Preloaders::GroupPolicyPreloader
          },
          description: 'Group at the requested depth of the hierarchy. ' \
            'NULL for flows tracked above that depth. Flows tracked in a project at that depth ' \
            'bucket by project namespace ID, which also resolves to NULL.'
        column :model_used, :string, description: 'Model used by the flow'
        date_bucket :created_at, :date, description: 'Flow creation date'

        tier :user_tier, :string, -> { sql('user_activity.sessions') }, ctes: [:user_activity],
          description: 'User activity tier, bucketing users by their number of flows in the selected period ' \
            'using the `thresholds` argument'
      end

      metrics do
        count description: 'Total number of flows, optionally filtered by status',
          parameters: {
            status: { type: :string, in: STATUSES.keys, array: true,
                      description: 'Only count flows with the given statuses (created, running, finished, failed, ...)',
                      formatter: ->(values) { STATUSES.values_at(*values) } }
          }
        count :users, :integer, -> { sql('user_id') }, distinct: true, description: 'Number of unique users'
        count :projects, :integer, -> { sql('project_id') }, distinct: true,
          description: 'Number of unique projects'
        count :flow_types, :integer, -> { sql('workflow_definition') }, distinct: true,
          description: 'Number of unique flow types'
        retained_count :returning_users, :integer, -> { sql('user_id') }, over: :created_at,
          description: 'Number of unique users who also ran a flow in the previous period'
        acquired_count :joined_users, :integer, -> { sql('user_id') }, over: :created_at,
          description: 'Number of unique users who ran a flow in this period but not in the previous one'
        churned_count :churned_users, :integer, -> { sql('user_id') }, over: :created_at,
          description: 'Number of unique users who ran a flow in the previous period but not in this one'
        lagged_count :previous_period_users, :integer, -> { sql('user_id') }, over: :created_at,
          description: 'Number of unique users in the previous period'
      end

      measurement :credits_used, :float, -> { sql('credits_used') },
        description: 'Credits used by the flow', authorize: :read_agent_artifacts

      measurement :created_mr_count, :integer, -> { sql('length(created_merge_request_ids)') },
        description: 'Number of merge requests created by the flow'
      measurement :merged_mr_count, :integer, -> { sql('length(later_merged_merge_request_ids)') },
        description: 'Number of merge requests created by the flow that were later merged'
      measurement :closed_mr_count, :integer, -> { sql('length(later_closed_merge_request_ids)') },
        description: 'Number of merge requests created by the flow that were later closed without merging'
      # Filtering the created ids keeps the count non-negative: a removed MR link shrinks
      # created_merge_request_ids while the later_* arrays still carry that MR's outcome.
      measurement :open_mr_count, :integer, -> {
        sql(<<~SQL)
          length(arrayFilter(
            mr_id -> NOT has(later_merged_merge_request_ids, mr_id) AND NOT has(later_closed_merge_request_ids, mr_id),
            created_merge_request_ids
          ))
        SQL
      }, description: 'Number of merge requests created by the flow that are still open'

      filters do
        exact_match :workflow_definition, :string, description: 'Filter by one or many flow types'
        exact_match :status, :string,
          description: 'Filter by one or many flow statuses (created, running, finished, failed, ...)',
          formatter: ->(values) { STATUSES.values_at(*Array.wrap(values)).compact }
        exact_match :project_id, :string, description: 'Filter by one or many project Global IDs',
          formatter: gid_formatter
        exact_match :user_id, :string, description: 'Filter by one or many user Global IDs',
          formatter: gid_formatter
        descendants :group_id, :string, -> { sql('traversal_path') }, max_size: 100,
          description: 'Filter by one or many group Global IDs, including flows from their descendants'
        range :created_at, :datetime, description: 'Filter by flow creation timestamp'
        range :flow_types_used, :integer, -> { sql('user_activity.flow_types') }, ctes: [:user_activity],
          description: 'Filter by the number of distinct flow types the user ran in the selected period'
        range :active_days, :integer, -> { sql('user_activity.active_days') }, ctes: [:user_activity],
          description: 'Filter by the number of distinct days the user created flows in the selected period'
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
