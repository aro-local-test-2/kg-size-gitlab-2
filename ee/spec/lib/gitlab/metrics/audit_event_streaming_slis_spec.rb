# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::AuditEventStreamingSlis, :prometheus, feature_category: :audit_events do
  using RSpec::Parameterized::TableSyntax

  let(:labels) { described_class::LABELS }

  before do
    described_class.initialize_slis!
  end

  describe '.initialize_slis!' do
    it 'initializes the dispatch error-rate and apdex SLIs', :aggregate_failures do
      expect(Gitlab::Metrics::Sli::ErrorRate)
        .to receive(:initialize_sli).with(described_class::DISPATCH_SLI, [labels])
      expect(Gitlab::Metrics::Sli::Apdex)
        .to receive(:initialize_sli).with(described_class::DISPATCH_SLI, [labels])

      described_class.initialize_slis!
    end

    it 'pre-creates the plain publish counters at zero so their series exist', :aggregate_failures do
      expect(publish_count).to eq(0)
      expect(consumer_unreachable_count).to eq(0)
      expect(dispatch_destination_error_count).to eq(0)
      described_class::FALLBACK_REASONS.each { |reason| expect(fallback_count(reason)).to eq(0) }
    end

    it 'names the dispatch SLI so it emits the documented gitlab_sli_ series' do
      # The framework derives gitlab_sli_<name>_total / _error_total /
      # _apdex_total series from this name; it is the contract with the docs
      # table and the runbooks catalog.
      expect(described_class::DISPATCH_SLI).to eq(:audit_event_streaming_nats_dispatch)
    end
  end

  describe '.record_publish' do
    it 'counts a publish attempt without a fallback when NATS acknowledged' do
      expect { described_class.record_publish(fallback: false) }
        .to change { publish_count }.by(1)
        .and not_change { fallback_count(:timeout) }
    end

    it 'counts both an attempt and a reason-labelled fallback when the publish fell back' do
      expect { described_class.record_publish(fallback: true, reason: :timeout) }
        .to change { publish_count }.by(1)
        .and change { fallback_count(:timeout) }.by(1)
        .and not_change { fallback_count(:connection_lost) }
    end

    it 'labels an unknown or missing reason as unexpected' do
      expect { described_class.record_publish(fallback: true, reason: :bogus) }
        .to change { fallback_count(:unexpected) }.by(1)
      expect { described_class.record_publish(fallback: true) }
        .to change { fallback_count(:unexpected) }.by(1)
    end

    it 'emits plain counter names without the gitlab_sli_ prefix', :aggregate_failures do
      expect(described_class.publish_counter.name).to eq(:gitlab_audit_event_streaming_nats_publish_total)
      expect(described_class.fallback_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_publish_fallback_total)
    end
  end

  describe '.record_publish_duration' do
    it 'observes the duration on the publish-duration histogram' do
      expect(described_class.publish_duration_histogram).to receive(:observe).with(labels, 0.25)

      described_class.record_publish_duration(0.25)
    end

    it 'ignores nil or negative durations', :aggregate_failures do
      expect(described_class).not_to receive(:publish_duration_histogram)

      described_class.record_publish_duration(nil)
      described_class.record_publish_duration(-1)
    end
  end

  describe '.record_consumer_unreachable' do
    it 'increments the consumer-unreachable counter' do
      expect { described_class.record_consumer_unreachable }
        .to change { consumer_unreachable_count }.by(1)
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.consumer_unreachable_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_consumer_unreachable_total)
    end
  end

  describe '.record_dispatch' do
    where(:result, :expected_error) do
      :success | false
      :failure | true
    end

    with_them do
      it 'maps the dispatch result to the error flag on the dispatch SLI' do
        expect(described_class.dispatch_error_rate).to receive(:increment).with(labels: labels, error: expected_error)

        described_class.record_dispatch(result: result)
      end
    end
  end

  describe '.record_dispatch_destination_error' do
    it 'increments the destination-error counter' do
      expect { described_class.record_dispatch_destination_error }
        .to change { dispatch_destination_error_count }.by(1)
    end

    it 'does not touch the dispatch SLI error rate (degradation, not an error)' do
      expect(described_class.dispatch_error_rate).not_to receive(:increment)

      described_class.record_dispatch_destination_error
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.dispatch_destination_error_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_dispatch_destination_error_total)
    end
  end

  describe '.observe_lag' do
    it 'observes the lag and scores the apdex as satisfied when under target', :aggregate_failures do
      expect(described_class.lag_histogram).to receive(:observe).with(labels, 1.5)
      expect(described_class.dispatch_lag_apdex).to receive(:increment).with(labels: labels, success: true)

      described_class.observe_lag(1.5)
    end

    it 'scores the apdex as unsatisfied when lag exceeds the target' do
      over_target = described_class::LAG_APDEX_TARGET_SECONDS + 1

      expect(described_class.dispatch_lag_apdex).to receive(:increment).with(labels: labels, success: false)

      described_class.observe_lag(over_target)
    end

    it 'ignores nil lag', :aggregate_failures do
      expect(described_class).not_to receive(:lag_histogram)
      expect(described_class).not_to receive(:dispatch_lag_apdex)

      described_class.observe_lag(nil)
    end

    it 'drops a negative lag with a debug log instead of observing it', :aggregate_failures do
      expect(Gitlab::AppJsonLogger).to receive(:debug).with(hash_including(lag_seconds: -1))
      expect(described_class.lag_histogram).not_to receive(:observe)

      described_class.observe_lag(-1)
    end
  end

  describe '.lag_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.lag_histogram

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(described_class::LAG_HISTOGRAM)
      expect(histogram.instance_variable_get(:@buckets)).to eq(described_class::LAG_BUCKETS)
    end
  end

  describe '.publish_duration_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.publish_duration_histogram

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(described_class::PUBLISH_DURATION_HISTOGRAM)
      expect(histogram.instance_variable_get(:@buckets)).to eq(described_class::PUBLISH_DURATION_BUCKETS)
    end
  end

  def publish_count
    described_class.publish_counter.get(labels)
  end

  def fallback_count(reason)
    described_class.fallback_counter.get(labels.merge(reason: reason))
  end

  def consumer_unreachable_count
    described_class.consumer_unreachable_counter.get(labels)
  end

  def dispatch_destination_error_count
    described_class.dispatch_destination_error_counter.get(labels)
  end
end
