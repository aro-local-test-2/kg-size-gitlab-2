# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicyEvaluation'], feature_category: :security_policy_management do
  specify do
    expect(described_class).to have_graphql_fields(
      :id, :policy_id, :trigger_type, :mode, :verdict, :policy_version, :evaluated_at,
      :project_id, :environment_id, :user_id, :violations
    )
  end
end
