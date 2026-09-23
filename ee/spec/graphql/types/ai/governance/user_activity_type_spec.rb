# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::UserActivityType, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceUserActivity') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:user, :session_count)
  end
end
