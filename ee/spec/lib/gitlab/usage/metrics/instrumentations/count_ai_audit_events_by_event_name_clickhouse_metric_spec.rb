# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountAiAuditEventsByEventNameClickhouseMetric,
  feature_category: :audit_events do
  let(:empty_counts) { ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.index_with(0) }

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
  end

  def insert_ai_audit_events(rows)
    clickhouse_fixture(:ai_audit_events, rows.map do |row|
      { id: SecureRandom.uuid }.merge(row)
    end)
  end

  describe '#available?' do
    it 'is available only when ClickHouse analytics is globally enabled', :aggregate_failures do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      expect(described_class.new(time_frame: 'all').available?).to be(true)

      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      expect(described_class.new(time_frame: 'all').available?).to be(false)
    end
  end

  context 'with events stored in ClickHouse', :click_house do
    before do
      insert_ai_audit_events([
        { event_name: 'ai_agent_session_started', created_at: 5.days.ago },
        { event_name: 'ai_agent_session_started', created_at: 5.days.ago },
        { event_name: 'ai_tool_invoked', created_at: 1.day.ago },
        { event_name: 'ai_llm_input_sent', created_at: 40.days.ago }
      ])
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) do
        empty_counts.merge('ai_agent_session_started' => 2, 'ai_tool_invoked' => 1, 'ai_llm_input_sent' => 1)
      end
    end

    # Unlike the PostgreSQL variant's monthly window (30 days ago to 2 days
    # ago), the ClickHouse 28d frame extends to now, so yesterday's event counts.
    it_behaves_like 'a correct instrumented metric value', { time_frame: '28d', data_source: 'database' } do
      let(:expected_value) do
        empty_counts.merge('ai_agent_session_started' => 2, 'ai_tool_invoked' => 1)
      end
    end
  end

  context 'when no audit events exist', :click_house do
    it 'returns all event names with zero counts' do
      expect(described_class.new(time_frame: 'all').value).to eq(empty_counts)
    end
  end

  context 'when an event name outside the allowed list is stored', :click_house do
    before do
      insert_ai_audit_events([
        { event_name: 'ai_tool_invoked', created_at: 1.day.ago },
        { event_name: 'ai_retired_event', created_at: 1.day.ago }
      ])
    end

    it 'reports the stored name alongside the zero-filled allowed names' do
      expect(described_class.new(time_frame: 'all').value)
        .to eq(empty_counts.merge('ai_tool_invoked' => 1, 'ai_retired_event' => 1))
    end
  end

  context 'with an unsupported time_frame' do
    it 'raises ArgumentError' do
      expect { described_class.new(time_frame: '7d').value }
        .to raise_error(ArgumentError, /Unsupported time_frame/)
    end
  end

  context 'when ClickHouse raises an error' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:should_raise_for_dev?).and_return(false)
      allow(ClickHouse::Client).to receive(:select)
        .and_raise(ClickHouse::Client::DatabaseError, 'connection refused')
    end

    it 'returns the -1 fallback' do
      expect(described_class.new(time_frame: 'all').value).to eq(-1)
    end
  end

  context 'when ClickHouse analytics is not enabled' do
    before do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'returns zero counts without querying ClickHouse' do
      expect(ClickHouse::Client).not_to receive(:select)

      expect(described_class.new(time_frame: 'all').value).to eq(empty_counts)
    end
  end
end
