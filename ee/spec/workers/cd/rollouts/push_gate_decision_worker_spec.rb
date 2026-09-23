# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::PushGateDecisionWorker, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }
  let_it_be(:user) { create(:user) }
  let_it_be(:request_transition) { create(:cd_rollout_transition, rollout: rollout, event: 'request_approval') }

  describe '#perform' do
    it 'calls the push service with the rollout, request transition, result, and user' do
      expect_next_instance_of(::Cd::Rollouts::PushGateDecisionService, rollout,
        request_transition: request_transition, result: 'approve', current_user: user) do |service|
        expect(service).to receive(:execute)
      end

      described_class.new.perform(rollout.id, request_transition.id, 'approve', user.id)
    end

    context 'when the rollout no longer exists' do
      it 'logs the skip and does not call the service' do
        expect(::Cd::Rollouts::PushGateDecisionService).not_to receive(:new)
        expect(::Cd::Logger).to receive(:info)
          .with(hash_including(Labkit::Fields::GL_USER_ID => user.id))

        expect do
          described_class.new.perform(non_existing_record_id, request_transition.id, 'approve', user.id)
        end.not_to raise_error
      end
    end

    context 'when the request transition no longer exists' do
      it 'does nothing' do
        expect(::Cd::Rollouts::PushGateDecisionService).not_to receive(:new)

        expect do
          described_class.new.perform(rollout.id, non_existing_record_id, 'approve', user.id)
        end.not_to raise_error
      end
    end

    context 'when the user no longer exists' do
      it 'does nothing' do
        expect(::Cd::Rollouts::PushGateDecisionService).not_to receive(:new)

        expect do
          described_class.new.perform(rollout.id, request_transition.id, 'approve', non_existing_record_id)
        end.not_to raise_error
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [rollout.id, request_transition.id, 'approve', user.id] }

      before do
        allow_next_instance_of(::Cd::Rollouts::PushGateDecisionService) do |service|
          allow(service).to receive(:execute)
        end
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:job) { { 'args' => [rollout.id, request_transition.id, 'approve', user.id] } }
    let(:exception) { GRPC::Unavailable.new('kas down') }

    it 'tracks the exception with the rollout context' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        exception,
        rollout_id: rollout.id,
        request_transition_id: request_transition.id
      )

      described_class.sidekiq_retries_exhausted_block.call(job, exception)
    end
  end
end
