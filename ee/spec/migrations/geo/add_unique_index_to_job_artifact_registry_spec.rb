# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddUniqueIndexToJobArtifactRegistry, :geo, feature_category: :geo_replication do
  let(:registry) { table(:job_artifact_registry) }
  let(:connection) { registry.connection }

  describe '#up' do
    it 'replaces the non-unique index with a unique index' do
      migrate!

      expect(index(described_class::UNIQUE_INDEX_NAME).unique).to be(true)
      expect(index(described_class::OLD_INDEX_NAME)).to be_nil
    end

    it 'rejects duplicates and succeeds after cleanup and retry' do
      registry.create!(artifact_id: 1)
      duplicate = registry.create!(artifact_id: 1)

      expect { migrate! }.to raise_error(StandardError, /PG::UniqueViolation/)

      expect(index(described_class::OLD_INDEX_NAME)).to be_present
      expect(index(described_class::UNIQUE_INDEX_NAME).valid).to be(false)

      duplicate.delete
      migrate!

      expect(index(described_class::UNIQUE_INDEX_NAME).valid).to be(true)
      expect(index(described_class::UNIQUE_INDEX_NAME).unique).to be(true)
      expect(index(described_class::OLD_INDEX_NAME)).to be_nil
    end
  end

  describe '#down' do
    it 'restores the non-unique index before removing the unique index' do
      migrate!

      schema_migrate_down!

      expect(index(described_class::OLD_INDEX_NAME).unique).to be(false)
      expect(index(described_class::UNIQUE_INDEX_NAME)).to be_nil
    end
  end

  private

  def index(name)
    connection.indexes(:job_artifact_registry).find { |index| index.name == name }
  end
end
