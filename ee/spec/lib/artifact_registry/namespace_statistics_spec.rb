# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::NamespaceStatistics, feature_category: :artifact_registry do
  let(:attributes) { { 'repositories_count' => 7, 'deduplicated_size_bytes' => 987_654 } }

  subject(:statistics) { described_class.new(attributes) }

  describe '#repositories_count' do
    it 'exposes the count' do
      expect(statistics.repositories_count).to eq(7)
    end

    context 'when repositories_count is absent' do
      let(:attributes) { {} }

      it 'reads nil rather than raising' do
        expect(statistics.repositories_count).to be_nil
      end
    end
  end

  describe '#deduplicated_size_bytes' do
    it 'exposes the byte figure' do
      expect(statistics.deduplicated_size_bytes).to eq(987_654)
    end

    context 'when deduplicated_size_bytes is absent' do
      let(:attributes) { {} }

      it 'reads nil rather than raising' do
        expect(statistics.deduplicated_size_bytes).to be_nil
      end
    end

    context 'when the stored counter underflowed' do
      let(:attributes) { super().merge('deduplicated_size_bytes' => -2048) }

      it 'passes the negative through, since AR declares no floor on this figure' do
        expect(statistics.deduplicated_size_bytes).to eq(-2048)
      end
    end
  end

  context 'when every figure is zero, the response for a namespace with no repositories' do
    let(:attributes) { { 'repositories_count' => 0, 'deduplicated_size_bytes' => 0 } }

    it 'reads the zeros rather than treating them as absences', :aggregate_failures do
      expect(statistics.repositories_count).to eq(0)
      expect(statistics.deduplicated_size_bytes).to eq(0)
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) do
      super().merge('components_count' => 42, 'downloads_count' => 0, 'newly_added_ar_field' => 'x')
    end

    it 'exposes no reader for the two consumerless contract fields, nor for an unknown key',
      :aggregate_failures do
      expect(statistics.repositories_count).to eq(7)
      expect(statistics).not_to respond_to(:components_count)
      expect(statistics).not_to respond_to(:downloads_count)
      expect(statistics).not_to respond_to(:newly_added_ar_field)
    end
  end

  context 'when constructed with nil attributes' do
    subject(:statistics) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(statistics.repositories_count).to be_nil
      expect(statistics.deduplicated_size_bytes).to be_nil
    end
  end
end
