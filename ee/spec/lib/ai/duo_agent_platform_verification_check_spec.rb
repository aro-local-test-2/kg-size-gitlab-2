# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoAgentPlatformVerificationCheck, :use_clean_rails_memory_store_caching,
  feature_category: :duo_agent_platform do
  describe '.agentic_chat_verification_check_enabled?' do
    let_it_be(:user) { create(:admin) }

    let(:probe_result) { instance_double(CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe) }

    subject(:can_run) { described_class.agentic_chat_verification_check_enabled?(user) }

    before do
      allow(Ability).to receive(:allowed?).with(user, :manage_self_hosted_models_settings).and_return(true)
      allow(CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe).to receive(:new)
        .with(user, deployment: :self_hosted).and_return(probe_result)
      allow(probe_result).to receive(:execute).and_return(
        instance_double(CloudConnector::StatusChecks::Probes::ProbeResult, success?: true)
      )
    end

    context 'when the feature flag is disabled, the user is allowed, and the probe succeeds' do
      before do
        stub_feature_flags(duo_agentic_chat_verification_check: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is enabled, the user is not allowed, and the probe succeeds' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :manage_self_hosted_models_settings).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is enabled, the user is allowed, and the probe fails' do
      before do
        allow(probe_result).to receive(:execute).and_return(
          instance_double(CloudConnector::StatusChecks::Probes::ProbeResult, success?: false)
        )
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is enabled, the user is allowed, and the probe succeeds' do
      it { is_expected.to be(true) }
    end

    it 'caches the probe result per user' do
      can_run

      expect(CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe).not_to receive(:new)

      described_class.agentic_chat_verification_check_enabled?(user)
    end

    it 'probes again for a different user' do
      can_run

      other_user = create(:admin)
      allow(Ability).to receive(:allowed?).with(other_user, :manage_self_hosted_models_settings).and_return(true)
      allow(CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe).to receive(:new)
        .with(other_user, deployment: :self_hosted).and_return(probe_result)

      expect(CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe).to receive(:new)
        .with(other_user, deployment: :self_hosted)

      described_class.agentic_chat_verification_check_enabled?(other_user)
    end
  end
end
