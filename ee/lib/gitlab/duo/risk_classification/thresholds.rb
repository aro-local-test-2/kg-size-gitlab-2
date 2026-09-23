# frozen_string_literal: true

module Gitlab
  module Duo
    module RiskClassification
      # Maps a score (0-100) onto a risk tier via fixed lower bounds. Kept
      # separate from the score itself so re-tiering later is a threshold
      # change, not a re-scoring run.
      #
      # These bounds are a starting point, not calibrated against real
      # assessments yet -- expect them to move once there's outcome data to
      # tune against.
      module Thresholds
        MIN_SCORE = 0
        MAX_SCORE = 100

        BOUNDS = {
          low: MIN_SCORE,
          medium: 25,
          high: 50,
          critical: 75
        }.freeze

        def self.tier_for(score)
          return unless valid?(score)

          BOUNDS.reverse_each.find { |_tier, lower_bound| score >= lower_bound }.first
        end

        def self.valid?(score)
          score.is_a?(Integer) && score.between?(MIN_SCORE, MAX_SCORE)
        end
      end
    end
  end
end
