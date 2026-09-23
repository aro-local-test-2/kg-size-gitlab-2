# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::ScoringFunction::Weights, feature_category: :duo_code_review do
  # Anonymous so declaring weights cannot mutate a shipped scoring function:
  # class_attribute copies on write.
  def weigh(&block)
    Class.new { include Gitlab::Duo::RiskClassification::ScoringFunction::Weights }.tap do |klass|
      klass.class_eval(&block)
    end
  end

  def domain_names
    Gitlab::Duo::RiskClassification::Domain.all.map(&:name)
  end

  describe '.weigh_domain' do
    it 'keys the weight by the domain name the catalog declares' do
      klass = weigh { weigh_domain :authorization, 18 }

      expect(klass.claim_weights).to eq({ 'authorization' => { max: 18 } })
    end

    it 'treats a domain claim as boolean unless given a scale' do
      klass = weigh { weigh_domain :database_migration, 12, scale: { 'destructive' => 1.0 } }

      expect(klass.claim_weights['database_migration']).to eq({ max: 12, scale: { 'destructive' => 1.0 } })
    end

    # The point of the whole concern: a weight cannot name something that does
    # not exist, so a rename cannot leave a key that quietly matches nothing.
    it 'refuses a domain the catalog does not declare, and says what it has' do
      expect { weigh { weigh_domain :payments, 10 } }
        .to raise_error(described_class::UnknownWeight, /no domain named 'payments'.*authorization/)
    end
  end

  describe '.weigh_signal' do
    it 'builds the key from a signal and a dimension that both exist' do
      klass = weigh { weigh_signal :test_coverage, :uncovered_lines, 5 }

      expect(klass.signal_weights).to eq({ 'test_coverage.uncovered_lines' => 5 })
    end

    it 'refuses an unregistered signal' do
      expect { weigh { weigh_signal :coverage, :uncovered_lines, 5 } }
        .to raise_error(described_class::UnknownWeight, /no signal named 'coverage'/)
    end

    it 'refuses a dimension the signal does not declare, and lists the ones it has' do
      expect { weigh { weigh_signal :test_coverage, :renamed_away, 5 } }
        .to raise_error(described_class::UnknownWeight, /no dimension 'renamed_away'.*uncovered_lines/)
    end

    # A mitigation subtracts, so weighting one as a signal would invert it.
    it 'refuses a mitigation weighted as a signal' do
      expect { weigh { weigh_signal :revert, :reverts_prior_change, 8 } }
        .to raise_error(described_class::UnknownWeight, /revert is a mitigation/)
    end
  end

  describe '.weigh_mitigation' do
    it 'keeps mitigations in their own channel' do
      klass = weigh { weigh_mitigation :revert, :reverts_prior_change, 8 }

      expect(klass.mitigation_weights).to eq({ 'revert.reverts_prior_change' => 8 })
      expect(klass.signal_weights).to be_empty
    end

    it 'refuses a signal weighted as a mitigation' do
      expect { weigh { weigh_mitigation :diff_shape, :churn, 5 } }
        .to raise_error(described_class::UnknownWeight, /diff_shape is a signal/)
    end
  end

  describe '.claim_budget' do
    it 'sums what each claim can award' do
      klass = weigh { weigh_domain :authorization, 18 }

      expect(klass.claim_budget).to eq(18)
    end

    # A budget counted from an unreachable maximum would compress every score:
    # the spec that holds the weights to 100 points would pass while the top
    # score stayed out of reach.
    it 'counts a graded claim at the most its scale can reach' do
      klass = weigh { weigh_domain :database_migration, 14, scale: { 'destructive' => 0.5, 'none' => 0.0 } }

      expect(klass.claim_budget).to eq(7)
    end
  end

  # Weights are declared in a class body, so a version that inherits from
  # another must not be able to reach back and rewrite the weights the parent
  # already shipped.
  describe 'isolation between classes' do
    it 'leaves the parent untouched when a subclass declares its own weight', :aggregate_failures do
      parent = weigh { weigh_domain :authorization, 18 }

      child = Class.new(parent)
      child.weigh_domain :authentication, 9

      expect(parent.claim_weights.keys).to eq(['authorization'])
      expect(child.claim_weights.keys).to match_array(%w[authorization authentication])
    end
  end
end
