# frozen_string_literal: true

module Security
  # Recognizes duo_workflow workload pipelines whose SHA matches the default
  # branch HEAD, letting their security findings ingest into the Vulnerability Report.
  module AgenticAnalyzer
    module_function

    def default_branch_scan?(pipeline)
      project = pipeline.project
      return false unless pipeline.workload? && pipeline.source.to_sym == :duo_workflow && enabled?(project)

      Gitlab::SafeRequestStore.fetch([:agentic_analyzer_default_branch_scan, pipeline.id]) do
        default_sha = project.commit(project.default_branch)&.id
        default_sha.present? && pipeline.sha == default_sha
      end
    end

    def enabled?(project)
      Feature.enabled?(:agentic_analyzer_security_ingestion, project)
    end
    private_class_method :enabled?
  end
end
