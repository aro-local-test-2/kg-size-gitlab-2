# frozen_string_literal: true

# Worker for storing security reports into the database.
#
module Security
  class StoreSecurityReportsByProjectWorker
    include ApplicationWorker
    include SecurityScansQueue

    data_consistency :always
    sidekiq_options retry: 3
    feature_category :vulnerability_management
    worker_resource_boundary :memory

    idempotent!
    # until_executing released the lock when the job started, so two jobs for the same project
    # could execute together and contend on the same (project_id, fingerprint) rows. perform
    # resolves the latest pipeline at run time, so coalescing a duplicate loses nothing.
    deduplicate :until_executed, if_deduplicated: :reschedule_once

    # Bounds how many ingestions can run at once, so they don't all contend on the same
    # heavily-indexed sec tables together (see defer_on_database_health_signal below).
    concurrency_limit -> { 200 }

    # Ordered by index count -- every index is maintained on write, so heavily-indexed tables are
    # the ones whose autovacuum competes with ingestion for WAL bandwidth. This is the intersection
    # of the ingestion write path with the sec tables observed accruing the most dead tuples.
    defer_on_database_health_signal :gitlab_sec, [
      ::Vulnerabilities::Read.table_name,
      ::Vulnerabilities::Finding.table_name,
      ::Vulnerability.table_name,
      ::Vulnerabilities::Identifier.table_name,
      ::Security::FindingEnrichment.table_name,
      ::Vulnerabilities::FindingIdentifier.table_name
    ], 5.minutes

    def self.defer_on_database_health_signal?
      # rubocop:disable Gitlab/FeatureFlagWithoutActor -- fleet-wide throttle, no actor in scope
      Feature.enabled?(:defer_store_security_reports_on_database_health)
      # rubocop:enable Gitlab/FeatureFlagWithoutActor
    end

    def self.cache_key(project_id: nil)
      return unless project_id.present?

      "#{name}::latest_pipeline_with_security_reports::#{project_id}"
    end

    def perform(project_id)
      project = Project.find_by_id(project_id)
      return unless project&.can_store_security_reports?

      pipeline = latest_pipeline_with_security_reports(project.id)

      # Technically possible since this is an async job and pipelines
      # can be deleted between when this job was scheduled and
      # run;very unlikely
      return unless pipeline

      ::Security::Ingestion::IngestReportsService.execute(pipeline)
      SecretDetection::GitlabTokenVerificationWorker.perform_async(pipeline.id)
    end

    private

    def latest_pipeline_with_security_reports(project_id)
      self.class.cache_key(project_id: project_id)
        .then { |cache_key| Gitlab::Redis::SharedState.with { |redis| redis.get(cache_key) } }
        # not strictly necessary, but to prevent coercing nil to id 0
        .then { |pipeline_id_string| pipeline_id_string.blank? ? nil : pipeline_id_string.to_i }
        .then { |pipeline_id| Ci::Pipeline.find_by_id(pipeline_id) }
    end
  end
end
