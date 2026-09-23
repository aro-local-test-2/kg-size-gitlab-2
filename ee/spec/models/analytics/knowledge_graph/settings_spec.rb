# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::Settings, feature_category: :knowledge_graph do
  describe '.all_settings' do
    it 'returns the frozen settings registry' do
      expect(described_class.all_settings).to eq(described_class::SETTINGS).and be_frozen
    end
  end

  describe '.boolean_settings' do
    it 'returns the auto-index setting' do
      expect(described_class.boolean_settings)
        .to include(orbit_auto_index_root_namespace: include(type: :boolean, default: false))
    end
  end
end
