# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::ConnectedAgentType, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceConnectedAgent') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :agent_type, :identity_count, :active_count, :revoked_count, :user_count, :session_count, :last_session_at
    )
  end
end
