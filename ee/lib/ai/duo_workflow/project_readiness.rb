# frozen_string_literal: true

module Ai
  module DuoWorkflow
    # Read-only view of how ready a project is to run Duo Agent Platform flows, backing
    # the readiness rows in Settings > General > GitLab Duo.
    class ProjectReadiness
      include ::Gitlab::Utils::StrongMemoize

      AGENT_CONFIG_PATH = ::Gitlab::DuoAgentPlatform::Config::CONFIG_FILE_NAME

      def initialize(project, user)
        @project = project
        @user = user
      end

      def platform_enabled?
        ::Ai::DuoWorkflow.duo_agent_platform_available?(project)
      end
      strong_memoize_attr :platform_enabled?

      # Applies the same gate as Ci::RegisterJobService, so a green row means a queued
      # flow would actually be picked up.
      def runner_available?
        usable_runner.present?
      end

      def usable_runner_type
        usable_runner&.runner_type
      end

      def agent_config_present?
        ::Gitlab::DuoAgentPlatform::Config.new(project).config_present?
      end
      strong_memoize_attr :agent_config_present?

      # Not read from AgentConfigWorkflowTracker: its cache entry expires while a
      # draft merge request can still be open.
      def agent_config_merge_request
        return if agent_config_present?

        MergeRequestsFinder.new(
          user,
          project_id: project.id,
          state: 'opened',
          blob_path: AGENT_CONFIG_PATH,
          sort: 'created_asc'
        ).execute.first
      end
      strong_memoize_attr :agent_config_merge_request

      def agent_config_workflow_id
        return if agent_config_present?

        AgentConfigWorkflowTracker.new(project).active_workflow&.id
      end
      strong_memoize_attr :agent_config_workflow_id

      def repository_empty?
        project.empty_repo?
      end
      strong_memoize_attr :repository_empty?

      # Without a flow consumer the run fails with a message meaningless to maintainers,
      # so the action is hidden instead.
      def generate_available?
        return false if repository_empty?

        catalog_item = ::Ai::Catalog::FoundationalFlow.developer_v1.catalog_item

        !!catalog_item&.consumers&.for_projects(project)&.exists?
      end
      strong_memoize_attr :generate_available?

      def mcp_servers_count
        agent_consumers = ::Ai::Catalog::ItemConsumersFinder
          .new(user, params: { project_id: project.id, item_types: [::Ai::Catalog::Item::AGENT_TYPE] })
          .execute
          .with_items

        latest_version_ids = agent_consumers.map { |consumer| consumer.item.latest_version_id }

        ::Ai::Catalog::McpServersBatchLoader
          .batch_mcp_servers_for_item_versions(latest_version_ids, user)
          .values.flatten.uniq.count
      end
      strong_memoize_attr :mcp_servers_count

      private

      def usable_runner
        candidate_runners.find { |runner| usable_runner?(runner) }
      end
      strong_memoize_attr :usable_runner

      attr_reader :project, :user

      # rubocop:disable CodeReuse/ActiveRecord -- Scoping across Ci::Runner and Ci::RunnerManager
      def candidate_runners
        # RunnerValidator reads runner.groups per candidate; preloading avoids an N+1.
        project.all_available_runners
          .active
          .online
          .with_tag(::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG)
          .preload(:runner_managers, :groups)
      end

      def usable_runner?(runner)
        return false unless ::Ai::DuoWorkflow::RunnerValidator.new(runner, project).valid?

        runner.runner_managers.any? { |manager| RunnerExecutors.docker_compatible?(manager) }
      end
      # rubocop:enable CodeReuse/ActiveRecord
    end
  end
end
