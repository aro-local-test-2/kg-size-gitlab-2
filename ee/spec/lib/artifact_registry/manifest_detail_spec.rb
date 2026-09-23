# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::ManifestDetail, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'digest' => 'sha256:aaaa',
      'media_type' => 'application/vnd.oci.image.index.v1+json',
      'artifact_type' => 'application/vnd.example.sbom',
      'subject_digest' => 'sha256:bbbb',
      'size' => 4096,
      'created_at' => '2026-07-03T09:15:00Z',
      'architecture' => 'amd64',
      'os' => 'linux',
      'os_variant' => 'v8',
      'tags' => %w[latest 1.2.3],
      'tags_count' => 2,
      'children' => [
        { 'digest' => 'sha256:cccc', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
      ],
      'children_count' => 1,
      'parent_digests' => ['sha256:dddd'],
      'parents_count' => 1,
      'referrers_count' => 3,
      'annotations' => { 'org.opencontainers.image.title' => 'demo' }
    }
  end

  subject(:detail) { described_class.new(attributes) }

  # The shared readers, timestamp coercion, and nil-constructor behavior are inherited from
  # Manifest and covered by manifest_spec. This spec covers only the detail-only readers and the
  # collection-shape and nil-vs-empty semantics they add.
  it { is_expected.to be_a(ArtifactRegistry::Manifest) }

  describe 'detail-only readers' do
    it 'exposes the fields the list element does not carry', :aggregate_failures do
      expect(detail.architecture).to eq('amd64')
      expect(detail.os).to eq('linux')
      expect(detail.os_variant).to eq('v8')
      expect(detail.tags).to eq(%w[latest 1.2.3])
      expect(detail.tags_count).to eq(2)
      expect(detail.children_count).to eq(1)
      expect(detail.parent_digests).to eq(['sha256:dddd'])
      expect(detail.parents_count).to eq(1)
      expect(detail.referrers_count).to eq(3)
    end

    it 'passes children through as the platform-triple objects the contract carries' do
      expect(detail.children).to eq(
        [{ 'digest' => 'sha256:cccc', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }]
      )
    end

    it 'passes annotations through as the pushed map' do
      expect(detail.annotations).to eq({ 'org.opencontainers.image.title' => 'demo' })
    end
  end

  describe 'the null-versus-empty distinctions the contract keeps apart' do
    context 'when annotations carried an empty map' do
      let(:attributes) { super().merge('annotations' => {}) }

      it 'reads an empty Hash, not nil' do
        expect(detail.annotations).to eq({})
      end
    end

    context 'when the annotations key was absent' do
      let(:attributes) { super().except('annotations') }

      it 'reads nil, not an empty Hash' do
        expect(detail.annotations).to be_nil
      end
    end

    context 'when an array carried an empty list' do
      let(:attributes) { super().merge('tags' => [], 'children' => [], 'parent_digests' => []) }

      it 'reads an empty Array, distinct from an absent key', :aggregate_failures do
        expect(detail.tags).to eq([])
        expect(detail.children).to eq([])
        expect(detail.parent_digests).to eq([])
      end
    end

    context 'when an array key was absent' do
      let(:attributes) { super().except('tags', 'children', 'parent_digests') }

      it 'reads nil, distinct from an empty list', :aggregate_failures do
        expect(detail.tags).to be_nil
        expect(detail.children).to be_nil
        expect(detail.parent_digests).to be_nil
      end
    end
  end

  describe 'the platform triple, nullable per value rather than as a unit' do
    # Null each part on its own and assert the other two still read, so the per-value contract is
    # proven rather than demonstrated on one value.
    where(:null_field, :architecture, :os, :os_variant) do
      'architecture' | nil     | 'linux' | 'v8'
      'os'           | 'amd64' | nil     | 'v8'
      'os_variant'   | 'amd64' | 'linux' | nil
    end

    with_them do
      let(:attributes) do
        super().merge('architecture' => architecture, 'os' => os, 'os_variant' => os_variant)
      end

      it 'nulls only the one part and leaves the other two readable', :aggregate_failures do
        expect(detail.architecture).to eq(architecture)
        expect(detail.os).to eq(os)
        expect(detail.os_variant).to eq(os_variant)
      end
    end
  end

  describe 'malformed shapes coerce rather than reach the resolver as another type' do
    context 'when annotations is not a Hash' do
      let(:attributes) { super().merge('annotations' => %w[not a map]) }

      it 'coerces to nil' do
        expect(detail.annotations).to be_nil
      end
    end

    context 'when children carries a non-Hash entry' do
      let(:attributes) { super().merge('children' => [{ 'digest' => 'sha256:cccc' }, 'oops']) }

      it 'drops the non-Hash entry' do
        expect(detail.children).to eq([{ 'digest' => 'sha256:cccc' }])
      end
    end

    context 'when a string array carries a non-string entry' do
      let(:attributes) { super().merge('tags' => ['latest', 42], 'parent_digests' => [nil, 'sha256:dddd']) }

      it 'keeps only the string members', :aggregate_failures do
        expect(detail.tags).to eq(['latest'])
        expect(detail.parent_digests).to eq(['sha256:dddd'])
      end
    end

    # Each array reader guards on Array, so a wrong container type (a String or a Hash where the
    # contract sends a list) coerces to nil rather than reaching a consumer as another shape.
    context 'when an array-valued field is not an Array' do
      where(:malformed) { ['a string', { 'not' => 'a list' }, 42] }

      with_them do
        let(:attributes) { super().merge('tags' => malformed, 'children' => malformed, 'parent_digests' => malformed) }

        it 'coerces each to nil', :aggregate_failures do
          expect(detail.tags).to be_nil
          expect(detail.children).to be_nil
          expect(detail.parent_digests).to be_nil
        end
      end
    end
  end

  describe 'the preview readers inherited from Manifest' do
    it 'returns nil for the previews, which the detail response does not carry', :aggregate_failures do
      expect(detail.tags_preview).to be_nil
      expect(detail.parents_preview).to be_nil
      expect(detail.children_preview).to be_nil
    end
  end
end
