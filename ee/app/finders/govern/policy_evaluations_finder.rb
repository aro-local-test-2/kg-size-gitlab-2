# frozen_string_literal: true

module Govern
  # Lists the policy evaluations of an organization, newest first, for the
  # Policy Store UI. Callers are responsible for authorization.
  #
  # Filter params: policy_id, mode, verdict, evaluated_after, evaluated_before.
  class PolicyEvaluationsFinder
    def initialize(organization:, params: {})
      @organization = organization
      @params = params
    end

    def execute
      evaluations = PolicyEvaluation.for_organization(organization)
      evaluations = by_policy(evaluations)
      evaluations = by_mode(evaluations)
      evaluations = by_verdict(evaluations)
      evaluations = by_evaluated_at(evaluations)

      evaluations.order_by_evaluated_at_desc
    end

    private

    attr_reader :organization, :params

    def by_policy(evaluations)
      return evaluations unless params[:policy_id]

      evaluations.for_policy(params[:policy_id])
    end

    def by_mode(evaluations)
      return evaluations unless params[:mode]

      evaluations.with_mode(params[:mode])
    end

    def by_verdict(evaluations)
      return evaluations unless params[:verdict]

      evaluations.with_verdict(params[:verdict])
    end

    def by_evaluated_at(evaluations)
      evaluations = evaluations.evaluated_after(params[:evaluated_after]) if params[:evaluated_after]
      evaluations = evaluations.evaluated_before(params[:evaluated_before]) if params[:evaluated_before]

      evaluations
    end
  end
end
