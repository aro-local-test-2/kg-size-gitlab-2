# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::RolloutWorkflowToken, feature_category: :continuous_delivery do
  let(:workflow_token) { create(:cd_rollout_workflow_token) }

  describe 'factory' do
    it 'creates a valid workflow token using factory defaults' do
      expect(workflow_token).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:rollout).required }
    it { is_expected.to belong_to(:organization).required }

    it 'takes its sharding key from the rollout' do
      expect(workflow_token.organization_id).to eq(workflow_token.rollout.organization_id)
    end
  end

  describe 'validations' do
    subject { workflow_token }

    it { is_expected.to validate_length_of(:token).is_at_most(4096) }

    it 'refuses a token binding of any other length' do
      workflow_token.token_binding = 'too-short'

      expect(workflow_token).not_to be_valid
      expect(workflow_token.errors[:token_binding]).to be_present
    end

    # Required, not merely assigned: without a binding Relay refuses the StartWorkflow
    # this record exists for.
    it 'refuses a missing token binding' do
      workflow_token.token_binding = nil

      expect(workflow_token).not_to be_valid
      expect(workflow_token.errors[:token_binding]).to be_present
    end
  end

  describe 'token_binding' do
    # Relay refuses any other length outright, so a caller cannot discover this by
    # trial and error at runtime.
    it 'is assigned at creation, at the length Relay requires' do
      expect(workflow_token.token_binding.bytesize).to eq(Gitlab::Kas::Client::WORKFLOW_TOKEN_BINDING_BYTES)
    end

    it 'is unguessable, so two rollouts never share one' do
      expect(workflow_token.token_binding).not_to eq(create(:cd_rollout_workflow_token).token_binding)
    end

    # Cd::Rollouts::StartService presents it again when it retries a call whose response
    # it lost, so writing the token back must leave it alone.
    it 'is not reassigned on update' do
      expect { workflow_token.update!(token: 'the-workflow-token') }
        .not_to change { workflow_token.reload.token_binding }
    end

    # Encrypted at rest: a database read without the application's keys must not yield
    # something that can be replayed as the binding.
    it 'is not stored in the clear' do
      stored = described_class.connection.select_value(
        "SELECT token_binding FROM cd_rollout_workflow_tokens WHERE id = #{workflow_token.id}"
      )

      expect(stored).not_to include(workflow_token.token_binding)
    end
  end
end
