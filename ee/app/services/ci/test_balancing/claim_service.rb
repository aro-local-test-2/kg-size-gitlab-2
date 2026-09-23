# frozen_string_literal: true

module Ci
  module TestBalancing
    # Claims a duration-budgeted batch of pending tests for the calling node.
    #
    # The claim is atomic in Redis (see Ci::TestBalancing::Queue): the slowest
    # pending tests are popped up to a tapering budget and moved into a per-node
    # backup set. The claimed tests are then persisted as write-once assignment
    # rows in PostgreSQL and the backup is cleared.
    #
    # If a previous claim popped from Redis but crashed before the PG write, the
    # node's backup is recovered on its next request before any new pop, so no
    # claimed test is ever lost. An empty result means the queue is drained.
    class ClaimService < BaseService
      def execute
        error = validate_preconditions
        return error if error

        recovered = recover_backup
        return success(convert_ids_to_paths(recovered)) if recovered.any?

        claimed = queue.claim
        return success([]) if claimed.empty?

        persist_assignments(claimed)
        queue.clear_backup

        success(convert_ids_to_paths(claimed))
      end

      private

      def convert_ids_to_paths(items)
        return [] if items.empty?

        ids = items.pluck(:test_split_id) # rubocop:disable CodeReuse/ActiveRecord, Database/AvoidUsingPluckWithoutLimit -- plain Array
        paths = ::Ci::TestBalancing::TestSplit.paths_by_id(job.project_id, ids)

        items.map do |item|
          { path: paths[item[:test_split_id]], expected_duration: item[:expected_duration] }
        end
      end

      def success(tests)
        ServiceResponse.success(payload: { test_splits: tests })
      end
    end
  end
end
