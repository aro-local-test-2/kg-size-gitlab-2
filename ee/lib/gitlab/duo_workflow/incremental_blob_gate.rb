# frozen_string_literal: true

module Gitlab
  module DuoWorkflow
    # Decides whether a consumer reads channel_values from checkpoint_headers and
    # checkpoint_blobs deltas instead of the legacy p_duo_workflows_checkpoints row.
    #
    # Every consumer gate resolves to #read?, so none can skip
    # incremental_checkpoints_enabled. CreateCheckpointService writes a header only
    # when that column is set, so a gated read always has blobs to fold. That's what
    # makes the header table a safe superset of the legacy one, with no merging.
    #
    # Each consumer names its own flag so the read surfaces roll out separately. The
    # lookups repeat rather than share a helper, to keep every flag name a literal
    # symbol. They run before #read? so a disabled consumer skips its header query;
    # that is only nil-safe because the constructor resolved the root ancestor.
    class IncrementalBlobGate
      def initialize(workflow)
        @workflow = workflow
        @parent = workflow.resource_parent
        @root_ancestor = @parent&.root_ancestor
      end

      # Base gate for the one consumer without a per-consumer flag: the __start__
      # channel read in CreateCheckpointService.
      def reconstruct?
        return false unless parent && workflow.incremental_checkpoints_enabled?

        Feature.enabled?(:duo_workflow_read_incremental_checkpoints, parent) ||
          Feature.enabled?(:duo_workflow_read_incremental_checkpoints, root_ancestor)
      end

      # The shared condition behind every consumer gate. The write path stays on
      # #reconstruct?, so a checkpoint write pays no membership query.
      def read?
        reconstruct? && !workflow.legacy_checkpoint_fallback?
      end

      def for_notifications?
        return false unless Feature.enabled?(:dw_read_blobs_notifications, parent) ||
          Feature.enabled?(:dw_read_blobs_notifications, root_ancestor)

        read?
      end

      def for_list?
        return false unless Feature.enabled?(:dw_read_blobs_list, parent) ||
          Feature.enabled?(:dw_read_blobs_list, root_ancestor)

        read?
      end

      # #for_graphql? without the #legacy_checkpoint_fallback? header read, so a
      # batch loader can filter a page of workflows before fetching any headers.
      def graphql_candidate?
        return false unless Feature.enabled?(:dw_read_blobs_graphql, parent) ||
          Feature.enabled?(:dw_read_blobs_graphql, root_ancestor)

        reconstruct?
      end

      def for_graphql?
        graphql_candidate? && !workflow.legacy_checkpoint_fallback?
      end

      def for_trace?
        return false unless Feature.enabled?(:dw_read_blobs_trace, parent) ||
          Feature.enabled?(:dw_read_blobs_trace, root_ancestor)

        read?
      end

      private

      attr_reader :workflow, :parent, :root_ancestor
    end
  end
end
