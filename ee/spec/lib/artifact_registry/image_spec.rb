# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Image, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'api-gateway',
      'last_downloaded_at' => '2026-07-03T09:15:00Z'
    }
  end

  subject(:image) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes the identifier, the image name, and the parsed timestamp', :aggregate_failures do
      expect(image.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(image.name).to eq('api-gateway')
      expect(image.last_downloaded_at).to eq(DateTime.iso8601('2026-07-03T09:15:00Z'))
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'ignored') }

    it 'defines no reader for the contract fields nothing renders yet, nor for unknown keys',
      :aggregate_failures do
      expect(image.name).to eq('api-gateway')
      expect(image).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for an absent name without raising', :aggregate_failures do
      expect(image.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(image.name).to be_nil
      expect(image.last_downloaded_at).to be_nil
    end
  end

  describe 'timestamp coercion' do
    context 'when last_downloaded_at is null, which the contract sends for an image never pulled' do
      let(:attributes) { super().merge('last_downloaded_at' => nil) }

      it 'returns nil' do
        expect(image.last_downloaded_at).to be_nil
      end
    end

    context 'when last_downloaded_at is not parseable' do
      let(:attributes) { super().merge('last_downloaded_at' => 'not-a-timestamp') }

      it 'returns nil rather than raising' do
        expect(image.last_downloaded_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:image) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(image.id).to be_nil
      expect(image.name).to be_nil
      expect(image.last_downloaded_at).to be_nil
    end
  end
end
