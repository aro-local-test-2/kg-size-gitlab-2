# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Logger, feature_category: :continuous_delivery do
  subject(:logger) { described_class.new('/dev/null') }

  it_behaves_like 'a json logger', {}

  describe '.file_name_noext' do
    it 'returns the log file name without extension' do
      expect(described_class.file_name_noext).to eq('cd')
    end
  end
end
