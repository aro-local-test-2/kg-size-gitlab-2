# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUserCreditsUsageProduct'],
  feature_category: :consumables_cost_management do
  include GraphqlHelpers

  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUserCreditsUsageProduct') }

  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([:id, :title, :flow_types])
  end

  it 'omits creditsUsed, which is a subscription-wide figure' do
    expect(described_class.fields.keys).not_to include('creditsUsed')
  end

  it 'defines id as a string field' do
    expect(described_class.fields['id'].type.to_type_signature).to eq('String!')
  end

  it 'defines flow_types as a non-null list' do
    expect(described_class.fields['flowTypes'].type.non_null?).to be(true)
  end

  describe '#id' do
    it 'returns the product id instead of a global id' do
      user = build(:user)
      product = ::GitlabSubscriptions::SubscriptionUsage::Product.new(
        id: 'duo_agent_platform',
        title: 'GitLab Duo Agent Platform',
        credits_used: nil,
        flow_types: [],
        declarative_policy_subject: user
      )

      expect(resolve_field(:id, product, current_user: user)).to eq('duo_agent_platform')
    end
  end
end
