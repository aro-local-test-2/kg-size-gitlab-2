# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Logger, feature_category: :artifact_registry do
  subject(:logger) { described_class.new('/dev/null') }

  it_behaves_like 'a json logger', { 'feature_category' => 'artifact_registry' }

  describe '.file_name_noext' do
    it 'returns the log file name without extension' do
      expect(described_class.file_name_noext).to eq('artifact_registry')
    end
  end
end
