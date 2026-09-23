# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::ProcessWorkflowEventWorker, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }
  let_it_be_with_reload(:event) { create(:cd_rollout_incoming_event, rollout: rollout) }

  let(:params) { { 'type' => 'com.gitlab.cd.rollout_succeeded', 'data' => {} } }

  describe '#perform' do
    it 'delegates to the event processing service with symbolized params and the claim' do
      expect_next_instance_of(::Cd::Rollouts::ProcessWorkflowEventService, rollout,
        params: { type: 'com.gitlab.cd.rollout_succeeded', data: {} }, incoming_event: event) do |service|
        expect(service).to receive(:execute).and_return(ServiceResponse.success(payload: { rollout: rollout }))
      end

      described_class.new.perform(event.id, params)
    end

    context 'when the claim does not exist' do
      it 'does nothing' do
        expect(::Cd::Rollouts::ProcessWorkflowEventService).not_to receive(:new)

        expect { described_class.new.perform(non_existing_record_id, params) }.not_to raise_error
      end
    end

    context 'when the claim is already completed' do
      before do
        event.completed!
      end

      it 'does not process the event again' do
        expect(::Cd::Rollouts::ProcessWorkflowEventService).not_to receive(:new)

        described_class.new.perform(event.id, params)
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [event.id, params] }
    end
  end
end
