# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::NpmDistTag, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 't1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'latest',
      'version_id' => 'v1000-0000-0000-0000-000000000000',
      'version' => '1.10.0'
    }
  end

  subject(:dist_tag) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes the identifier, name, tagged version id, and version string', :aggregate_failures do
      expect(dist_tag.id).to eq('t1b2c3d4-0000-0000-0000-000000000000')
      expect(dist_tag.name).to eq('latest')
      expect(dist_tag.version_id).to eq('v1000-0000-0000-0000-000000000000')
      expect(dist_tag.version).to eq('1.10.0')
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'x') }

    it 'defines no reader for an unknown key' do
      expect(dist_tag).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 't1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising', :aggregate_failures do
      expect(dist_tag.id).to eq('t1b2c3d4-0000-0000-0000-000000000000')
      expect(dist_tag.name).to be_nil
      expect(dist_tag.version_id).to be_nil
      expect(dist_tag.version).to be_nil
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:dist_tag) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(dist_tag.id).to be_nil
      expect(dist_tag.name).to be_nil
    end
  end
end
