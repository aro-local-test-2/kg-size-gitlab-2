# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Authz::ArtifactRegistry::Roles, feature_category: :system_access do
  before do
    allow(Gitlab::Glaz).to receive(:roles).and_return(
      [
        { id: '019ed9d4-7d53-7b5c-8653-1ceac0c48b14', name: 'Artifact Viewer', permissions: [] },
        { id: '019ed9d4-7d50-7249-9baa-52594d2d645b', name: 'Artifact Admin', permissions: [] },
        { id: '019ed9d7-920d-72eb-a0ff-117122219c2a', name: 'Organization Administrator', permissions: [] }
      ]
    )
  end

  # ids_by_name/names_by_id memoize into class-level ivars with no
  # invalidation. RSpec runs many files in one process, so a memoized map
  # built from this spec's incomplete stub (3 of 5 roles) would otherwise
  # leak into every later spec calling uuid_for/name_for on the real data.
  after do
    described_class.instance_variable_set(:@ids_by_name, nil)
    described_class.instance_variable_set(:@names_by_id, nil)
  end

  describe '.uuid_for' do
    it 'returns the UUID for a known role' do
      expect(described_class.uuid_for(:artifact_viewer)).to eq('019ed9d4-7d53-7b5c-8653-1ceac0c48b14')
    end

    it 'is case-insensitive' do
      expect(described_class.uuid_for('ARTIFACT_VIEWER')).to eq(described_class.uuid_for(:artifact_viewer))
    end

    it 'returns nil for an unknown role' do
      expect(described_class.uuid_for(:not_a_role)).to be_nil
    end

    it 'resolves the organization_admin platform role, keyed by its display name' do
      expect(described_class.uuid_for(:organization_admin)).to eq('019ed9d7-920d-72eb-a0ff-117122219c2a')
    end
  end

  describe '.name_for' do
    it 'returns the role name for a known id' do
      expect(described_class.name_for('019ed9d4-7d53-7b5c-8653-1ceac0c48b14')).to eq(:artifact_viewer)
    end

    it 'round-trips with uuid_for' do
      expect(described_class.name_for(described_class.uuid_for(:artifact_admin))).to eq(:artifact_admin)
    end

    it 'returns nil for an unknown id' do
      expect(described_class.name_for('00000000-0000-7000-8000-000000000000')).to be_nil
    end
  end
end
