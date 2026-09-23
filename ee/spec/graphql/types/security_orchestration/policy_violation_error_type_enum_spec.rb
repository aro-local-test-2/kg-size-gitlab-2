# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['PolicyViolationErrorType'], feature_category: :security_policy_management do
  specify { expect(described_class.graphql_name).to eq('PolicyViolationErrorType') }

  it 'exposes every error code a violation can carry' do
    expected = Security::ScanResultPolicyViolation::ERRORS.values +
      [Security::ScanResultPolicies::PolicyViolationDetails::ERROR_UNKNOWN]

    expect(described_class.values.keys).to match_array(expected)
  end
end
