# frozen_string_literal: true

module Types
  module MergeRequests
    module RiskClassification
      class TierEnum < BaseEnum
        declarative_enum ::MergeRequests::RiskTier
      end
    end
  end
end
