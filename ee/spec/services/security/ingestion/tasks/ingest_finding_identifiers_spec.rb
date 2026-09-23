# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::Tasks::IngestFindingIdentifiers, feature_category: :vulnerability_management do
  describe '#execute' do
    let(:pipeline) { create(:ci_pipeline) }
    let(:identifier) { create(:vulnerabilities_identifier) }
    let(:finding_1) { create(:vulnerabilities_finding) }
    let(:finding_2) { create(:vulnerabilities_finding) }
    let(:finding_map_1) { create(:finding_map, finding: finding_1, identifier_ids: [identifier.id]) }
    let(:finding_map_2) { create(:finding_map, finding: finding_2, identifier_ids: [identifier.id]) }
    let(:service_object) { described_class.new(pipeline, [finding_map_1, finding_map_2]) }

    subject(:ingest_finding_identifiers) { service_object.execute }

    before do
      finding_1.identifiers << identifier
    end

    it 'associates findings with the identifiers' do
      expect { ingest_finding_identifiers }.to change { Vulnerabilities::FindingIdentifier.count }.by(1)
                                           .and change { finding_2.reload.identifiers }.from([]).to([identifier])
    end

    it 'does not rewrite the rows that already exist' do
      existing = Vulnerabilities::FindingIdentifier.find_by(occurrence_id: finding_1.id, identifier_id: identifier.id)
      existing.update!(updated_at: 1.week.ago)
      before = existing.reload.updated_at

      ingest_finding_identifiers

      expect(existing.reload.updated_at).to eq(before)
    end

    it_behaves_like 'bulk insertable task'
  end
end
