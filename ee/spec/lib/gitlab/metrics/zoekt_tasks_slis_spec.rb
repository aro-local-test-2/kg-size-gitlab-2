# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::ZoektTasksSlis, feature_category: :global_search do
  describe '#initialize_slis!' do
    it 'initializes Apdex SLI for search_zoekt_tasks' do
      expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(:search_zoekt_tasks, [])

      described_class.initialize_slis!
    end

    it 'initializes ErrorRate SLI for search_zoekt_tasks' do
      expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(:search_zoekt_tasks, [])

      described_class.initialize_slis!
    end
  end

  describe '#increment_request_count' do
    let(:zoekt_node_id) { 1 }
    let(:task_type) { 'index' }

    it 'increments the request counter with correct labels' do
      counter = instance_double(Prometheus::Client::Counter)
      allow(described_class).to receive(:request_counter).and_return(counter)

      expect(counter).to receive(:increment).with(
        { zoekt_node: '1', task_type: 'index' },
        1
      )

      described_class.increment_request_count(zoekt_node_id: zoekt_node_id, task_type: task_type)
    end

    it 'increments by custom count when provided' do
      counter = instance_double(Prometheus::Client::Counter)
      allow(described_class).to receive(:request_counter).and_return(counter)

      expect(counter).to receive(:increment).with(
        { zoekt_node: '1', task_type: 'index' },
        5
      )

      described_class.increment_request_count(zoekt_node_id: zoekt_node_id, task_type: task_type, count: 5)
    end
  end

  describe '#increment_error_count' do
    let(:zoekt_node_id) { 2 }
    let(:task_type) { 'delete' }

    it 'increments the error rate SLI with correct labels' do
      expect(Gitlab::Metrics::Sli::ErrorRate[:search_zoekt_tasks]).to receive(:increment).with(
        labels: { zoekt_node: '2', task_type: 'delete' },
        error: true
      )

      described_class.increment_error_count(zoekt_node_id: zoekt_node_id, task_type: task_type)
    end
  end

  describe '#increment_apdex' do
    let(:zoekt_node_id) { 3 }
    let(:task_type) { 'index' }
    let(:labels) { { zoekt_node: '3', task_type: 'index' } }

    before do
      allow(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment)
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    context 'when duration is within threshold' do
      it 'increments apdex as success' do
        duration = described_class::APDEX_THRESHOLD_S - 100

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: true
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    context 'when duration exceeds threshold' do
      it 'increments apdex as failure' do
        duration = described_class::APDEX_THRESHOLD_S + 100

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: false
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    context 'when duration equals threshold' do
      it 'increments apdex as success' do
        duration = described_class::APDEX_THRESHOLD_S

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: true
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    describe 'duration histogram' do
      let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

      before do
        allow(described_class).to receive(:duration_histogram).and_return(histogram)
      end

      it 'observes the duration with the apdex labels, at full sub-second resolution' do
        expect(histogram).to receive(:observe).with(labels, 45.25)

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25)
      end

      it 'observes a duration that exceeds the apdex threshold' do
        expect(histogram).to receive(:observe).with(labels, 9000.5)

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 9000.5)
      end
    end

    describe 'histogram buckets' do
      it 'includes an exact 60 second edge' do
        expect(described_class::DURATION_BUCKETS).to include(60)
      end

      it 'declares monotonically increasing buckets' do
        expect(described_class::DURATION_BUCKETS).to eq(described_class::DURATION_BUCKETS.sort.uniq)
      end

      it 'declares integer edges so the exporter renders le="60", not le="60.0"' do
        expect(described_class::DURATION_BUCKETS).to all(be_an(Integer))
      end

      it 'registers the histogram with those buckets' do
        expect(Gitlab::Metrics).to receive(:histogram).with(
          :gitlab_search_zoekt_task_duration_seconds,
          anything,
          {},
          described_class::DURATION_BUCKETS
        ).and_return(instance_double(Prometheus::Client::Histogram, observe: nil))

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 1.0)
      end

      it 'extends beyond the apdex threshold so an outlier is not collapsed into +Inf' do
        expect(described_class::DURATION_BUCKETS.max).to be > described_class::APDEX_THRESHOLD_S
      end

      it 'includes the apdex threshold as an exact edge so the apdex ratio is re-derivable' do
        expect(described_class::DURATION_BUCKETS).to include(described_class::APDEX_THRESHOLD_S)
      end
    end

    describe 'structured log line' do
      let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

      before do
        allow(described_class).to receive(:duration_histogram).and_return(histogram)
      end

      it 'logs the duration, target, outcome and labels' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          message: 'Zoekt task Apdex SLI',
          ::Labkit::Fields::DURATION_S => 45.25,
          target_s: described_class::APDEX_THRESHOLD_S,
          success: true,
          zoekt_node: '3',
          task_type: 'index'
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25)
      end

      it 'logs success false when the duration exceeds the threshold' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(success: false, ::Labkit::Fields::DURATION_S => 9000.5)
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 9000.5)
      end
    end
  end
end
