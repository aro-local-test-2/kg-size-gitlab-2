# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::NatsConsumerWorker, feature_category: :audit_events do
  subject(:worker) { described_class.new }

  before do
    allow(::Gitlab::Nats).to receive(:enabled?).and_return(true)
    allow(::AuditEvents::Streaming::NatsStreamProvisioner).to receive(:ensure_once!)
    allow(::AuditEvents::Streaming::NatsPartitionConsumerWorker).to receive(:bulk_perform_async)
    stub_const("AuditEvents::Streaming::NatsPartitioning::PARTITION_COUNT", 4)
  end

  describe '#perform' do
    it_behaves_like 'an idempotent worker'

    it 'fans out one drainer per partition key, including the instance lane' do
      expected_args = [[0], [1], [2], [3], [AuditEvents::Streaming::NatsPartitioning::INSTANCE_KEY]]

      expect(::AuditEvents::Streaming::NatsPartitionConsumerWorker)
        .to receive(:bulk_perform_async).with(expected_args)

      worker.perform
    end

    it 'ensures the stream (lease-guarded)' do
      expect(::AuditEvents::Streaming::NatsStreamProvisioner).to receive(:ensure_once!)

      worker.perform
    end

    it 'does not fail the run when stream provisioning raises' do
      allow(::AuditEvents::Streaming::NatsStreamProvisioner)
        .to receive(:ensure_once!).and_raise(StandardError, 'nats down')
      expect(::Gitlab::ErrorTracking).to receive(:log_exception).with(kind_of(StandardError))

      expect { worker.perform }.not_to raise_error
      expect(::AuditEvents::Streaming::NatsPartitionConsumerWorker).to have_received(:bulk_perform_async)
    end

    context 'when silent mode is enabled' do
      before do
        allow(::Gitlab::SilentMode).to receive(:enabled?).and_return(true)
      end

      it 'does nothing' do
        expect(::AuditEvents::Streaming::NatsPartitionConsumerWorker).not_to receive(:bulk_perform_async)

        worker.perform
      end
    end

    context 'when NATS is not enabled' do
      before do
        allow(::Gitlab::Nats).to receive(:enabled?).and_return(false)
      end

      it 'does nothing' do
        expect(::AuditEvents::Streaming::NatsPartitionConsumerWorker).not_to receive(:bulk_perform_async)

        worker.perform
      end
    end

    context 'when the consumer feature flag is disabled' do
      before do
        stub_feature_flags(audit_event_streaming_nats_consumer: false)
      end

      it 'does nothing' do
        expect(::AuditEvents::Streaming::NatsPartitionConsumerWorker).not_to receive(:bulk_perform_async)

        worker.perform
      end
    end
  end
end
