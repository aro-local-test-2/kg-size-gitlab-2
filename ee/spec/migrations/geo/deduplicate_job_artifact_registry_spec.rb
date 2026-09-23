# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe DeduplicateJobArtifactRegistry, :geo, feature_category: :geo_replication do
  let(:registry) { table(:job_artifact_registry) }

  describe '#up' do
    it 'keeps the synced record over a newer unsynced record' do
      synced_duplicate = create_registry(artifact_id: 1, state: 2)
      newer_pending_duplicate = create_registry(artifact_id: 1, state: 0)
      unique_record = create_registry(artifact_id: 2)

      migrate!

      expect(registry.pluck(:id)).to contain_exactly(synced_duplicate.id, unique_record.id)
      expect(registry.where(id: newer_pending_duplicate.id)).not_to exist
      expect(synced_duplicate.reload.state).to eq(2)
    end

    it 'keeps the record with the highest ID when no duplicate is synced' do
      create_registry(artifact_id: 1, state: 0)
      kept_duplicate = create_registry(artifact_id: 1, state: 3)

      migrate!

      expect(registry.where(artifact_id: 1).pluck(:id)).to contain_exactly(kept_duplicate.id)
    end

    it 'keeps the synced record with the highest ID when multiple duplicates are synced' do
      create_registry(artifact_id: 1, state: 2)
      kept_duplicate = create_registry(artifact_id: 1, state: 2)
      create_registry(artifact_id: 1, state: 0)

      migrate!

      expect(registry.where(artifact_id: 1).pluck(:id)).to contain_exactly(kept_duplicate.id)
    end

    it 'removes duplicates that span batch boundaries' do
      create_registry(id: 1, artifact_id: 1)
      kept_record = create_registry(id: described_class::BATCH_SIZE + 1, artifact_id: 1)

      migrate!

      expect(registry.where(artifact_id: 1).pluck(:id)).to contain_exactly(kept_record.id)
    end

    it 'preserves all records when there are no duplicates' do
      records = [create_registry(artifact_id: 1), create_registry(artifact_id: 2)]

      expect { migrate! }.not_to change { registry.count }
      expect(registry.pluck(:id)).to match_array(records.map(&:id))
    end

    it 'runs safely when the table is empty' do
      expect { migrate! }.not_to change { registry.count }.from(0)
    end

    it 'is idempotent' do
      deleted_record = create_registry(artifact_id: 1)
      create_registry(artifact_id: 1)

      migrate!

      expect { with_db_config { described_class.new.up } }.not_to change { registry.pluck(:id) }
      expect(registry.where(artifact_id: 1).pluck(:id)).to contain_exactly(registry.maximum(:id))
      expect(registry.where(id: deleted_record.id)).not_to exist
    end
  end

  describe '#down' do
    it 'does not restore deleted records' do
      create_registry(artifact_id: 1)
      create_registry(artifact_id: 1)
      migrate!

      expect { schema_migrate_down! }.not_to change { registry.count }.from(1)
    end
  end

  private

  def create_registry(**attributes)
    registry.create!({ artifact_id: 1, state: 0 }.merge(attributes))
  end
end
