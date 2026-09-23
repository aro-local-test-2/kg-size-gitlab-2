# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountAiAuditEventsByEventNameMetric,
  feature_category: :audit_events do
  let(:empty_counts) { ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.index_with(0) }

  context 'with time_frame all' do
    before do
      create_list(:audit_events_ai_audit_event, 2, event_name: 'ai_agent_session_started')
      create(:audit_events_ai_audit_event, event_name: 'ai_tool_invoked')
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) do
        empty_counts.merge('ai_agent_session_started' => 2, 'ai_tool_invoked' => 1)
      end
    end
  end

  context 'with time_frame 28d' do
    # The 28d frame uses the Service Ping monthly window (30.days.ago..2.days.ago),
    # so events older than 30 days AND newer than 2 days ago are both excluded.
    before do
      create_list(:audit_events_ai_audit_event, 2, event_name: 'ai_llm_input_sent', created_at: 5.days.ago)
      create(:audit_events_ai_audit_event, event_name: 'ai_llm_input_sent', created_at: 40.days.ago) # too old
      create(:audit_events_ai_audit_event, event_name: 'ai_tool_invoked', created_at: 1.day.ago)     # too recent
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: '28d', data_source: 'database' } do
      let(:expected_value) { empty_counts.merge('ai_llm_input_sent' => 2) }
    end
  end

  context 'when no audit events exist' do
    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) { ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.index_with(0) }
    end
  end

  context 'when an event name outside the allowed list is stored' do
    before do
      allow(::AuditEvents::AiAuditEvent.connection).to receive(:transaction_open?).and_return(false)
      create(:audit_events_ai_audit_event, event_name: 'ai_tool_invoked')
      create(:audit_events_ai_audit_event, event_name: 'ai_retired_event')
    end

    it 'reports the stored name alongside the zero-filled allowed names' do
      expect(described_class.new(time_frame: 'all').value)
        .to eq(empty_counts.merge('ai_tool_invoked' => 1, 'ai_retired_event' => 1))
    end
  end

  context 'when the batched grouped count fails' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:should_raise_for_dev?).and_return(false)
      allow(Gitlab::Database::BatchCount).to receive(:batch_count)
        .and_raise(ActiveRecord::QueryCanceled, 'statement timeout')
      create(:audit_events_ai_audit_event, event_name: 'ai_tool_invoked')
    end

    it 'returns the -1 fallback for the whole metric' do
      expect(described_class.new(time_frame: 'all').value).to eq(-1)
    end
  end
end
