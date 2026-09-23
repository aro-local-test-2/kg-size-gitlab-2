# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.functionalVerificationStatus', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:admin) }

  let(:query) do
    graphql_query_for('functionalVerificationStatus', { check_type: :AGENTIC_CHAT }, 'state message updatedAt')
  end

  subject(:request) { post_graphql(query, current_user: current_user) }

  before do
    allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
      .with(current_user).and_return(true)
  end

  it 'returns the not_run state when no run has started' do
    request

    expect(graphql_data_at(:functional_verification_status)).to eq(
      'state' => 'NOT_RUN', 'message' => nil, 'updatedAt' => nil
    )
  end

  context 'when a run exists' do
    let_it_be(:run) do
      create(:duo_agent_platform_functional_verification_run, :passed, check_type: :agentic_chat)
    end

    it 'returns the current state of the run' do
      request

      expect(graphql_data_at(:functional_verification_status, :state)).to eq('PASSED')
    end
  end

  context 'when the verification check is not enabled for the user' do
    before do
      allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
        .with(current_user).and_return(false)
    end

    it 'returns null' do
      request

      expect(graphql_data_at(:functional_verification_status)).to be_nil
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_functional_verification_check do
    let(:user) { current_user }
    let(:boundary_object) { :instance }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end
end
