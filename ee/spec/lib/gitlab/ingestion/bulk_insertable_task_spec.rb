# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ingestion::BulkInsertableTask do
  describe '.on_conflict' do
    let(:pipeline) { create(:ci_pipeline) }
    let(:identifier) { create(:vulnerabilities_identifier) }
    let(:finding) { create(:vulnerabilities_finding) }
    let(:finding_map) { create(:finding_map, finding: finding, identifier_ids: [identifier.id]) }
    let(:task) do
      Class.new(Security::Ingestion::AbstractTask) do
        include Gitlab::Ingestion::BulkInsertableTask

        self.model = Vulnerabilities::FindingIdentifier
        self.unique_by = %i[occurrence_id identifier_id].freeze
        self.on_conflict = :nothing

        def attributes
          finding_maps.flat_map do |finding_map|
            finding_map.identifier_ids.map do |identifier_id|
              { occurrence_id: finding_map.finding_id, identifier_id: identifier_id }
            end
          end
        end
      end
    end

    it 'still inserts rows that do not conflict' do
      expect { task.new(pipeline, [finding_map]).execute }
        .to change { Vulnerabilities::FindingIdentifier.count }.by(1)
    end

    it 'leaves a conflicting row untouched instead of rewriting it' do
      task.new(pipeline, [finding_map]).execute
      row = Vulnerabilities::FindingIdentifier.find_by(occurrence_id: finding.id, identifier_id: identifier.id)
      row.update!(updated_at: 1.week.ago)
      unchanged = row.reload.updated_at

      expect { task.new(pipeline, [finding_map]).execute }
        .not_to change { Vulnerabilities::FindingIdentifier.count }

      expect(row.reload.updated_at).to eq(unchanged)
    end

    it 'rejects any other value, so a typo cannot fall through to DO UPDATE' do
      expect do
        Class.new(Security::Ingestion::AbstractTask) do
          include Gitlab::Ingestion::BulkInsertableTask

          self.on_conflict = :noting
        end
      end.to raise_error(ArgumentError, /on_conflict must be one of/)
    end
  end

  describe '.unique_by' do
    let(:pipeline) { create(:ci_pipeline) }
    let(:identifier_1) { create(:vulnerabilities_identifier) }
    let(:identifier_2) { create(:vulnerabilities_identifier) }
    let(:finding) { create(:vulnerabilities_finding) }
    let(:identifier_ids) { [identifier_1.id, identifier_1.id, identifier_2.id] }
    let(:finding_map) { create(:finding_map, finding: finding, identifier_ids: identifier_ids) }
    let(:task) do
      Class.new(Security::Ingestion::AbstractTask) do
        include Gitlab::Ingestion::BulkInsertableTask

        self.model = Class.new(SecApplicationRecord) do
          self.table_name = 'vulnerability_occurrence_identifiers'
        end
        self.unique_by = %i[occurrence_id identifier_id].freeze

        def attributes
          finding_maps.flat_map do |finding_map|
            finding_map.identifier_ids.map do |identifier_id|
              {
                occurrence_id: finding_map.finding_id,
                identifier_id: identifier_id
              }
            end
          end
        end
      end
    end

    let(:service_object) { task.new(pipeline, [finding_map]) }

    it 'does not try to create/update duplicate records' do
      expect { service_object.execute }.to change { finding.identifiers.count }.by(2)
    end
  end
end
