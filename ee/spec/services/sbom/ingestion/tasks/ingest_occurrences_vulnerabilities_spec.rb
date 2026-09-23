# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::Ingestion::Tasks::IngestOccurrencesVulnerabilities, feature_category: :dependency_management do
  describe '#execute' do
    let_it_be(:pipeline) { build(:ci_pipeline) }

    let!(:finding_1) do
      create(
        :vulnerabilities_finding,
        :detected,
        :with_dependency_scanning_metadata,
        project: pipeline.project,
        file: occurrence_map_1.input_file_path,
        package: occurrence_map_1.name,
        version: occurrence_map_1.version,
        pipeline: pipeline
      )
    end

    let!(:finding_2) do
      create(
        :vulnerabilities_finding,
        :detected,
        :with_dependency_scanning_metadata,
        project: pipeline.project,
        file: occurrence_map_2.input_file_path,
        package: occurrence_map_2.name,
        version: occurrence_map_2.version,
        pipeline: pipeline
      )
    end

    let(:occurrence_map_1) do
      create(:sbom_occurrence_map, :for_occurrence_ingestion, :with_occurrence)
    end

    let(:occurrence_map_2) do
      create(:sbom_occurrence_map, :for_occurrence_ingestion, :with_occurrence)
    end

    let(:occurrence_maps) { [occurrence_map_1, occurrence_map_2] }

    subject(:ingest_occurrences_vulnerabilities) do
      described_class.execute(pipeline, occurrence_maps)
    end

    before do
      occurrence_map_1.vulnerability_ids = [finding_1.vulnerability_id]
      occurrence_map_1.vulnerability_finding_ids_map = { finding_1.vulnerability_id => finding_1.id }
      occurrence_map_2.vulnerability_ids = [finding_2.vulnerability_id]
      occurrence_map_2.vulnerability_finding_ids_map = { finding_2.vulnerability_id => finding_2.id }
    end

    it_behaves_like 'bulk insertable task'

    it 'is idempotent' do
      expect { described_class.execute(pipeline, occurrence_maps) }
        .to change { Sbom::OccurrencesVulnerability.count }.by(2)
      expect { described_class.execute(pipeline, occurrence_maps) }
        .not_to change { Sbom::OccurrencesVulnerability.count }
    end

    describe 'attributes' do
      it 'sets the correct attributes for the occurrence' do
        ingest_occurrences_vulnerabilities

        expect(Sbom::OccurrencesVulnerability.all).to match_array([
          an_object_having_attributes('sbom_occurrence_id' => occurrence_map_2.occurrence_id,
            'vulnerability_id' => finding_2.vulnerability_id,
            'vulnerability_occurrence_id' => finding_2.id),
          an_object_having_attributes('sbom_occurrence_id' => occurrence_map_1.occurrence_id,
            'vulnerability_id' => finding_1.vulnerability_id,
            'vulnerability_occurrence_id' => finding_1.id)
        ])
      end
    end

    context 'when there is an existing occurrence' do
      let!(:existing_record) do
        create(:sbom_occurrences_vulnerability,
          sbom_occurrence_id: occurrence_map_1.occurrence_id,
          vulnerability_id: finding_1.vulnerability_id)
      end

      let(:expected_vulnerability_ids) { [finding_1.vulnerability_id, finding_2.vulnerability_id] }

      it 'does not create a new record for the existing occurrence' do
        expect { ingest_occurrences_vulnerabilities }.to change { Sbom::OccurrencesVulnerability.count }.by(1)
      end

      it_behaves_like 'it syncs vulnerabilities with ES',
        -> { expected_vulnerability_ids }, :ingest_occurrences_vulnerabilities

      context 'when the vulnerability_id was not ingested' do
        before do
          occurrence_map_1.vulnerability_ids = []
        end

        it 'deletes the record' do
          expect { ingest_occurrences_vulnerabilities }.to change {
            Sbom::OccurrencesVulnerability.exists?(existing_record.id)
          }.from(true).to(false)
        end

        context 'when there is another record with the same vulnerability_id' do
          let!(:other_record) do
            create(:sbom_occurrences_vulnerability,
              vulnerability_id: finding_1.vulnerability_id)
          end

          it 'does not delete the record' do
            expect { ingest_occurrences_vulnerabilities }.not_to change {
              Sbom::OccurrencesVulnerability.exists?(other_record.id)
            }.from(true)
          end
        end
      end
    end

    context 'when a finding id cannot be resolved for a vulnerability' do
      before do
        occurrence_map_1.vulnerability_finding_ids_map = {}
      end

      it 'still creates the link with a nil vulnerability_occurrence_id' do
        ingest_occurrences_vulnerabilities

        link = Sbom::OccurrencesVulnerability.find_by(
          sbom_occurrence_id: occurrence_map_1.occurrence_id,
          vulnerability_id: finding_1.vulnerability_id
        )

        expect(link).to be_present
        expect(link.vulnerability_occurrence_id).to be_nil
      end

      it 'logs that the link was created without a resolved vulnerability_occurrence_id' do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(
          hash_including(
            message: 'Sbom occurrence vulnerability link created without a resolved vulnerability_occurrence_id',
            sbom_occurrence_id: occurrence_map_1.occurrence_id,
            vulnerability_id: finding_1.vulnerability_id
          )
        )

        ingest_occurrences_vulnerabilities
      end
    end

    context 'when there is more than one vulnerability per occurrence' do
      before do
        finding = create(
          :vulnerabilities_finding,
          :detected,
          :with_dependency_scanning_metadata,
          project: pipeline.project,
          file: occurrence_map_1.input_file_path,
          package: occurrence_map_1.name,
          version: occurrence_map_1.version,
          pipeline: pipeline
        )
        occurrence_map_1.vulnerability_ids << finding.vulnerability_id
        occurrence_map_1.vulnerability_finding_ids_map[finding.vulnerability_id] = finding.id
      end

      it 'creates all related occurrences_vulnerabilities' do
        expect { ingest_occurrences_vulnerabilities }.to change { Sbom::OccurrencesVulnerability.count }.by(3)
      end
    end

    context 'when a link already exists with a nil vulnerability_occurrence_id' do
      let!(:existing_link) do
        create(:sbom_occurrences_vulnerability,
          sbom_occurrence_id: occurrence_map_1.occurrence_id,
          vulnerability_id: finding_1.vulnerability_id,
          project_id: pipeline.project.id,
          vulnerability_occurrence_id: nil)
      end

      # Existing rows are not re-processed by ingestion (they are excluded via
      # `new_links = ingested_links - existing_links`); backfilling their
      # vulnerability_occurrence_id is handled separately
      # by https://gitlab.com/gitlab-org/gitlab/-/work_items/602158, not here.
      it 'does not backfill the existing link during re-ingestion' do
        expect { ingest_occurrences_vulnerabilities }
          .not_to change { existing_link.reload.vulnerability_occurrence_id }.from(nil)
      end
    end

    context 'when there is no vulnerabilities' do
      let(:occurrence_map_3) { create(:sbom_occurrence_map, :for_occurrence_ingestion, :with_occurrence) }
      let(:occurrence_maps) { [occurrence_map_1, occurrence_map_2, occurrence_map_3] }

      it 'skips records without vulnerabilities' do
        expect { ingest_occurrences_vulnerabilities }.to change { Sbom::OccurrencesVulnerability.count }.by(2)
      end
    end

    describe 'elasticsearch synchronization' do
      let(:vulnerability_1) { finding_1.vulnerability }
      let(:vulnerability_2) { finding_2.vulnerability }

      context 'when there are associated vulnerabilities' do
        let(:expected_vulnerability_ids) { [vulnerability_1.id, vulnerability_2.id] }

        it_behaves_like 'it syncs vulnerabilities with ES',
          -> { expected_vulnerability_ids }, :ingest_occurrences_vulnerabilities
      end

      context 'when no vulnerabilities are returned' do
        let(:occurrence_maps) { [] }

        it_behaves_like 'does not sync with ES when no vulnerabilities', :ingest_occurrences_vulnerabilities
      end
    end
  end
end
