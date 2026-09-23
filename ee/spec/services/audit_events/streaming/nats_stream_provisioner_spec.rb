# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::NatsStreamProvisioner, feature_category: :audit_events do
  include ExclusiveLeaseHelpers

  let(:client) { instance_double(Gitlab::Nats::Client) }

  before do
    allow(::Gitlab::Nats).to receive(:client).and_return(client)
  end

  describe '#ensure!' do
    context 'when the stream does not exist' do
      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(nil)
      end

      it 'creates the stream' do
        expect(client).to receive(:add_stream).with(hash_including(name: described_class::STREAM_NAME))

        expect(described_class.new.ensure!.action).to eq(:created)
      end
    end

    context 'when the stream exists and matches' do
      let(:config) do
        double('StreamConfig', # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object
          subjects: [described_class::SUBJECT_FILTER],
          num_replicas: described_class::DEFAULT_NUM_REPLICAS,
          max_age: described_class::MAX_AGE.to_i * 1_000_000_000,
          duplicate_window: described_class::DUPLICATE_WINDOW.to_i * 1_000_000_000
        )
      end

      let(:info) { double('StreamInfo', config: config) } # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object

      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(info)
      end

      it 'is a no-op' do
        expect(client).not_to receive(:add_stream)
        expect(client).not_to receive(:update_stream)

        expect(described_class.new.ensure!.action).to eq(:exists)
      end
    end

    context 'when the stream exists but drifts' do
      let(:config) do
        double('StreamConfig', # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object
          subjects: ['audit_events.streaming.old'],
          num_replicas: 1,
          max_age: 0,
          duplicate_window: 0
        )
      end

      let(:info) { double('StreamInfo', config: config) } # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object

      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(info)
      end

      it 'updates the stream' do
        expect(client).to receive(:update_stream).with(hash_including(name: described_class::STREAM_NAME))

        expect(described_class.new.ensure!.action).to eq(:updated)
      end
    end
  end

  describe '.ensure_once!' do
    it 'runs ensure! when the lease can be obtained' do
      stub_exclusive_lease(described_class::ENSURE_LEASE_KEY, 'lease-uuid')
      allow(client).to receive(:stream_info).and_return(nil)
      allow(client).to receive(:add_stream)

      expect(described_class.ensure_once!).to be_a(described_class::Result)
    end

    it 'is a no-op when the lease is already held' do
      stub_exclusive_lease_taken(described_class::ENSURE_LEASE_KEY)

      expect(client).not_to receive(:stream_info)

      expect(described_class.ensure_once!).to be_nil
    end

    it 'cancels the lease and re-raises when ensure! fails, so the next tick retries' do
      lease_uuid = 'lease-uuid'
      stub_exclusive_lease(described_class::ENSURE_LEASE_KEY, lease_uuid)
      allow(client).to receive(:stream_info).and_return(nil)
      allow(client).to receive(:add_stream).and_raise(StandardError, 'nats down')

      expect_to_cancel_exclusive_lease(described_class::ENSURE_LEASE_KEY, lease_uuid)

      expect { described_class.ensure_once! }.to raise_error(StandardError, 'nats down')
    end
  end

  describe '#desired_config' do
    subject(:config) { described_class.new.desired_config }

    it 'sets limits retention, file storage, replication, and 24h max_age' do
      expect(config).to include(
        name: described_class::STREAM_NAME,
        subjects: [described_class::SUBJECT_FILTER],
        retention: :limits,
        storage: :file,
        num_replicas: described_class::DEFAULT_NUM_REPLICAS
      )
      expect(config[:max_age]).to eq(24.hours.to_i * 1_000_000_000)
      expect(config[:duplicate_window]).to eq(described_class::DUPLICATE_WINDOW.to_i * 1_000_000_000)
    end

    it 'uses the configured stream_replicas (e.g. 3 for clustered production)' do
      allow(::Settings.nats).to receive(:stream_replicas).and_return(3)

      expect(described_class.new.desired_config[:num_replicas]).to eq(3)
    end
  end
end
