# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUserCreditsUsage'],
  feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUserCreditsUsage') }

  # Deliberately `read_user` rather than `read_subscription_usage`: the self view is
  # reachable by any member, including Guests, who cannot read subscription usage.
  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([
      :enabled,
      :is_outdated_client,
      :start_date,
      :end_date,
      :credits_used,
      :daily_usage,
      :products,
      :used_flow_types,
      :blocked_status
    ])
  end

  describe 'fields withheld from the self view' do
    it 'exposes no subscription-wide or other-user fields' do
      expect(described_class.fields.keys).not_to include(
        'usersUsage',
        'budgetCaps',
        'overage',
        'monthlyCommitment',
        'monthlyWaiver',
        'paidTierTrial',
        'purchaseCreditsPath',
        'subscriptionPortalUsageDashboardUrl'
      )
    end

    it 'exposes no field naming or identifying another user' do
      expect(described_class.fields.keys.grep(/user/i)).to be_empty
    end
  end

  describe 'field types' do
    it 'defines enabled as non-null' do
      expect(described_class.fields['enabled'].type.to_type_signature).to eq('Boolean!')
    end

    it 'defines creditsUsed as nullable' do
      expect(described_class.fields['creditsUsed'].type.to_type_signature).to eq('Float')
    end

    it 'resolves products through the self-scoped product type' do
      expect(described_class.fields['products'].type.unwrap.graphql_name)
        .to eq('GitlabSubscriptionUserCreditsUsageProduct')
    end

    it 'resolves dailyUsage through the self-scoped daily usage type' do
      expect(described_class.fields['dailyUsage'].type.unwrap.graphql_name)
        .to eq('GitlabSubscriptionUserCreditsUsageDailyUsage')
    end
  end
end
