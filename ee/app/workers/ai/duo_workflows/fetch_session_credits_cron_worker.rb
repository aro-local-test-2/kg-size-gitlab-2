# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Scans duo_workflows_workflows for sessions currently in a billable status and
    # fans out per-namespace fetches of their credit totals from CustomersDot.
    #
    # Current status, not "ever reached a billable status": a session that billed and
    # then dropped to `failed` before its billable second was scanned is missed and
    # reads null. Accepted for 19.4; scanning `failed` is a tracked follow-up.
    class FetchSessionCreditsCronWorker
      include ApplicationWorker
      # The SyncCursor advance is a ClickHouse insert, so this worker registers for
      # migration pause control like its child.
      include ClickHouseWorker
      # Disables retries: a retried run could overlap the next 15-minute tick and
      # double-read the cursor. A dropped cycle just widens the next scan window.
      include ::CronjobQueue

      idempotent!
      # :until_executing releases as soon as a run starts; :until_executed drops a
      # tick that would overlap a still-running one.
      deduplicate :until_executed
      # :delayed depends on the retry mechanism CronjobQueue disables. Replica lag
      # cannot matter anyway: the scan only reads rows older than SETTLE_HORIZON.
      data_consistency :sticky
      feature_category :duo_agent_platform
      urgency :low
      tags :clickhouse
      # Credits are never urgent; on a degraded table skip the cycle. A deferred run
      # does not scan, so the cursor stays put and the next run picks the same rows up.
      # Dispatched batches that fail later are recovered by the child worker's retries.
      defer_on_database_health_signal :gitlab_main_org, [:duo_workflows_workflows]

      SYNC_CURSOR = :duo_workflow_session_credits
      # Grace period for AI Gateway's billing events to land in CustomersDot before a
      # session's transition is scanned.
      SETTLE_HORIZON = 2.hours
      # Bounds the scan to 1,000 sessions a tick. Child jobs are one per root namespace
      # in the batch, so the worst case is 1,000 jobs, drained 5 at a time by the child's
      # concurrency_limit. A backlog clears at ~96k sessions a day.
      MAX_ROWS_PER_RUN = 1_000
      MAX_IDS_PER_JOB = 100

      def perform
        return unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?
        return seed_cursor if cursor == 0

        backoff_reason = SessionCredits::Backoff.reason
        return log_backoff(backoff_reason) if backoff_reason

        rows = scan
        return if rows.empty?

        # The cursor moves past every scanned row, dispatched or not. Rows outside the
        # rollout gate are skipped, not queued: holding the cursor for them would freeze
        # a group pilot on the first 1,000-row stretch with no eligible row, and would
        # let the deploy-to-enable gap pile up into a surprise backfill.
        log_extra_metadata_on_done(:dispatched_jobs, dispatch(rows))
        ::ClickHouse::SyncCursor.update_cursor_for(SYNC_CURSOR, rows.last.updated_at.to_i)
      end

      private

      # A group gate or the global toggle both satisfy the group actor check.
      # Self-managed batches carry no namespace, so only the instance toggle applies.
      def ingestion_enabled_for?(root_namespace_id)
        return Feature.enabled?(:duo_workflow_session_credits_ingestion, :instance) unless root_namespace_id

        Feature.enabled?(:duo_workflow_session_credits_ingestion, ::Group.actor_from_id(root_namespace_id))
      end

      def saas?
        ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      end

      # `> cursor_time`, not `>= cursor_time + 1.second`: the cursor stores whole
      # epoch seconds, so the high-water second is re-read next run. Re-fetching is an
      # upsert and the safe direction to round; skipping would drop rows that
      # MAX_ROWS_PER_RUN truncated mid-second. Known limit: a single second holding
      # more than MAX_ROWS_PER_RUN rows cannot be crossed (a composite cursor with an
      # id tiebreak is a tracked follow-up).
      #
      # One branch per billable status, not `status IN (...)`: idx_workflows_status_updated_at_id
      # leads on status, so an IN list leaves Postgres unable to emit rows in (updated_at, id)
      # order. It then sorts every row in the window before applying the limit, which timed out
      # once the window grew (the cursor only advances on success, so each timeout widened it).
      # Equality on the leading column gives one ordered index scan per status, merged by
      # MergeAppend, and the limit stops the scan early again.
      #
      # rubocop:disable CodeReuse/ActiveRecord -- the bounded window and keyset order
      # ride idx_workflows_status_updated_at_id, this worker's scan strategy.
      def scan
        # Both bounds are resolved once and shared by every branch. Evaluating them inside
        # the branch loop gave each status a window a few microseconds apart, so a row near
        # a boundary could sit inside one status's window and outside another's.
        lower = cursor_time
        upper = SETTLE_HORIZON.ago

        ::Ai::DuoWorkflows::Workflow
          .from_union(scan_branches(lower, upper), remove_duplicates: false, remove_order: false)
          .order(:updated_at, :id)
          .limit(MAX_ROWS_PER_RUN)
          .to_a
      end

      # Each branch is limited too: the global first MAX_ROWS_PER_RUN rows are always within
      # each status's own first MAX_ROWS_PER_RUN, so this bounds a branch even if the planner
      # stops streaming the merge lazily.
      def scan_branches(lower, upper)
        ::Ai::DuoWorkflows::Workflow.billable_status_values.map do |status|
          ::Ai::DuoWorkflows::Workflow
            .where(status: status)
            .where(::Ai::DuoWorkflows::Workflow.arel_table[:updated_at].gt(lower))
            .where(updated_at: ..upper)
            .order(:updated_at, :id)
            .limit(MAX_ROWS_PER_RUN)
            .select(:id, :namespace_id, :project_id, :updated_at)
        end
      end
      # rubocop:enable CodeReuse/ActiveRecord

      def cursor
        @cursor ||= ::ClickHouse::SyncCursor.cursor_for(SYNC_CURSOR)
      end

      # Floored at the credit window: windows older than MAX_WINDOW_DAYS cannot
      # overlap the update that queued them.
      def cursor_time
        floor = SessionCredits::IngestService::MAX_WINDOW_DAYS.days.ago.to_i

        Time.zone.at([cursor, floor].max)
      end

      # A missing cursor used to read as epoch 0 and the first run scanned the whole
      # 90-day window (INC-13873). Now the first run only records where "now" is,
      # before any scan; ingestion starts with the next tick. Backfilling older
      # sessions is a deliberate console step: set the cursor to any non-zero epoch
      # second to resume from (floored at MAX_WINDOW_DAYS; 0 would only re-seed).
      def seed_cursor
        seed = SETTLE_HORIZON.ago.to_i
        ::ClickHouse::SyncCursor.update_cursor_for(SYNC_CURSOR, seed)

        ::Gitlab::AppLogger.info(
          Labkit::Fields::CLASS_NAME => self.class.name,
          Labkit::Fields::LOG_MESSAGE => 'Seeded session credits cursor'
        )
      end

      # Warn, not info: a latch that never clears means CustomersDot is down or the
      # kill switch is on, and either needs a human.
      def log_backoff(reason)
        ::Gitlab::AppLogger.warn(
          Labkit::Fields::CLASS_NAME => self.class.name,
          Labkit::Fields::LOG_MESSAGE => 'Skipping session credits cycle while backing off from CustomersDot',
          Labkit::Fields::ERROR_TYPE => reason.to_s
        )
      end

      # Returns the number of child jobs enqueued.
      def dispatch(rows)
        dispatched = 0

        unless saas?
          return dispatched unless ingestion_enabled_for?(nil)

          # Self-managed has one instance-level subscription keyed by license.
          rows.each_slice(MAX_IDS_PER_JOB) do |slice|
            FetchNamespaceSessionCreditsWorker.perform_async(nil, slice.map(&:id))
            dispatched += 1
          end

          return dispatched
        end

        roots = root_namespace_ids_for(rows)

        unresolved_count = rows.count { |row| roots[row.id].nil? }
        log_unresolved(unresolved_count) if unresolved_count > 0

        rows.group_by { |row| roots[row.id] }.each do |root_namespace_id, group|
          next unless root_namespace_id
          next unless ingestion_enabled_for?(root_namespace_id)

          group.each_slice(MAX_IDS_PER_JOB) do |slice|
            FetchNamespaceSessionCreditsWorker.perform_async(root_namespace_id, slice.map(&:id))
            dispatched += 1
          end
        end

        dispatched
      end

      # Sessions are scoped to EITHER a namespace or a project, and namespace_id may
      # be a subgroup while CustomersDot subscriptions are keyed at the root. Two
      # id-keyed plucks instead of one root_ancestor call per row.
      #
      # rubocop:disable CodeReuse/ActiveRecord -- see scan
      def root_namespace_ids_for(rows)
        project_ids = rows.filter_map(&:project_id).uniq
        project_namespaces = ::Project.id_in(project_ids).pluck(:id, :namespace_id).to_h

        namespace_ids = (rows.filter_map(&:namespace_id) + project_namespaces.values).uniq
        roots = ::Namespace.id_in(namespace_ids).pluck(:id, Arel.sql('traversal_ids[1]')).to_h

        rows.each_with_object({}) do |row, hash|
          namespace_id = row.namespace_id || project_namespaces[row.project_id]
          hash[row.id] = roots[namespace_id]
        end
      end
      # rubocop:enable CodeReuse/ActiveRecord

      # An unresolvable root (deleted namespace or project, empty traversal_ids) drops
      # the row while the cursor advances past it; without this the loss is invisible.
      def log_unresolved(count)
        ::Gitlab::AppLogger.warn(
          Labkit::Fields::CLASS_NAME => self.class.name,
          Labkit::Fields::LOG_MESSAGE => 'Skipped sessions with an unresolvable root namespace',
          :unresolved_count => count
        )
      end
    end
  end
end
