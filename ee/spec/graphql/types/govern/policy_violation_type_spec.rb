# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicyViolation'], feature_category: :security_policy_management do
  specify do
    expect(described_class).to have_graphql_fields(:id, :details, :created_at)
  end
end
