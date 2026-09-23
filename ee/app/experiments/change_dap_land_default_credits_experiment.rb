# frozen_string_literal: true

class ChangeDapLandDefaultCreditsExperiment < ApplicationExperiment
  CANDIDATE_QUANTITY = 25

  def self.context_keys
    %i[namespace]
  end

  control { nil }

  candidate { CANDIDATE_QUANTITY }
end
