# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::NatsPartitionConsumerWorker, feature_category: :audit_events do
  include ExclusiveLeaseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:audit_event) { create(:audit_events_group_audit_event, group_id: group.id) }

  let(:partition) { 3 }
  let(:event_name) { 'audit_operation' }
  let(:nats_client) { instance_double(Gitlab::Nats::Client) }
  # nats-pure mixes `fetch` into the subscription instance at runtime
  # (NATS::JetStream::PullSubscription is a private, per-instance extension),
  # so a verified double cannot be used here.
  let(:subscription) { double('NATS pull subscription', unsubscribe: nil) } # rubocop:disable RSpec/VerifiedDoubles -- see above
  let(:dispatcher) { instance_double(AuditEvents::Streaming::BatchedDispatcher, execute: :delivered) }

  let(:payload) do
    {
      schema_version: 1,
      id: audit_event.id.to_s,
      event_name: event_name,
      group_id: group.id,
      persisted: true,
      model_class: audit_event.class.name,
      namespace_ancestor_ids: [group.id],
      project_namespace: false,
      published_at: Time.current.utc.iso8601(3),
      event: audit_event.as_json(methods: [:root_group_entity_id, :stream_id])
    }
  end

  let(:message) { instance_double(NATS::Msg, data: ::Gitlab::Json.generate(payload)) }

  subject(:worker) { described_class.new }

  before do
    allow(::Gitlab::Nats).to receive_messages(enabled?: true, client: nats_client)
    allow(nats_client).to receive(:pull_subscribe)
      .with(
        AuditEvents::Streaming::NatsPartitioning.subject_for_key(partition),
        durable: AuditEvents::Streaming::NatsPartitioning.durable_for_key(partition)
      )
      .and_return(subscription)
    allow(AuditEvents::Streaming::BatchedDispatcher).to receive(:new).and_return(dispatcher)
  end

  describe '#perform' do
    context 'when there are no messages' do
      before do
        allow(subscription).to receive(:fetch).and_return([])
      end

      it_behaves_like 'an idempotent worker' do
        let(:job_args) { [partition] }
      end

      it 'dispatches nothing' do
        expect(AuditEvents::Streaming::BatchedDispatcher).not_to receive(:new)

        worker.perform(partition)
      end

      it 'unsubscribes so the shared connection does not leak the subscription' do
        expect(subscription).to receive(:unsubscribe)

        worker.perform(partition)
      end
    end

    context 'with a long drain that spans multiple fetches' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
        allow(message).to receive(:ack)
      end

      it 'renews the lease between iterations so a slow drain keeps ownership' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |lease|
          allow(lease).to receive(:try_obtain).and_return('uuid')
          expect(lease).to receive(:renew).and_return(true)
        end

        worker.perform(partition)
      end

      it 'stops draining when the lease is lost mid-run so a second drainer never overlaps' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |lease|
          allow(lease).to receive_messages(try_obtain: 'uuid', renew: false)
        end

        # Only the first batch is processed; the lost lease stops the loop
        # before the second fetch.
        expect(subscription).to receive(:fetch).once.and_return([message])

        worker.perform(partition)
      end
    end

    context 'when tearing down the subscription raises (dropped connection)' do
      before do
        allow(subscription).to receive(:fetch).and_return([])
        allow(subscription).to receive(:unsubscribe).and_raise(StandardError, 'connection closed')
      end

      it 'does not let the teardown escape and fail the job' do
        expect { worker.perform(partition) }.not_to raise_error
      end

      it 'tracks the teardown error rather than swallowing it silently' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(kind_of(StandardError))

        worker.perform(partition)
      end
    end

    context 'with a successfully dispatched message' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
      end

      it 'dispatches the group batch and acks the message' do
        expect(AuditEvents::Streaming::BatchedDispatcher).to receive(:new) do |group_id, payloads|
          expect(group_id).to eq(group.id)
          expect(payloads.size).to eq(1)
          dispatcher
        end
        expect(dispatcher).to receive(:execute).and_return(:delivered)
        expect(message).to receive(:ack)

        worker.perform(partition)
      end

      it 'records a dispatch success metric and consumer lag' do
        allow(message).to receive(:ack)

        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch)
          .with(result: :success)
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:observe_lag).with(kind_of(Numeric))

        worker.perform(partition)
      end

      it 'logs the partition and dispatched count' do
        allow(message).to receive(:ack)

        expect(worker).to receive(:log_extra_metadata_on_done).with(:partition, partition)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:dispatched_message_count, 1)

        worker.perform(partition)
      end

      context 'when lag observation fails after the messages are acked' do
        before do
          allow(message).to receive(:ack)
          allow(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:observe_lag)
            .and_raise(StandardError, 'metrics client down')
        end

        it 'keeps the recorded success and does not flip it to a failure' do
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch)
            .with(result: :success)
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_dispatch)
            .with(result: :failure)

          expect { worker.perform(partition) }.not_to raise_error
        end
      end
    end

    context 'when a destination delivery fails (execute reports failure)' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
        allow(dispatcher).to receive(:execute).and_return(:failed)
      end

      it 'leaves the message unacked for redelivery and records a failure' do
        expect(message).not_to receive(:ack)
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch)
          .with(result: :failure)

        worker.perform(partition)
      end
    end

    context 'when a destination delivery fails with a destination-side error' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
        allow(dispatcher).to receive(:execute).and_return(:destination_error)
      end

      it 'records degradation (not an SLI failure) and leaves the message unacked' do
        expect(message).not_to receive(:ack)
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch_destination_error)
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_dispatch)

        worker.perform(partition)
      end
    end

    context 'when dispatch raises unexpectedly' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
        allow(dispatcher).to receive(:execute).and_raise(StandardError, 'destination lookup failed')
      end

      it 'tracks the exception, leaves the message unacked, and records a failure' do
        expect(message).not_to receive(:ack)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(StandardError), hash_including(group_id: group.id))
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch)
          .with(result: :failure)

        expect { worker.perform(partition) }.not_to raise_error
      end
    end

    context 'when dispatch succeeds but ack fails' do
      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
        allow(dispatcher).to receive(:execute).and_return(:delivered)
        allow(message).to receive(:ack).and_raise(StandardError, 'ack failed')
      end

      it 'still records a dispatch success (the events were delivered)' do
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_dispatch)
          .with(result: :success)

        worker.perform(partition)
      end

      it 'tracks the ack error separately without raising' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(kind_of(StandardError))

        expect { worker.perform(partition) }.not_to raise_error
      end
    end

    context 'with a poison message that cannot be parsed' do
      let(:message) do
        instance_double(NATS::Msg, data: 'not-json{', subject: 'audit_events.streaming.3', metadata: nil)
      end

      before do
        allow(subscription).to receive(:fetch).and_return([message], [])
      end

      it 'tracks the discard, logs identifiers (not the body), and acks it away', :aggregate_failures do
        expect(message).to receive(:ack)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(described_class::PoisonMessageError),
            hash_including(subject: 'audit_events.streaming.3', byte_size: 'not-json{'.bytesize))
        expect(::Gitlab::AppJsonLogger).to receive(:warn) do |payload|
          expect(payload[::Labkit::Fields::LOG_MESSAGE]).to eq('Discarding unparseable NATS audit event message')
          expect(payload).not_to have_value('not-json{') # never log the raw body
        end
        expect(AuditEvents::Streaming::BatchedDispatcher).not_to receive(:new)

        worker.perform(partition)
      end
    end

    context 'with messages for multiple groups in one batch' do
      let_it_be(:other_group) { create(:group) }
      let_it_be(:other_audit_event) { create(:audit_events_group_audit_event, group_id: other_group.id) }

      let(:other_payload) do
        payload.merge(
          id: other_audit_event.id.to_s,
          group_id: other_group.id,
          event: other_audit_event.as_json(methods: [:root_group_entity_id, :stream_id])
        )
      end

      let(:other_message) { instance_double(NATS::Msg, data: ::Gitlab::Json.generate(other_payload)) }

      before do
        allow(subscription).to receive(:fetch).and_return([message, other_message], [])
      end

      it 'dispatches one batch per group and acks every message' do
        expect(message).to receive(:ack)
        expect(other_message).to receive(:ack)
        expect(AuditEvents::Streaming::BatchedDispatcher).to receive(:new).twice.and_return(dispatcher)
        expect(dispatcher).to receive(:execute).twice.and_return(:delivered)

        expect(worker).to receive(:log_extra_metadata_on_done).with(:partition, partition)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:dispatched_message_count, 2)

        worker.perform(partition)
      end
    end

    context 'when the runtime limit is reached' do
      before do
        allow(message).to receive(:ack)
        allow_next_instance_of(::Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
        allow(subscription).to receive(:fetch).and_return([message])
      end

      it 'stops draining after the current batch' do
        expect(subscription).to receive(:fetch).once

        worker.perform(partition)
      end
    end

    context 'when the pull times out because the partition is drained' do
      before do
        allow(subscription).to receive(:fetch).and_raise(::NATS::Timeout)
      end

      it 'treats the timeout as an empty batch and completes' do
        expect { worker.perform(partition) }.not_to raise_error
      end
    end

    context 'when the stream is not provisioned yet' do
      before do
        allow(nats_client).to receive(:pull_subscribe).and_raise(::NATS::JetStream::Error::NotFound)
      end

      it 'exits cleanly without raising, so the job is not retried' do
        expect(worker).to receive(:log_extra_metadata_on_done).with(:partition, partition)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped, 'stream_not_found')
        expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped_detail, kind_of(String))

        expect { worker.perform(partition) }.not_to raise_error
      end
    end

    context 'when the NATS server is unreachable' do
      before do
        allow(nats_client).to receive(:pull_subscribe)
          .and_raise(::Gitlab::Nats::Client::ConnectionError, 'NATS connection lost: connection reset')
      end

      it 'exits cleanly without raising, so a broker outage does not become a retry storm' do
        expect(worker).to receive(:log_extra_metadata_on_done).with(:partition, partition)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped, 'nats_unreachable')
        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:skipped_detail, 'NATS connection lost: connection reset')

        expect { worker.perform(partition) }.not_to raise_error
      end

      it 'records the consumer-unreachable metric so a consumer-only outage is visible' do
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_consumer_unreachable)

        worker.perform(partition)
      end
    end

    context 'with per-partition mutual exclusion' do
      let(:lease_key) { "audit_events:streaming:nats:partition:#{partition}" }

      it 'does not drain when the partition lease is already held' do
        stub_exclusive_lease_taken(lease_key)

        expect(nats_client).not_to receive(:pull_subscribe)

        worker.perform(partition)
      end

      it 'releases the lease after draining' do
        allow(subscription).to receive(:fetch).and_return([])
        expect_to_cancel_exclusive_lease(lease_key, anything)

        worker.perform(partition)
      end
    end

    context 'with the instance-scoped partition key' do
      let(:partition) { AuditEvents::Streaming::NatsPartitioning::INSTANCE_KEY }

      before do
        allow(subscription).to receive(:fetch).and_return([])
      end

      it 'subscribes to the dedicated instance subject and durable' do
        expect(nats_client).to receive(:pull_subscribe)
          .with(
            AuditEvents::Streaming::NatsPartitioning::INSTANCE_SUBJECT,
            durable: AuditEvents::Streaming::NatsPartitioning::INSTANCE_DURABLE
          )
          .and_return(subscription)

        worker.perform(partition)
      end

      context 'with an instance-scoped event (no group_id)' do
        let(:instance_payload) { payload.merge(group_id: nil) }
        let(:instance_message) { instance_double(NATS::Msg, data: ::Gitlab::Json.generate(instance_payload)) }

        before do
          allow(nats_client).to receive(:pull_subscribe).and_return(subscription)
          allow(subscription).to receive(:fetch).and_return([instance_message], [])
          allow(instance_message).to receive(:ack)
        end

        it 'dispatches the batch with a nil group_id' do
          expect(AuditEvents::Streaming::BatchedDispatcher).to receive(:new) do |group_id, _payloads|
            expect(group_id).to be_nil
            dispatcher
          end
          expect(instance_message).to receive(:ack)

          worker.perform(partition)
        end
      end
    end

    context 'when silent mode is enabled' do
      before do
        allow(::Gitlab::SilentMode).to receive(:enabled?).and_return(true)
      end

      it 'does not consume' do
        expect(nats_client).not_to receive(:pull_subscribe)

        worker.perform(partition)
      end
    end

    context 'when the consumer feature flag is disabled' do
      before do
        stub_feature_flags(audit_event_streaming_nats_consumer: false)
      end

      it 'does not consume' do
        expect(nats_client).not_to receive(:pull_subscribe)

        worker.perform(partition)
      end
    end
  end
end
