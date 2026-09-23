# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::Tasks::IngestIdentifiers, feature_category: :vulnerability_management do
  describe '#execute' do
    let_it_be(:pipeline) { create(:ci_pipeline) }

    let(:existing_fingerprint) { Digest::SHA1.hexdigest('type:id') }
    let(:vulnerability_identifier) { create(:vulnerabilities_identifier, project: pipeline.project, fingerprint: existing_fingerprint, name: 'bar') }
    let(:existing_report_identifier) { create(:ci_reports_security_identifier, external_id: 'id', external_type: 'type') }
    let(:extra_identifiers) { Array.new(21) { |index| create(:ci_reports_security_identifier, external_id: "id-#{index}", external_type: 'type') } }
    let(:identifiers) { extra_identifiers.unshift(existing_report_identifier) }
    let(:expected_fingerprints) { Array.new(19) { |index| Digest::SHA1.hexdigest("type:id-#{index}") }.unshift(existing_fingerprint).sort }

    let(:report_finding) { create(:ci_reports_security_finding, identifiers: identifiers) }
    let(:finding_map) { create(:finding_map, report_finding: report_finding, pipeline: pipeline) }
    let(:service_object) { described_class.new(pipeline, [finding_map]) }
    let(:project_identifiers) { pipeline.project.vulnerability_identifiers }
    let(:unchanged_identifier) do
      create(:vulnerabilities_identifier,
        project: pipeline.project,
        fingerprint: Digest::SHA1.hexdigest('type:id-0'),
        external_type: 'type',
        external_id: 'id-0',
        name: 'type-id-0',
        url: nil)
    end

    subject(:ingest_identifiers) { service_object.execute }

    it 'creates new records and updates the existing ones' do
      expect { ingest_identifiers }.to change { project_identifiers.count }.from(1).to(20)
                                   .and change { vulnerability_identifier.reload.name }
    end

    it 'sets the identifier_ids for the finding_map object' do
      expect { ingest_identifiers }.to(
        change { project_identifiers.where(id: finding_map.identifier_ids).pluck(:fingerprint).sort }
          .from([])
          .to(expected_fingerprints))
    end

    context 'when an identifier already exists unchanged' do
      before do
        unchanged_identifier.update!(updated_at: 1.week.ago)
      end

      it 'does not rewrite it' do
        was = unchanged_identifier.reload.updated_at

        ingest_identifiers

        expect(unchanged_identifier.reload.updated_at).to eq(was)
      end

      it 'still resolves its id onto the finding map' do
        ingest_identifiers

        expect(finding_map.identifier_ids).to include(unchanged_identifier.id)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        unchanged_identifier.update!(updated_at: 1.week.ago)
        stub_feature_flags(skip_unchanged_vulnerability_identifiers: false)
      end

      it 'rewrites unchanged identifiers too' do
        expect { ingest_identifiers }.to change { unchanged_identifier.reload.updated_at }
      end
    end

    it 'upserts the identifiers in controlled batches' do
      expect(described_class.klass).to receive(:bulk_upsert!)
        .with(anything, hash_including(batch_size: 50))
        .and_call_original

      ingest_identifiers
    end

    context 'when the identifiers span multiple insert batches' do
      before do
        vulnerability_identifier
        allow(described_class).to receive(:batch_size).and_return(3)
      end

      it 'creates all records and sets the identifier_ids for the finding_map object' do
        expect { ingest_identifiers }.to change { project_identifiers.count }.from(1).to(20)
          .and change { project_identifiers.where(id: finding_map.identifier_ids).pluck(:fingerprint).sort }
            .from([])
            .to(expected_fingerprints)
      end
    end

    context 'with multiple projects' do
      let_it_be(:other_pipeline) { create(:ci_pipeline) }

      let(:identifiers) { Array.new(10) { |index| create(:ci_reports_security_identifier, external_id: "id-#{index}", external_type: 'type') } }
      let(:other_finding_map) { create(:finding_map, report_finding: report_finding, pipeline: other_pipeline) }
      let(:service_object) { described_class.new(nil, [finding_map, other_finding_map]) }
      let(:other_project_identifiers) { other_pipeline.project.vulnerability_identifiers }

      it 'creates records for multiple projects' do
        expect { ingest_identifiers }.to change { project_identifiers.count }.from(0).to(10)
          .and change { other_project_identifiers.count }.from(0).to(10)
      end
    end

    context 'when two projects hold the same fingerprint' do
      let_it_be(:other_pipeline) { create(:ci_pipeline) }

      let(:shared_fingerprint) { Digest::SHA1.hexdigest('type:id-0') }
      let(:identifiers) { [create(:ci_reports_security_identifier, external_id: 'id-0', external_type: 'type')] }
      let(:other_finding_map) { create(:finding_map, report_finding: report_finding, pipeline: other_pipeline) }
      let(:service_object) { described_class.new(pipeline, [finding_map, other_finding_map]) }

      let(:changed_in_other_project) do
        create(:vulnerabilities_identifier,
          project: other_pipeline.project,
          fingerprint: shared_fingerprint,
          external_type: 'type',
          external_id: 'id-0',
          name: 'stale name',
          url: nil)
      end

      before do
        unchanged_identifier.update!(updated_at: 1.week.ago)
        changed_in_other_project.update!(updated_at: 1.week.ago)
      end

      # A lookup that did not group by project would compare each row against the other
      # project's attributes, so the unchanged row would look changed and get rewritten.
      it 'compares each project against its own row' do
        was = unchanged_identifier.reload.updated_at

        ingest_identifiers

        expect(unchanged_identifier.reload.updated_at).to eq(was)
        expect(changed_in_other_project.reload.name).to eq('type-id-0')
      end

      it 'resolves each project id onto its own finding map' do
        ingest_identifiers

        expect(finding_map.identifier_ids).to eq([unchanged_identifier.id])
        expect(other_finding_map.identifier_ids).to eq([changed_in_other_project.id])
      end
    end

    it_behaves_like 'bulk insertable task'
  end
end
