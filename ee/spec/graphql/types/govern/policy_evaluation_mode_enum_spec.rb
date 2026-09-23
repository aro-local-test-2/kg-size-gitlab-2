# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicyEvaluationMode'], feature_category: :security_policy_management do
  it 'mirrors the model enum' do
    expect(described_class.values.keys)
      .to match_array(Govern::PolicyEvaluation.modes.keys.map(&:upcase))
  end
end
