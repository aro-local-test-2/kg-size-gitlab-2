# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::ScoringFunction::Base, feature_category: :duo_code_review do
  # A subclass, so the contract is tested without any version's arithmetic.
  let(:scoring_function) { Class.new(described_class) }

  describe '#execute' do
    # A version that forgets to score has to fail loudly. Returning an empty
    # result would read as "nothing risky here".
    it 'raises, since scoring is left to each version' do
      expect { scoring_function.new.execute }.to raise_error(::Gitlab::AbstractMethodError)
    end
  end

  describe '.version' do
    it 'is settable per version and stays unset until then', :aggregate_failures do
      expect(scoring_function.version).to be_nil

      scoring_function.version = 'v9'

      expect(scoring_function.version).to eq('v9')
      expect(scoring_function.new.version).to eq('v9')
    end
  end

  describe 'the input contract' do
    # The flow returns JSON and SignalsExtractor keys by symbol, so both have
    # to arrive at the same string keys the weights are declared against.
    it 'reads symbol and string keys the same way', :aggregate_failures do
      instance = scoring_function.new(
        signals: { 'diff_shape.churn': 0.5 },
        claims: { authorization: {} },
        mitigations: { 'rollout_guard.feature_flag': 1.0 },
        missing: [:ownership]
      )

      expect(instance.send(:signals)).to eq({ 'diff_shape.churn' => 0.5 })
      expect(instance.send(:claims).keys).to eq(['authorization'])
      expect(instance.send(:mitigations)).to eq({ 'rollout_guard.feature_flag' => 1.0 })
      expect(instance.send(:missing)).to eq(['ownership'])
    end

    it 'accepts nil for every input, so a partial assessment still scores', :aggregate_failures do
      instance = scoring_function.new(claims: nil, signals: nil, mitigations: nil, missing: nil)

      expect(instance.send(:claims)).to be_empty
      expect(instance.send(:signals)).to be_empty
      expect(instance.send(:mitigations)).to be_empty
      expect(instance.send(:missing)).to be_empty
    end

    it 'keeps the inputs private, since a result is the only output' do
      expect(scoring_function.new).not_to respond_to(:claims)
    end
  end

  describe 'Result' do
    it 'carries the same fields whichever version produced it' do
      expect(described_class::Result.members)
        .to eq(%i[score confidence signal_breakdown version missing_signals])
    end
  end
end
