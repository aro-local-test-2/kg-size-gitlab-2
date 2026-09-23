# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['PolicyStore'], feature_category: :security_policy_management do
  specify do
    expect(described_class).to have_graphql_fields(:triggers, :rules, :actions, :policies, :policy_evaluations)
  end
end
