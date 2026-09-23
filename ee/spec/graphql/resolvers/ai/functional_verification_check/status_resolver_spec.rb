# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::FunctionalVerificationCheck::StatusResolver,
  feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:user) { create(:admin) }

  subject(:resolve_status) do
    resolve(described_class, obj: nil, args: { check_type: 'AGENTIC_CHAT' }, ctx: { current_user: user })
  end

  context 'when the verification check is not enabled for the user' do
    before do
      allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
        .with(user).and_return(false)
    end

    it 'returns nil without reading the run' do
      expect(::Ai::DuoAgentPlatform::FunctionalVerificationRunService).not_to receive(:new)

      expect(resolve_status).to be_nil
    end
  end

  context 'when the verification check is enabled for the user' do
    before do
      allow(::Ai::DuoAgentPlatformVerificationCheck).to receive(:agentic_chat_verification_check_enabled?)
        .with(user).and_return(true)
    end

    it 'reads the current run state for the agentic chat check' do
      expect_next_instance_of(::Ai::DuoAgentPlatform::FunctionalVerificationRunService,
        check_type: :agentic_chat) do |service|
        expect(service).to receive(:read).and_return({ state: 'not_run' })
      end

      expect(resolve_status).to eq({ state: 'not_run' })
    end
  end

  # The GraphQL argument only accepts CheckTypeEnum values, so an unsupported
  # check_type can't be reached through the field/argument pipeline today. This
  # exercises the resolver's own defensive branch directly for when the enum
  # gains a second value ahead of a matching case.
  context 'when the check type is not supported' do
    let(:ctx) do
      GraphQL::Query::Context.new(
        query: GraphQL::Query.new(GitlabSchema, document: nil, context: {}, variables: {}),
        values: { current_user: user }
      )
    end

    let(:resolver) { described_class.new(object: nil, context: ctx, field: nil) }

    it 'raises a resource not available error without checking eligibility' do
      expect(::Ai::DuoAgentPlatformVerificationCheck).not_to receive(:agentic_chat_verification_check_enabled?)

      expect { resolver.resolve(check_type: :other) }
        .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable, /other is not a supported check type/)
    end
  end
end
