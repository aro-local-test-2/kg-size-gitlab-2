# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::WorkflowEvent, feature_category: :continuous_delivery do
  subject(:event) do
    described_class.new(
      type: 'com.gitlab.cd.service_failed',
      data: { environment: 'production', service: 'web', step_type: 'com.gitlab.cd.argo.canary.deploy',
              position: [0, 0], error: 'boom', reason: 'needs sign-off' }
    )
  end

  it 'exposes the event type' do
    expect(event.type).to eq('com.gitlab.cd.service_failed')
  end

  it 'exposes the environment name' do
    expect(event.environment_name).to eq('production')
  end

  it 'exposes the service name' do
    expect(event.service_name).to eq('web')
  end

  it 'exposes the step type' do
    expect(event.step_type).to eq('com.gitlab.cd.argo.canary.deploy')
  end

  it 'exposes the step path as a dot-joined string' do
    expect(event.step_path).to eq('0.0')
  end

  it 'exposes the error' do
    expect(event.error).to eq('boom')
  end

  it 'exposes the reason' do
    expect(event.reason).to eq('needs sign-off')
  end

  it 'exposes an empty array when no channel_tokens were given' do
    expect(event.channel_tokens).to eq([])
  end

  context 'when data is missing' do
    subject(:event) { described_class.new(type: 'com.gitlab.cd.rollout_succeeded', data: {}) }

    it 'returns nil for every data-backed reader' do
      expect(event.environment_name).to be_nil
      expect(event.service_name).to be_nil
      expect(event.step_type).to be_nil
      expect(event.step_path).to be_nil
      expect(event.error).to be_nil
      expect(event.reason).to be_nil
    end
  end

  # The engine reports a refusal that belongs to no step -- a malformed flow definition, a
  # rollout identity it cannot use -- with an empty position.
  context 'when the position is empty' do
    subject(:event) do
      described_class.new(type: 'com.gitlab.cd.step_failed', data: { position: [], error: 'boom' })
    end

    it 'has no step path, rather than an empty one' do
      expect(event.step_path).to be_nil
    end
  end

  context 'when channel_tokens are given' do
    subject(:event) do
      described_class.new(type: 'com.gitlab.cd.step_started', data: {},
        channel_tokens: [{ channel_name: 'approval', token: 'a-token' }])
    end

    it 'exposes them' do
      expect(event.channel_tokens).to eq([{ channel_name: 'approval', token: 'a-token' }])
    end
  end
end
