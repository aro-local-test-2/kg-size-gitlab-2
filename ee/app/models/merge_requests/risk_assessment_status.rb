# frozen_string_literal: true

module MergeRequests
  module RiskAssessmentStatus
    extend DeclarativeEnum

    key :status
    name 'MergeRequestRiskAssessmentStatus'
    description 'Status of a merge request risk classification.'

    define do
      pending value: 0, description: N_('Waiting to be classified.')
      queued value: 1, description: N_('Queued for (re)classification.')
      complete value: 2, description: N_('Classification has completed.')
      failed value: 3, description: N_('Classification could not be completed.')
    end
  end
end
