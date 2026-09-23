# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::UpstreamRepositorySummary, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'payment-core',
      'format' => 'maven',
      'kind' => 'hosted'
    }
  end

  subject(:summary) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes every documented field', :aggregate_failures do
      expect(summary.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(summary.name).to eq('payment-core')
      expect(summary.format).to eq('maven')
      expect(summary.kind).to eq('hosted')
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('visibility' => 'private', 'newly_added_ar_field' => 'x') }

    it 'defines no reader for fields nothing renders yet, nor for unknown keys', :aggregate_failures do
      expect(summary.name).to eq('payment-core')
      expect(summary).not_to respond_to(:visibility)
      expect(summary).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising', :aggregate_failures do
      expect(summary.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(summary.name).to be_nil
      expect(summary.format).to be_nil
      expect(summary.kind).to be_nil
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:summary) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(summary.id).to be_nil
      expect(summary.name).to be_nil
      expect(summary.format).to be_nil
      expect(summary.kind).to be_nil
    end
  end
end
