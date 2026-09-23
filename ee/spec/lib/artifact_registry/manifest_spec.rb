# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Manifest, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'digest' => 'sha256:aaaa',
      'media_type' => 'application/vnd.oci.image.manifest.v1+json',
      'artifact_type' => 'application/vnd.example.sbom',
      'subject_digest' => 'sha256:bbbb',
      'size' => 1024,
      'created_at' => '2026-07-03T09:15:00Z'
    }
  end

  subject(:manifest) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes every documented field, with created_at parsed', :aggregate_failures do
      expect(manifest.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(manifest.digest).to eq('sha256:aaaa')
      expect(manifest.media_type).to eq('application/vnd.oci.image.manifest.v1+json')
      expect(manifest.artifact_type).to eq('application/vnd.example.sbom')
      expect(manifest.subject_digest).to eq('sha256:bbbb')
      expect(manifest.size).to eq(1024)
      expect(manifest.created_at).to eq(DateTime.iso8601('2026-07-03T09:15:00Z'))
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('last_downloaded_at' => '2026-07-04T00:00:00Z', 'newly_added_ar_field' => 'x') }

    it 'defines no reader for the contract fields nothing renders yet, nor for unknown keys',
      :aggregate_failures do
      expect(manifest.digest).to eq('sha256:aaaa')
      expect(manifest).not_to respond_to(:last_downloaded_at)
      expect(manifest).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'the nullable fields' do
    let(:attributes) { super().merge('artifact_type' => nil, 'subject_digest' => nil) }

    it 'exposes nil for a manifest with no artifact type or subject, which the contract sends as JSON null',
      :aggregate_failures do
      expect(manifest.artifact_type).to be_nil
      expect(manifest.subject_digest).to be_nil
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising', :aggregate_failures do
      expect(manifest.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(manifest.digest).to be_nil
      expect(manifest.media_type).to be_nil
      expect(manifest.artifact_type).to be_nil
      expect(manifest.subject_digest).to be_nil
      expect(manifest.size).to be_nil
      expect(manifest.created_at).to be_nil
    end
  end

  describe 'the preview readers' do
    let(:attributes) do
      super().merge(
        'tags_preview' => %w[latest v1],
        'parents_preview' => ['sha256:parent'],
        'children_preview' => [
          { 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
        ]
      )
    end

    it 'exposes the previews the list row carries', :aggregate_failures do
      expect(manifest.tags_preview).to eq(%w[latest v1])
      expect(manifest.parents_preview).to eq(['sha256:parent'])
      expect(manifest.children_preview).to eq(
        [{ 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }]
      )
    end

    context 'when the previews carry malformed entries' do
      let(:attributes) do
        super().merge(
          'tags_preview' => ['latest', 123],
          'parents_preview' => ['sha256:parent', { 'not' => 'a string' }],
          'children_preview' => [{ 'digest' => 'sha256:child' }, 'oops', { 'architecture' => 'amd64' }]
        )
      end

      it 'drops the malformed entries, keeping the non-null-element contract intact', :aggregate_failures do
        expect(manifest.tags_preview).to eq(['latest'])
        expect(manifest.parents_preview).to eq(['sha256:parent'])
        expect(manifest.children_preview).to eq([{ 'digest' => 'sha256:child' }])
      end
    end

    context 'when a preview key is absent' do
      let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

      it 'returns nil for each, distinct from an empty array', :aggregate_failures do
        expect(manifest.tags_preview).to be_nil
        expect(manifest.parents_preview).to be_nil
        expect(manifest.children_preview).to be_nil
      end
    end

    context 'when a preview key is present but empty' do
      let(:attributes) do
        super().merge('tags_preview' => [], 'parents_preview' => [], 'children_preview' => [])
      end

      it 'returns an empty array, distinct from an absent key', :aggregate_failures do
        expect(manifest.tags_preview).to eq([])
        expect(manifest.parents_preview).to eq([])
        expect(manifest.children_preview).to eq([])
      end
    end

    context 'when a preview key is not an array' do
      let(:attributes) do
        super().merge('tags_preview' => 'nope', 'parents_preview' => {}, 'children_preview' => 42)
      end

      it 'coerces each to nil without raising', :aggregate_failures do
        expect(manifest.tags_preview).to be_nil
        expect(manifest.parents_preview).to be_nil
        expect(manifest.children_preview).to be_nil
      end
    end
  end

  describe 'timestamp coercion' do
    context 'when created_at is not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp') }

      it 'coerces to nil without raising' do
        expect(manifest.created_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:manifest) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(manifest.id).to be_nil
      expect(manifest.digest).to be_nil
      expect(manifest.created_at).to be_nil
    end
  end
end
