# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::VersionStatistics, feature_category: :artifact_registry do
  let(:attributes) { { 'files_count' => 12 } }

  subject(:statistics) { described_class.new(attributes) }

  describe '#files_count' do
    it 'exposes the count' do
      expect(statistics.files_count).to eq(12)
    end

    context 'when files_count is absent' do
      let(:attributes) { {} }

      it 'reads nil rather than raising' do
        expect(statistics.files_count).to be_nil
      end
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) do
      super().merge('size_bytes' => 987_654, 'last_downloaded_at' => '2026-07-04T00:00:00Z',
        'newly_added_ar_field' => 'x')
    end

    it 'exposes no reader for the Phase 8 fields this slice omits, nor for an unknown key',
      :aggregate_failures do
      expect(statistics.files_count).to eq(12)
      expect(statistics).not_to respond_to(:size_bytes)
      expect(statistics).not_to respond_to(:last_downloaded_at)
      expect(statistics).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:statistics) { described_class.new(nil) }

    it 'treats it as an empty resource without raising' do
      expect(statistics.files_count).to be_nil
    end
  end
end
