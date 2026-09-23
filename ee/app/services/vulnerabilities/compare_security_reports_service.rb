# frozen_string_literal: true

module Vulnerabilities
  class CompareSecurityReportsService < ::Ci::CompareReportsBaseService
    extend ::Gitlab::Utils::Override

    def build_comparer(base_report, head_report)
      comparison_params = params.merge(
        base_report: base_report,
        head_report: head_report,
        partial_scan_scanner_ids: partial_scan_scanner_ids
      )
      comparer_class.new(project, comparison_params)
    end

    # For full scan comparisons where the head pipeline includes partial scans,
    # identify the scanners configured for partial scanning and filter out their
    # findings from the base pipeline. This prevents vulnerabilities detected by
    # those scanners in the base pipeline from incorrectly appearing as "fixed"
    # in the full scan tab, since they're already handled in the partial scan comparison.
    def partial_scan_scanner_ids
      return [] unless params[:scan_mode] == 'full'
      return [] if head_pipeline.nil?

      partial_scans = head_pipeline.security_scans.partial.to_a
      return Set.new if partial_scans.empty?

      build_type_pairs = partial_scans.map do |scan|
        file_type_value = ::Ci::JobArtifact.file_types[scan.scan_type]
        [scan.build_id, file_type_value]
      end

      artifacts = head_pipeline.job_artifacts
                               .security_reports_by_build_and_type_pairs(build_type_pairs)

      artifacts.filter_map do |artifact|
        artifact&.security_report&.scanner&.external_id
      end.to_set
    end

    def comparer_class
      Gitlab::Ci::Reports::Security::SecurityFindingsReportsComparer
    end

    def serializer_class
      Vulnerabilities::FindingDiffSerializer
    end

    def get_report(pipeline)
      return :parsing unless security_findings_stored?(pipeline)

      related_pipeline_ids = related_pipeline_ids_for(pipeline)

      findings = Security::FindingsFinder.new(
        pipeline,
        params: {
          report_type: params[:report_type],
          scope: 'all',
          scan_mode: scan_mode_for_pipeline(pipeline),
          limit: max_findings_count,
          related_pipeline_ids: related_pipeline_ids
        }
      ).execute.with_api_scopes

      findings_array = findings.to_a
      findings_array = findings_array.uniq(&:uuid) if related_pipeline_ids.present?
      Security::Finding.preload_auto_dismissal_checks!(project, findings_array)
      Security::Finding.preload_severity_override_checks!(project, findings_array)

      Gitlab::Ci::Reports::Security::AggregatedFinding.new(pipeline, findings_array)
    end

    def execute(base_pipeline, head_pipeline)
      @base_pipeline = base_pipeline
      @head_pipeline = head_pipeline
      super
    end

    private

    attr_reader :base_pipeline, :head_pipeline

    def max_findings_count
      if Feature.enabled?(:security_mr_reports_tab_full_data_set, project)
        Gitlab::Ci::Reports::Security::SecurityFindingsReportsComparer::MAX_FULL_DATA_SET_FINDINGS
      else
        Gitlab::Ci::Reports::Security::SecurityFindingsReportsComparer::MAX_FINDINGS_COUNT
      end
    end

    def scan_mode_for_pipeline(pipeline)
      # For partial scan comparisons, we want to compare full scan results from the base pipeline
      # against partial scan results from the head pipeline. This prevents existing vulnerabilities
      # from appearing as "new" when they're detected by partial scans on feature branches.
      if params[:scan_mode] == 'partial' && pipeline == base_pipeline
        'full'
      else
        params[:scan_mode]
      end
    end

    def security_findings_stored?(pipeline)
      return true if pipeline.nil?
      return false unless Security::Scan.results_ready?(pipeline, params[:report_type])

      !related_scans_processing?(pipeline)
    end

    def related_scans_processing?(pipeline)
      pipeline_ids = related_pipeline_ids_for(pipeline)
      return false if pipeline_ids.empty?

      Security::Scan
        .by_pipeline_ids(pipeline_ids)
        .by_scan_types(params[:report_type])
        .latest
        .processing
        .exists?
    end

    # Merge request approval policies and the security policy pipeline merge
    # check evaluate the latest pipelines of all sources for the head sha
    # (for example, both the branch pipeline and the merge request pipeline),
    # so the head report has to aggregate findings across the same set of
    # pipelines to match what those enforcement mechanisms report.
    # See https://gitlab.com/gitlab-org/gitlab/-/work_items/599102.
    def related_pipeline_ids_for(pipeline)
      return [] unless pipeline && pipeline == head_pipeline

      related_pipeline_ids(pipeline)
    end

    def related_pipeline_ids(pipeline)
      return [] unless Feature.enabled?(:security_report_related_pipelines, project)

      @related_pipeline_ids ||= {}
      @related_pipeline_ids[pipeline.id] ||=
        Security::RelatedPipelinesFinder.cached_ci_and_security_orchestration_pipeline_ids(pipeline)
    end

    # The cache key has to change when a new related pipeline completes for
    # the head sha, so cached comparisons are invalidated once, for example,
    # a branch pipeline for the same commit finishes after the merge request
    # pipeline.
    override :key
    def key(base_pipeline, head_pipeline)
      return super unless head_pipeline && Feature.enabled?(:security_report_related_pipelines, project)

      super + [related_pipeline_ids(head_pipeline).sort]
    end
  end
end
