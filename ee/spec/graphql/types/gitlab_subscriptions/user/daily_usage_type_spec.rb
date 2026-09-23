# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUserCreditsUsageDailyUsage'],
  feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUserCreditsUsageDailyUsage') }

  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([:date, :credits_used])
  end

  it 'defines date as a non-null date' do
    expect(described_class.fields['date'].type.to_type_signature).to eq('ISO8601Date!')
  end

  it 'defines creditsUsed as a non-null float' do
    expect(described_class.fields['creditsUsed'].type.to_type_signature).to eq('Float!')
  end
end
