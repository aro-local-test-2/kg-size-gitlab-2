# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Version, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'version' => '1.10.0',
      'created_at' => '2026-07-03T09:15:00Z',
      'created_by' => '101',
      'project_id' => '202',
      'git_commit_sha' => 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    }
  end

  subject(:version) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes the identifier, the version, and the parsed timestamp', :aggregate_failures do
      expect(version.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(version.version).to eq('1.10.0')
      expect(version.created_at).to eq(DateTime.iso8601('2026-07-03T09:15:00Z'))
    end

    it 'passes the three attribution references through as raw opaque strings, unresolved',
      :aggregate_failures do
      expect(version.created_by).to eq('101')
      expect(version.project_id).to eq('202')
      expect(version.git_commit_sha).to eq('deadbeefdeadbeefdeadbeefdeadbeefdeadbeef')
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('last_downloaded_at' => '2026-07-04T00:00:00Z', 'newly_added_ar_field' => 'x') }

    it 'defines no reader for the contract fields nothing renders yet, nor for unknown keys',
      :aggregate_failures do
      expect(version.version).to eq('1.10.0')
      expect(version).not_to respond_to(:last_downloaded_at)
      expect(version).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'size, package_id, and the npm metadata object' do
    let(:attributes) do
      super().merge(
        'size' => 987_654,
        'package_id' => 'pkg-0000-0000-0000-000000000000',
        'npm_metadata' => { 'description' => 'A design system', 'name' => '@acme/ui' }
      )
    end

    it 'passes size, package_id, and the parsed metadata Hash through unresolved', :aggregate_failures do
      expect(version.size).to eq(987_654)
      expect(version.package_id).to eq('pkg-0000-0000-0000-000000000000')
      expect(version.npm_metadata).to eq({ 'description' => 'A design system', 'name' => '@acme/ui' })
    end

    describe '#size' do
      context 'when the contract sends an explicit zero, which a hosted empty version reads' do
        let(:attributes) { super().merge('size' => 0) }

        it 'returns the zero rather than blanking it, so zero and null stay distinguishable' do
          expect(version.size).to eq(0)
        end
      end

      context 'when the contract sends JSON null, which a remote or pending-#550 version reads' do
        let(:attributes) { super().merge('size' => nil) }

        it 'returns nil rather than zero' do
          expect(version.size).to be_nil
        end
      end

      context 'when the wire value is a numeric string' do
        let(:attributes) { super().merge('size' => '987654') }

        it 'coerces to an Integer so BigInt renders a numeric sizeBytes' do
          expect(version.size).to eq(987_654)
        end
      end

      context 'when the wire value is a float' do
        let(:attributes) { super().merge('size' => 123.9) }

        it 'truncates to an Integer' do
          expect(version.size).to eq(123)
        end
      end

      context 'when the wire value is a numeric string with a fraction' do
        let(:attributes) { super().merge('size' => '123.9') }

        it 'truncates alike, so a float string and a float behave the same' do
          expect(version.size).to eq(123)
        end
      end

      context 'when the wire value is a non-numeric string' do
        let(:attributes) { super().merge('size' => 'not-a-number') }

        it 'reads nil rather than passing a non-numeric value through to BigInt' do
          expect(version.size).to be_nil
        end
      end
    end

    describe '#package_id' do
      context 'when the wire value is a JSON number' do
        let(:attributes) { super().merge('package_id' => 123) }

        it 'coerces to a String so the resolver pairing check compares against the GraphQL ID' do
          expect(version.package_id).to eq('123')
        end
      end
    end

    context 'when npm_metadata is present but not an object' do
      let(:attributes) { super().merge('npm_metadata' => 'not-an-object') }

      it 'reads nil rather than passing a non-Hash through to the resolver' do
        expect(version.npm_metadata).to be_nil
      end
    end
  end

  describe '#dist_tags' do
    context 'when the contract sends the names' do
      let(:attributes) { super().merge('dist_tags' => %w[latest next]) }

      it 'returns them in the order received' do
        expect(version.dist_tags).to eq(%w[latest next])
      end
    end

    context 'when the key is absent' do
      it 'returns an empty Array' do
        expect(version.dist_tags).to eq([])
      end
    end

    context 'when the contract sends JSON null' do
      let(:attributes) { super().merge('dist_tags' => nil) }

      it 'returns an empty Array' do
        expect(version.dist_tags).to eq([])
      end
    end

    context 'when the value is not an Array' do
      let(:attributes) { super().merge('dist_tags' => 'latest') }

      it 'returns an empty Array' do
        expect(version.dist_tags).to eq([])
      end
    end

    context 'when an element is not a String' do
      let(:attributes) { super().merge('dist_tags' => ['latest', nil, 3, { 'name' => 'next' }]) }

      it 'keeps only the String names' do
        expect(version.dist_tags).to eq(%w[latest])
      end
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising', :aggregate_failures do
      expect(version.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(version.version).to be_nil
      expect(version.created_at).to be_nil
      expect(version.created_by).to be_nil
      expect(version.project_id).to be_nil
      expect(version.git_commit_sha).to be_nil
      expect(version.size).to be_nil
      expect(version.package_id).to be_nil
      expect(version.npm_metadata).to be_nil
      expect(version.dist_tags).to eq([])
    end
  end

  describe 'timestamp coercion' do
    context 'when created_at is null, which the contract sends as JSON null' do
      let(:attributes) { super().merge('created_at' => nil) }

      it 'coerces to nil without raising' do
        expect(version.created_at).to be_nil
      end
    end

    context 'when created_at is not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp') }

      it 'coerces to nil without raising' do
        expect(version.created_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:version) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(version.id).to be_nil
      expect(version.version).to be_nil
      expect(version.created_at).to be_nil
    end
  end
end
