# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Thresholds, feature_category: :code_review_workflow do
  describe '.tier_for' do
    where(:score, :tier) do
      [
        [0, :low],
        [24, :low],
        [25, :medium],
        [49, :medium],
        [50, :high],
        [74, :high],
        [75, :critical],
        [100, :critical]
      ]
    end

    with_them do
      it 'maps the score onto the expected tier' do
        expect(described_class.tier_for(score)).to eq(tier)
      end
    end

    it 'returns nil for an out-of-range score' do
      expect(described_class.tier_for(101)).to be_nil
      expect(described_class.tier_for(-1)).to be_nil
    end

    it 'returns nil for a nil score' do
      expect(described_class.tier_for(nil)).to be_nil
    end

    it 'returns nil for a non-integer score' do
      expect(described_class.tier_for(50.5)).to be_nil
    end
  end

  describe '.valid?' do
    it 'accepts integers within 0..100' do
      expect(described_class.valid?(0)).to be(true)
      expect(described_class.valid?(100)).to be(true)
    end

    it 'rejects out-of-range, non-integer, or nil values' do
      expect(described_class.valid?(-1)).to be(false)
      expect(described_class.valid?(101)).to be(false)
      expect(described_class.valid?(50.5)).to be(false)
      expect(described_class.valid?(nil)).to be(false)
    end
  end
end
