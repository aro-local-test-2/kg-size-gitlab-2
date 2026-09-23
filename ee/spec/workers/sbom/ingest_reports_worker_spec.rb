# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::IngestReportsWorker, feature_category: :dependency_management do
  let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_report) }

  describe 'deferring on database health' do
    it 'watches the high-churn sbom tables on the sec database' do
      expect(described_class.database_health_check_attrs).to include(
        gitlab_schema: :gitlab_sec,
        tables: %w[sbom_occurrences sbom_occurrence_refs sbom_occurrences_vulnerabilities],
        delay_by: 5.minutes
      )
    end

    it 'defers when the feature flag is enabled' do
      expect(described_class.defer_on_database_health_signal?).to be(true)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(defer_sbom_ingest_reports_on_database_health: false)
      end

      it 'does not defer' do
        expect(described_class.defer_on_database_health_signal?).to be(false)
      end
    end
  end

  describe '#perform' do
    subject(:run_worker) { described_class.new.perform(pipeline.id) }

    before do
      allow(Sbom::Ingestion::IngestReportsService).to receive(:execute)
    end

    context 'when there is no pipeline with the given ID' do
      subject(:perform) { described_class.new.perform(non_existing_record_id) }

      it 'does not raise an error' do
        expect { perform }.not_to raise_error
      end
    end

    it 'calls `Sbom::Ingestion::IngestReportsService`' do
      run_worker

      expect(Sbom::Ingestion::IngestReportsService).to have_received(:execute)
    end
  end
end
