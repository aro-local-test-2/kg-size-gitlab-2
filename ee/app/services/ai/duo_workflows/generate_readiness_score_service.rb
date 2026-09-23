# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Triggers the async, CI-backed "readiness_score" foundational flow for a
    # work item, scoring its readiness without opening Duo Chat.
    class GenerateReadinessScoreService
      include ::Gitlab::Utils::StrongMemoize

      WORKFLOW_DEFINITION_REFERENCE = 'readiness_score/v1'
      # Long enough to cover workflow creation + CI start, short enough that a
      # lease left by a crashed request frees quickly for a retry.
      LEASE_TTL = 2.minutes

      FEATURE_DISABLED_ERROR = 'Readiness score generation is not enabled for this project'
      PROJECT_REQUIRED_ERROR = 'Readiness score generation is only available for project work items'
      FLOW_UNAVAILABLE_ERROR = 'Readiness score flow is not available'
      WORKFLOW_ALREADY_RUNNING_ERROR = 'A readiness score generation is already running for this work item'

      def initialize(work_item:, current_user:)
        @work_item = work_item
        @current_user = current_user
      end

      def execute
        return error(PROJECT_REQUIRED_ERROR, :project_required) unless project
        return error(FEATURE_DISABLED_ERROR, :feature_disabled) unless feature_enabled?
        return error(FLOW_UNAVAILABLE_ERROR, :flow_unavailable) unless workflow_definition

        start_workflow
      end

      private

      attr_reader :work_item, :current_user

      # The duplicate check and the create it guards must both run inside the held
      # lease; otherwise two concurrent callers (double-click, retry race) could
      # both pass the check before either workflow row commits.
      def start_workflow
        lease_uuid = Gitlab::ExclusiveLease.new(lease_key, timeout: LEASE_TTL.to_i).try_obtain
        return error(WORKFLOW_ALREADY_RUNNING_ERROR, :workflow_already_running) unless lease_uuid

        begin
          return error(WORKFLOW_ALREADY_RUNNING_ERROR, :workflow_already_running) if workflow_already_running?

          ::Ai::DuoWorkflows::CreateAndStartWorkflowService.new(
            container: project,
            resource: work_item,
            current_user: current_user,
            goal: goal,
            source_branch: project.default_branch,
            workflow_definition: workflow_definition
          ).execute
        ensure
          Gitlab::ExclusiveLease.cancel(lease_key, lease_uuid)
        end
      end

      def lease_key
        "duo_workflows_generate_readiness_score:#{work_item.id}"
      end

      def project
        work_item.project
      end
      strong_memoize_attr :project

      def feature_enabled?
        ::Feature.enabled?(:workplan_score, project.root_ancestor)
      end

      def workflow_definition
        ::Ai::Catalog::FoundationalFlow[WORKFLOW_DEFINITION_REFERENCE]
      end
      strong_memoize_attr :workflow_definition

      def workflow_already_running?
        work_item.duo_workflows
          .with_workflow_definition(WORKFLOW_DEFINITION_REFERENCE)
          .with_non_terminal_status
          .exists?
      end

      def goal
        ::Ai::Catalog::GoalTemplates::ReadinessScore.resolve(resource: work_item)
      end

      def error(message, reason)
        ServiceResponse.error(message: message, reason: reason)
      end
    end
  end
end
