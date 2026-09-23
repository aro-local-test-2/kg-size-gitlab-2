# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::ClaimWorkflowEventService, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }

  let(:idempotency_key) { 'relay-idempotency-key-1' }
  let(:params) { { 'type' => 'com.gitlab.cd.rollout_succeeded', 'data' => {} } }

  subject(:service) { described_class.new(rollout, idempotency_key: idempotency_key, params: params) }

  describe '#execute' do
    it 'claims the event and enqueues the processing worker' do
      expect(::Cd::Rollouts::ProcessWorkflowEventWorker).to receive(:perform_async)
        .with(an_instance_of(Integer), params)

      expect { service.execute }.to change { rollout.incoming_events.count }.by(1)

      expect(rollout.incoming_events.last).to have_attributes(idempotency_key: idempotency_key, status: 'pending')
    end

    context 'when the idempotency_key was already claimed' do
      before do
        create(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: idempotency_key)
      end

      it 'does not enqueue the worker again' do
        expect(::Cd::Rollouts::ProcessWorkflowEventWorker).not_to receive(:perform_async)

        expect { service.execute }.not_to change { rollout.incoming_events.count }
      end

      it 'does not raise' do
        expect { service.execute }.not_to raise_error
      end
    end

    context 'when a concurrent request wins the unique index race' do
      before do
        allow_next_instance_of(::Cd::RolloutIncomingEvent) do |event|
          allow(event).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
        end
      end

      it 'does not raise' do
        expect(::Cd::Rollouts::ProcessWorkflowEventWorker).not_to receive(:perform_async)

        expect { service.execute }.not_to raise_error
      end
    end

    context 'when the idempotency_key fails validation for a reason other than uniqueness' do
      let(:idempotency_key) { 'a' * 256 }

      it 'raises rather than silently dropping the event' do
        expect(::Cd::Rollouts::ProcessWorkflowEventWorker).not_to receive(:perform_async)

        expect { service.execute }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
