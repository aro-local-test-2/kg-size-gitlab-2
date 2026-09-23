# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::BatchedDispatcher, feature_category: :audit_events do
  let_it_be(:group) { create(:group) }
  let_it_be(:audit_event) { create(:audit_events_group_audit_event, group_id: group.id) }

  let(:event_name) { 'audit_operation' }
  let(:streamer) { instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination, stream_batch: nil) }

  let(:payload) do
    {
      'schema_version' => 1,
      'id' => audit_event.id.to_s,
      'event_name' => event_name,
      'group_id' => group.id,
      'namespace_ancestor_ids' => [group.id],
      'project_namespace' => false,
      'event' => audit_event.as_json(methods: [:root_group_entity_id, :stream_id])
    }
  end

  subject(:dispatcher) { described_class.new(group.id, [payload]) }

  before do
    stub_licensed_features(external_audit_events: true)
  end

  context 'with an active group destination' do
    let_it_be(:destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(destination).and_return(streamer)
    end

    it 'dispatches the batch to the destination and records circuit-breaker success' do
      expect(streamer).to receive(:stream_batch) do |bodies|
        expect(bodies.size).to eq(1)
        expect(bodies.first).to include('id' => audit_event.id.to_s, 'event_type' => event_name)
      end
      expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_success).with(destination)

      expect(dispatcher.execute).to eq(:delivered)
    end

    it 'sends multiple events as a single batched request (not per-event)' do
      expect(streamer).to receive(:stream_batch).once do |bodies|
        expect(bodies.size).to eq(2)
      end

      described_class.new(group.id, [payload, payload]).execute
    end

    context 'when the destination has filters (N+1 guard)' do
      let(:filtered_event_name) { 'member_created' }
      let(:filtered_payload) { payload.merge('event_name' => filtered_event_name) }

      before do
        create(:audit_events_group_event_type_filters,
          external_streaming_destination: destination, audit_event_type: filtered_event_name)
        create(:audit_events_streaming_group_namespace_filters, external_streaming_destination: destination)
        allow(streamer).to receive(:stream_batch)
      end

      it 'does not issue additional filter queries as the batch grows' do
        control = ActiveRecord::QueryRecorder.new { described_class.new(group.id, [filtered_payload]).execute }

        expect { described_class.new(group.id, [filtered_payload, filtered_payload, filtered_payload]).execute }
          .not_to exceed_query_limit(control)
      end
    end

    context 'when loading destinations' do
      it 'caps group destinations at the per-entity limit (defends against drift)' do
        relation = AuditEvents::Group::ExternalStreamingDestination.where(id: destination.id)
        allow(relation).to receive_messages(active: relation, preload_filters: relation)
        allow_next_found_instance_of(Group) do |group_instance|
          allow(group_instance).to receive(:external_audit_event_streaming_destinations).and_return(relation)
        end
        allow(streamer).to receive(:stream_batch)

        expect(relation).to receive(:limit).with(described_class::MAX_DESTINATIONS).and_call_original

        dispatcher.execute
      end
    end

    context 'when the destination is circuit-broken' do
      before do
        allow(AuditEvents::Streaming::CircuitBreaker).to receive(:reject_open).and_return([])
      end

      it 'does not dispatch' do
        expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

        dispatcher.execute
      end
    end

    context 'when dispatch raises a user-config error' do
      before do
        allow(streamer).to receive(:stream_batch).and_raise(URI::InvalidURIError)
      end

      it 'logs, records a circuit-breaker failure, and reports a destination error' do
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)
        expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(destination)

        expect(dispatcher.execute).to eq(:destination_error)
      end
    end

    context 'when dispatch raises a destination-side connection error' do
      before do
        allow(streamer).to receive(:stream_batch).and_raise(Errno::ECONNRESET)
      end

      it 'reports a destination error, not a GitLab-side failure' do
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)

        expect(dispatcher.execute).to eq(:destination_error)
      end
    end

    context 'when dispatch raises a GitLab-side error' do
      before do
        allow(streamer).to receive(:stream_batch).and_raise(StandardError, 'bug')
      end

      it 'tracks the exception and reports the delivery as failed' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        expect(dispatcher.execute).to eq(:failed)
      end
    end
  end

  context 'with a raising payload' do
    let_it_be(:destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    let(:other_audit_event) { create(:audit_events_group_audit_event, group_id: group.id) }
    let(:other_payload) { payload.merge('id' => other_audit_event.id.to_s) }

    subject(:dispatcher) { described_class.new(group.id, [payload, other_payload]) }

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(destination).and_return(streamer)

      allow(AuditEvents::Group::ExternalStreamingDestination)
        .to receive(:new).and_wrap_original do |method, *args|
          method.call(*args).tap do |dest|
            allow(dest).to receive(:allowed_to_stream?).and_return(true)
          end
        end
    end

    it 'tracks the offending event and still dispatches the valid ones for that destination' do
      allow(dispatcher).to receive(:reconstructed_event).and_call_original
      allow(dispatcher).to receive(:reconstructed_event)
        .with(hash_including('id' => payload['id'])).and_raise(StandardError, 'boom')

      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(kind_of(StandardError), hash_including(event_id: payload['id']))
      expect(streamer).to receive(:stream_batch) do |bodies|
        expect(bodies.map { |b| b['id'] }).to contain_exactly(other_payload['id'])
      end

      dispatcher.execute
    end
  end

  context 'with an active instance destination and no group destination' do
    let_it_be(:instance_destination) do
      create(:audit_events_instance_external_streaming_destination, :http)
    end

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(instance_destination).and_return(streamer)
    end

    it 'dispatches the batch to the instance destination' do
      expect(streamer).to receive(:stream_batch) do |bodies|
        expect(bodies.size).to eq(1)
        expect(bodies.first).to include('id' => audit_event.id.to_s, 'event_type' => event_name)
      end
      expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_success).with(instance_destination)

      dispatcher.execute
    end

    context 'when instance-level external audit events are not licensed' do
      before do
        stub_licensed_features(external_audit_events: false)
      end

      it 'does not dispatch' do
        expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

        dispatcher.execute
      end
    end
  end

  context 'with both a group and an instance destination for the same batch' do
    let_it_be(:group_destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    let_it_be(:instance_destination) do
      create(:audit_events_instance_external_streaming_destination, :http)
    end

    let(:group_streamer) { instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination) }
    let(:instance_streamer) { instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination) }

    before do
      allow(AuditEvents::Streaming::CircuitBreaker).to receive(:reject_open) { |destinations| destinations }
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(group_destination).and_return(group_streamer)
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(instance_destination).and_return(instance_streamer)
    end

    it 'dispatches the batch to both destinations and reports success' do
      expect(group_streamer).to receive(:stream_batch)
      expect(instance_streamer).to receive(:stream_batch)

      expect(dispatcher.execute).to eq(:delivered)
    end

    it 'attempts every destination and reports failure when one delivery fails' do
      allow(group_streamer).to receive(:stream_batch)
      # Instance destination is down; the group one still gets its batch.
      allow(instance_streamer).to receive(:stream_batch).and_raise(StandardError, 'destination down')

      expect(group_streamer).to receive(:stream_batch)
      expect(instance_streamer).to receive(:stream_batch)

      expect(dispatcher.execute).to eq(:failed)
    end

    it 'reports failure (not destination error) when a GitLab-side and a destination error mix' do
      allow(group_streamer).to receive(:stream_batch).and_raise(Errno::ECONNRESET)
      allow(instance_streamer).to receive(:stream_batch).and_raise(StandardError, 'bug')

      expect(dispatcher.execute).to eq(:failed)
    end
  end

  context 'with no destinations' do
    it 'does nothing and reports success (nothing to deliver)' do
      expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

      expect(dispatcher.execute).to eq(:delivered)
    end
  end
end
