# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::UpstreamRepositoryAssociation, feature_category: :artifact_registry do
  let(:summary_attributes) do
    {
      'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
      'name' => 'payment-core',
      'format' => 'maven',
      'kind' => 'hosted'
    }
  end

  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'position' => 1,
      'upstream_repository' => summary_attributes
    }
  end

  subject(:association) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes the association id and position', :aggregate_failures do
      expect(association.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(association.position).to eq(1)
    end

    it 'wraps the upstream repository in a summary value object', :aggregate_failures do
      summary = association.upstream_repository

      expect(summary).to be_a(ArtifactRegistry::UpstreamRepositorySummary)
      expect(summary.id).to eq('b2c3d4e5-0000-0000-0000-000000000000')
      expect(summary.name).to eq('payment-core')
      expect(summary.format).to eq('maven')
      expect(summary.kind).to eq('hosted')
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('created_at' => '2026-07-03T09:15:00Z', 'newly_added_ar_field' => 'x') }

    it 'defines no reader for fields nothing renders yet, nor for unknown keys', :aggregate_failures do
      expect(association.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(association).not_to respond_to(:created_at)
      expect(association).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for the absent scalars without raising', :aggregate_failures do
      expect(association.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(association.position).to be_nil
    end

    it 'still returns an empty summary rather than nil when the upstream is absent', :aggregate_failures do
      summary = association.upstream_repository

      expect(summary).to be_a(ArtifactRegistry::UpstreamRepositorySummary)
      expect(summary.id).to be_nil
      expect(summary.name).to be_nil
    end
  end

  describe 'when the upstream repository is not an object' do
    let(:attributes) { super().merge('upstream_repository' => 'not-a-hash') }

    it 'returns an empty summary rather than raising', :aggregate_failures do
      summary = association.upstream_repository

      expect(summary).to be_a(ArtifactRegistry::UpstreamRepositorySummary)
      expect(summary.id).to be_nil
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:association) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(association.id).to be_nil
      expect(association.position).to be_nil
      expect(association.upstream_repository).to be_a(ArtifactRegistry::UpstreamRepositorySummary)
    end
  end
end
