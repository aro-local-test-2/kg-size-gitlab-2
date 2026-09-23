# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::ScoringFunction, feature_category: :duo_code_review do
  describe '.current' do
    it 'is the newest version' do
      expect(described_class.current).to eq(Gitlab::Duo::RiskClassification::ScoringFunction::V1)
    end
  end

  describe '.all' do
    it 'lists every version' do
      expect(described_class.all).to eq([Gitlab::Duo::RiskClassification::ScoringFunction::V1])
    end

    it 'gives every version a distinct identifier' do
      versions = described_class.all.map(&:version)

      expect(versions.uniq.size).to eq(versions.size)
    end
  end

  # Written over the registry, not as a call at the end of each class body,
  # which a new version could leave out.
  describe 'every version' do
    versions = described_class.all

    versions.each do |scoring_function|
      context "with #{scoring_function.version}" do
        it 'weights the answer to every domain the flow is asked about' do
          expect(scoring_function.claim_weights.keys)
            .to match_array(Gitlab::Duo::RiskClassification::Domain.all.map(&:name))
        end

        # Under-spending compresses every score, and over-spending is truncated
        # by the clamp, so two unlike changes would both read as the top score.
        it 'spends the whole score range' do
          budget = scoring_function.claim_budget + scoring_function.signal_budget

          expect(budget).to eq(Gitlab::Duo::RiskClassification::Thresholds::MAX_SCORE)
        end

        # Mitigations subtract from a score the claims and signals already
        # spent in full, so they are capped rather than budgeted.
        it 'caps mitigations below the claim budget' do
          expect(scoring_function::MITIGATION_CAP).to be < scoring_function.claim_budget
        end
      end
    end
  end

  describe '.for_version' do
    it 'looks a version up by its identifier' do
      expect(described_class.for_version('v1')).to eq(described_class::V1)
    end

    it 'accepts a symbol' do
      expect(described_class.for_version(:v1)).to eq(described_class::V1)
    end

    # An assessment scored by a version that no longer exists must not fall back
    # to the current one, or an old score would be reinterpreted under new
    # weights.
    it 'returns nil for an unknown version' do
      expect(described_class.for_version('v99')).to be_nil
    end
  end
end
