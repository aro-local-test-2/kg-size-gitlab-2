# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::NpmFile, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'f1b2c3d4-0000-0000-0000-000000000000',
      'file_name' => 'ui-components-1.10.0.tgz',
      'size' => 54_321,
      'sha256' => 'a' * 64,
      'created_at' => '2026-07-03T09:15:00Z'
    }
  end

  subject(:file) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes the identifier, name, size, checksum, and parsed timestamp', :aggregate_failures do
      expect(file.id).to eq('f1b2c3d4-0000-0000-0000-000000000000')
      expect(file.file_name).to eq('ui-components-1.10.0.tgz')
      expect(file.size).to eq(54_321)
      expect(file.sha256).to eq('a' * 64)
      expect(file.created_at).to eq(DateTime.iso8601('2026-07-03T09:15:00Z'))
    end

    it 'defines no Maven-only checksum reader, so the two file shapes stay distinct', :aggregate_failures do
      expect(file).not_to respond_to(:sha1)
      expect(file).not_to respond_to(:sha512)
      expect(file).not_to respond_to(:md5)
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('cache' => { 'origin' => 'upstream' }, 'newly_added_ar_field' => 'x') }

    it 'defines no reader for contract fields nothing renders, nor for unknown keys', :aggregate_failures do
      expect(file.file_name).to eq('ui-components-1.10.0.tgz')
      expect(file).not_to respond_to(:cache)
      expect(file).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'created_at nullable on a remote cached row' do
    let(:attributes) { super().merge('created_at' => nil) }

    it 'reads nil rather than raising' do
      expect(file.created_at).to be_nil
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'f1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising, so a sparse response is tolerated',
      :aggregate_failures do
      expect(file.id).to eq('f1b2c3d4-0000-0000-0000-000000000000')
      expect(file.file_name).to be_nil
      expect(file.size).to be_nil
      expect(file.sha256).to be_nil
      expect(file.created_at).to be_nil
    end
  end

  describe 'timestamp coercion' do
    context 'when created_at is not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp') }

      it 'coerces to nil without raising' do
        expect(file.created_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:file) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(file.id).to be_nil
      expect(file.file_name).to be_nil
      expect(file.created_at).to be_nil
    end
  end
end
