# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::ScoringFunction::V1, feature_category: :duo_code_review do
  def score_for(**args)
    described_class.new(**args).execute
  end

  def claim(value, evidence: nil)
    { 'value' => value, 'evidence' => evidence }
  end

  def capped_mitigations
    { 'revert.reverts_prior_change' => 1.0, 'rollout_guard.feature_flag' => 1.0 }
  end

  def all_claims_true
    {
      'authorization' => claim(true),
      'authentication' => claim(true),
      'credentials_crypto' => claim(true),
      'database_migration' => claim(true),
      'api_contract' => claim(true)
    }
  end

  describe 'the model' do
    # Every-version invariants (the whole budget, one claim per domain, the
    # mitigation cap) live in scoring_function_spec.rb. This is V1's own split.
    it 'splits the budget between claims and signals', :aggregate_failures do
      expect(described_class.claim_budget).to eq(74)
      expect(described_class.signal_budget).to eq(26)
    end
  end

  describe '#execute' do
    it 'stamps the version that produced the result' do
      expect(score_for.version).to eq('v1')
    end

    it 'scores an empty assessment at zero' do
      expect(score_for.score).to eq(0)
    end

    context 'with claims' do
      it 'awards the full claim budget when every claim is at its maximum' do
        expect(score_for(claims: all_claims_true).score).to eq(74)
      end

      it 'awards a single boolean claim its own weight' do
        expect(score_for(claims: { 'authorization' => claim(true) }).score).to eq(21)
      end

      it 'awards nothing for a boolean claim answered the safe way' do
        expect(score_for(claims: { 'authorization' => claim(false) }).score).to eq(0)
      end

      it 'accepts a stringified boolean, since the flow returns JSON' do
        expect(score_for(claims: { 'authorization' => claim('true') }).score).to eq(21)
      end

      # Severity ordering has to survive into the weights, or a critical domain
      # can be outscored by a high one.
      it 'weighs a critical domain above a high one' do
        critical = score_for(claims: { 'authorization' => claim(true) }).score
        high = score_for(claims: { 'api_contract' => claim(true) }).score

        expect(critical).to be > high
      end

      # No shipped claim is graded yet. Grading `database_migration` is the
      # next iteration, so the path stays covered through a subclass rather
      # than going untested until then.
      context 'when a domain claim is graded rather than boolean' do
        let(:graded) do
          Class.new(described_class) do
            weigh_domain :database_migration, 14,
              scale: { 'destructive' => 1.0, 'additive' => 0.5, 'none' => 0.0 }
          end
        end

        where(:answer, :expected_score) do
          [
            ['destructive', 14],
            ['additive', 7],
            ['none', 0]
          ]
        end

        with_them do
          it 'scales the weight by the declared fraction' do
            result = graded.new(claims: { 'database_migration' => claim(answer) }).execute

            expect(result.score).to eq(expected_score)
          end
        end

        # An answer outside the declared scale means the flow drifted from the
        # contract. Scoring it as zero is safer than guessing what it meant.
        it 'awards nothing for an answer outside the declared scale' do
          result = graded.new(claims: { 'database_migration' => claim('catastrophic') }).execute

          expect(result.score).to eq(0)
        end
      end

      it 'ignores a claim it does not score' do
        expect(score_for(claims: { 'unknown_claim' => claim(true) }).score).to eq(0)
      end

      it 'ignores a malformed claim rather than raising' do
        expect(score_for(claims: { 'authorization' => 'yes' }).score).to eq(0)
      end

      it 'reads a symbol-keyed claim, since the flow may arrive either way' do
        expect(score_for(claims: { 'authorization' => { value: true } }).score).to eq(21)
      end

      # The API declares the claim value as free-form text, so the flow can
      # answer "yes" or "behavioral" where a weight expects true or false.
      # Scoring that as zero is right; calling the domain assessed is not.
      context 'when the flow answers off the contract' do
        let(:result) { score_for(claims: { 'authorization' => claim('yes') }) }

        it 'awards nothing' do
          expect(result.score).to eq(0)
        end

        it 'reports the claim as unanswered rather than as safe' do
          expect(result.missing_signals).to include('authorization')
        end

        it 'does not count it towards confidence' do
          expect(result.confidence).to eq(0)
        end
      end
    end

    context 'with signals' do
      it 'awards a signal its weight at full strength' do
        expect(score_for(signals: { 'test_coverage.uncovered_lines' => 1.0 }).score).to eq(5)
      end

      it 'scales a signal by its normalised value' do
        expect(score_for(signals: { 'test_coverage.uncovered_lines' => 0.4 }).score).to eq(2)
      end

      # Thresholds.tier_for only accepts an Integer, so a fractional score
      # would leave the assessment without a tier at all.
      it 'rounds a fractional total to a whole number', :aggregate_failures do
        result = score_for(signals: { 'test_coverage.uncovered_lines' => 0.7 })

        expect(result.score).to eq(4)
        expect(result.score).to be_an(Integer)
      end

      # A regressed extractor returning a raw count instead of a fraction must
      # not be able to award a weight more than it is worth.
      it 'clamps a value above the normalised range' do
        expect(score_for(signals: { 'test_coverage.uncovered_lines' => 5.0 }).score).to eq(5)
      end

      it 'ignores a signal dimension that carries no weight' do
        expect(score_for(signals: { 'diff_shape.net_growth' => 1.0 }).score).to eq(0)
      end

      it 'accepts symbol keys' do
        expect(score_for(signals: { 'test_coverage.uncovered_lines': 1.0 }).score).to eq(5)
      end
    end

    context 'with mitigations' do
      it 'subtracts a mitigation from the score' do
        result = score_for(claims: all_claims_true, mitigations: { 'rollout_guard.feature_flag' => 1.0 })

        expect(result.score).to eq(68)
      end

      it 'scales a mitigation by its normalised value' do
        result = score_for(claims: all_claims_true, mitigations: { 'rollout_guard.feature_flag' => 0.5 })

        expect(result.score).to eq(71)
      end

      # A feature flag around a risky change must not be able to talk the score
      # down to nothing.
      it 'caps how much mitigations can subtract' do
        expect(score_for(claims: all_claims_true, mitigations: capped_mitigations).score).to eq(62)
      end

      it 'never drives the score below zero' do
        expect(score_for(mitigations: { 'revert.reverts_prior_change' => 1.0 }).score).to eq(0)
      end

      it 'clamps a value above the normalised range' do
        expect(score_for(claims: all_claims_true, mitigations: { 'rollout_guard.feature_flag' => 4.0 }).score)
          .to eq(68)
      end
    end

    it 'reaches the maximum score only when both channels are saturated' do
      signals = described_class.signal_weights.keys.index_with { 1.0 }

      result = score_for(claims: all_claims_true, signals: signals)

      expect(result.score).to eq(Gitlab::Duo::RiskClassification::Thresholds::MAX_SCORE)
    end
  end

  describe 'the signal breakdown' do
    it 'is empty when nothing contributed' do
      expect(score_for.signal_breakdown).to be_empty
    end

    it 'orders contributions by weight, largest first' do
      result = score_for(
        claims: { 'authorization' => claim(true), 'database_migration' => claim(true) },
        signals: { 'test_coverage.uncovered_lines' => 1.0 }
      )

      expect(result.signal_breakdown.pluck('signal'))
        .to eq(%w[authorization database_migration test_coverage.uncovered_lines])
    end

    it 'sorts a mitigation by size rather than by sign' do
      result = score_for(
        claims: { 'database_migration' => claim(true) },
        mitigations: { 'revert.reverts_prior_change' => 1.0 },
        signals: { 'test_coverage.uncovered_lines' => 1.0 }
      )

      expect(result.signal_breakdown.pluck('signal', 'contribution'))
        .to eq([['database_migration', 14], ['revert.reverts_prior_change', -8],
          ['test_coverage.uncovered_lines', 5]])
    end

    # The breakdown exists to explain the score, so the two have to agree. The
    # cap is applied to the score, not to what each mitigation is worth, which
    # left the two disagreeing by up to the amount forgone.
    describe 'reconciliation with the score' do
      it 'adds up to the score when nothing is capped' do
        result = score_for(
          claims: all_claims_true,
          signals: { 'test_coverage.uncovered_lines' => 1.0 },
          mitigations: { 'rollout_guard.feature_flag' => 1.0 }
        )

        expect(result.signal_breakdown.sum { |line| line['contribution'] }).to eq(result.score)
      end

      it 'adds up to the score when mitigations exceed the cap' do
        result = score_for(claims: all_claims_true, mitigations: capped_mitigations)

        expect(result.signal_breakdown.sum { |line| line['contribution'] }).to eq(result.score)
      end

      it 'shows the forgone amount as its own line, rather than scaling the mitigations down',
        :aggregate_failures do
        result = score_for(claims: all_claims_true, mitigations: capped_mitigations)
        lines = result.signal_breakdown.to_h { |line| [line['signal'], line['contribution']] }

        expect(lines['revert.reverts_prior_change']).to eq(-8)
        expect(lines['rollout_guard.feature_flag']).to eq(-6)
        expect(lines[described_class::MITIGATION_CAP_SIGNAL]).to eq(2)
      end

      # The breakdown is persisted, so a sentence written here would be frozen
      # in the locale of whichever process scored it. The reader explains the
      # line from its name instead.
      it 'carries no prose of its own' do
        result = score_for(claims: all_claims_true, mitigations: capped_mitigations)
        line = result.signal_breakdown.find do |contribution|
          contribution['signal'] == described_class::MITIGATION_CAP_SIGNAL
        end

        expect(line['detail']).to be_nil
      end

      it 'omits the line entirely when the cap does not bind' do
        result = score_for(claims: all_claims_true, mitigations: { 'rollout_guard.feature_flag' => 1.0 })

        expect(result.signal_breakdown.pluck('signal')).not_to include(described_class::MITIGATION_CAP_SIGNAL)
      end

      it 'omits the line when mitigations land exactly on the cap', :aggregate_failures do
        mitigations = { 'revert.reverts_prior_change' => 0.75, 'rollout_guard.feature_flag' => 1.0 }
        result = score_for(claims: all_claims_true, mitigations: mitigations)

        expect(result.score).to eq(62)
        expect(result.signal_breakdown.pluck('signal')).not_to include(described_class::MITIGATION_CAP_SIGNAL)
      end
    end

    it 'uses string keys, since it is persisted as JSON' do
      result = score_for(claims: { 'authorization' => claim(true) })

      expect(result.signal_breakdown.first.keys).to contain_exactly('signal', 'contribution', 'detail')
    end

    it 'carries the claim evidence, so a reviewer can check the claim' do
      result = score_for(claims: { 'authorization' => claim(true, evidence: 'app/policies/x.rb:42') })

      expect(result.signal_breakdown.first['detail']).to eq('authorization: true (app/policies/x.rb:42)')
    end

    it 'states the claim on its own when the flow gave no evidence' do
      result = score_for(claims: { 'authorization' => claim(true) })

      expect(result.signal_breakdown.first['detail']).to eq('authorization: true')
    end

    # The model writes the evidence and the string is persisted, so a newline
    # would break out of the explanation it is rendered into.
    it 'collapses model-written evidence onto one line' do
      result = score_for(claims: { 'authorization' => claim(true, evidence: "app/x.rb:1\n\nlooks  fine") })

      expect(result.signal_breakdown.first['detail']).to eq('authorization: true (app/x.rb:1 looks fine)')
    end

    it 'keeps two decimal places, since a reviewer reads the number' do
      result = score_for(signals: { 'diff_shape.churn' => 0.25 })

      expect(result.signal_breakdown.first['contribution']).to eq(0.75)
    end
  end

  describe 'missing signals' do
    it 'reports a claim the flow never answered' do
      expect(score_for.missing_signals).to match_array(described_class.claim_weights.keys)
    end

    it 'reports a signal that could not be measured' do
      result = score_for(claims: all_claims_true, missing: ['test_coverage'])

      expect(result.missing_signals).to eq(['test_coverage'])
    end

    it 'does not report a claim that was answered, even negatively' do
      result = score_for(claims: { 'authorization' => claim(false) })

      expect(result.missing_signals).not_to include('authorization')
    end

    it 'does not report the same input twice' do
      result = score_for(missing: %w[test_coverage test_coverage])

      expect(result.missing_signals.count('test_coverage')).to eq(1)
    end
  end

  describe 'confidence' do
    # "We could not measure this" and "this looks safe" must never read the
    # same, so an assessment with nothing measured is not a confident zero.
    it 'is zero when nothing was measured' do
      expect(score_for.confidence).to eq(0)
    end

    it 'rises as more of the picture becomes available' do
      few = score_for(claims: { 'authorization' => claim(true) }).confidence
      many = score_for(claims: all_claims_true).confidence

      expect(many).to be > few
    end

    # Agreement is only meaningful once both halves were measured. Applying it
    # to a single measured half would make answering more claims lower
    # confidence.
    it 'rests on availability alone when only one half was measured' do
      # The whole 74-point claim budget answered and no signal to corroborate
      # it, so agreement cannot be assessed at all.
      expect(score_for(claims: all_claims_true).confidence).to eq(74)
    end

    it 'weighs availability and agreement as declared once both halves exist' do
      result = score_for(
        claims: { 'authorization' => claim(false) },
        signals: described_class.signal_weights.keys.index_with { 1.0 }
      )

      # 21 of 74 claim points and all 26 signal points answered, so
      # availability alone would give 47. The halves flatly disagree though:
      # the flow says no domain is touched while every signal is maxed out, so
      # agreement is 0 and confidence lands below what availability would claim.
      expect(result.confidence).to eq(31)
    end

    # Held against the same answered inputs, so only agreement differs. An
    # unanswered input already costs availability, and must not be charged
    # again as the two halves disagreeing.
    it 'is higher when the semantic and structural halves agree' do
      answered_claims = { 'authorization' => claim(false) }
      all_signals = described_class.signal_weights.keys

      agreeing = score_for(claims: answered_claims, signals: all_signals.index_with { 0.0 }).confidence
      disagreeing = score_for(claims: answered_claims, signals: all_signals.index_with { 1.0 }).confidence

      expect(agreeing).to be > disagreeing
    end

    # A claim is worth far more than a signal dimension, so counting inputs
    # rather than points would let a thin but complete-looking picture read as
    # confident.
    it 'weighs a missing claim more heavily than a missing signal dimension' do
      without_claim = score_for(
        claims: all_claims_true.except('authorization'),
        signals: described_class.signal_weights.keys.index_with { 1.0 }
      ).confidence

      without_dimension = score_for(
        claims: all_claims_true,
        signals: described_class.signal_weights.keys.excluding('ai_authorship.agent_authored').index_with { 1.0 }
      ).confidence

      expect(without_dimension).to be > without_claim
    end

    it 'never exceeds 100' do
      signals = described_class.signal_weights.keys.index_with { 1.0 }

      expect(score_for(claims: all_claims_true, signals: signals).confidence).to be <= 100
    end
  end

  describe 'determinism' do
    # The whole point of scoring in Rails rather than in the model: the same
    # inputs must always produce the same number.
    it 'produces the same result for the same inputs' do
      args = {
        claims: all_claims_true,
        signals: { 'test_coverage.uncovered_lines' => 0.7, 'diff_shape.churn' => 0.3 },
        mitigations: { 'rollout_guard.feature_flag' => 0.5 }
      }

      first_run = score_for(**args).to_h
      second_run = score_for(**args).to_h

      expect(first_run).to eq(second_run)
    end
  end
end
