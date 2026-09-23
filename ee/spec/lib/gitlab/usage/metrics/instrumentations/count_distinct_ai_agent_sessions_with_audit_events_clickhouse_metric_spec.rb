# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountDistinctAiAgentSessionsWithAuditEventsClickhouseMetric,
  feature_category: :audit_events do
  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
  end

  describe '#available?' do
    it 'is available only when ClickHouse analytics is globally enabled', :aggregate_failures do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      expect(described_class.new(time_frame: 'all').available?).to be(true)

      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      expect(described_class.new(time_frame: 'all').available?).to be(false)
    end
  end

  def insert_ai_audit_events(rows)
    clickhouse_fixture(:ai_audit_events, rows.map do |row|
      { id: SecureRandom.uuid }.merge(row)
    end)
  end

  context 'with time_frame all', :click_house do
    before do
      insert_ai_audit_events([
        { workflow_id: 1, created_at: 5.days.ago },
        { workflow_id: 1, created_at: 4.days.ago },
        { workflow_id: 2, created_at: 40.days.ago }
      ])
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end

  context 'with time_frame 28d', :click_house do
    # Unlike the PostgreSQL variant's monthly window (30 days ago to 2 days
    # ago), the ClickHouse 28d frame extends to now, so yesterday's event counts.
    before do
      insert_ai_audit_events([
        { workflow_id: 1, created_at: 5.days.ago },
        { workflow_id: 1, created_at: 4.days.ago },
        { workflow_id: 2, created_at: 40.days.ago },
        { workflow_id: 3, created_at: 1.day.ago }
      ])
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: '28d', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end

  context 'with an unsupported time_frame' do
    it 'raises ArgumentError' do
      expect { described_class.new(time_frame: '7d').value }
        .to raise_error(ArgumentError, /Unsupported time_frame/)
    end
  end

  context 'when no audit events exist', :click_house do
    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) { 0 }
    end
  end

  context 'when ClickHouse analytics is not enabled' do
    before do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'returns the -1 fallback without querying ClickHouse' do
      expect(ClickHouse::Client).not_to receive(:select)

      expect(described_class.new(time_frame: 'all').value).to eq(-1)
    end
  end
end
