# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Govern::PolicyCreate, feature_category: :security_policy_management do
  it { expect(described_class.graphql_name).to eq('GovernPolicyCreate') }
  it { expect(described_class).to require_graphql_authorizations(:create_govern_policy) }

  it 'exposes the created policy' do
    expect(described_class.fields['policy'].type.unwrap).to eq(Types::Govern::PolicyType)
  end

  it 'accepts the policy attributes as arguments' do
    expect(described_class.arguments.keys).to match_array(
      %w[
        organizationId name description triggerType rules actions
        policyScope scopeRego mode lifecycleState clientMutationId
      ]
    )
  end

  # Six of these arguments come from the shared concern, so this pins the published
  # contract against an edit made for the sake of the other mutation that includes it.
  it 'requires only the organization, name, trigger type, and rules' do
    required = described_class.arguments.filter_map { |name, arg| name if arg.type.non_null? }

    expect(required).to match_array(%w[organizationId name triggerType rules])
  end
end
