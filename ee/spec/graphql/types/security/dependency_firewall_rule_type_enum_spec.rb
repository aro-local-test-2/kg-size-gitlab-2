# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::DependencyFirewallRuleTypeEnum, feature_category: :dependency_firewall do
  specify { expect(described_class.graphql_name).to eq('DependencyFirewallRuleType') }

  it 'exposes every persistable rule type' do
    expect(described_class.values.keys)
      .to match_array(::Security::DependencyFirewallPolicyRule.types.keys.map(&:upcase))
  end

  it 'maps each value back to the model enum key' do
    described_class.values.each_pair do |name, value|
      expect(value.value).to eq(name.downcase)
    end
  end

  # The class falls back to a generated description so a missing entry cannot stop the app booting.
  # That makes this example the only thing keeping the public GraphQL docs curated.
  it 'curates a description for every value' do
    expect(described_class::DESCRIPTIONS.keys)
      .to include(*::Security::DependencyFirewallPolicyRule.types.keys)
  end
end
