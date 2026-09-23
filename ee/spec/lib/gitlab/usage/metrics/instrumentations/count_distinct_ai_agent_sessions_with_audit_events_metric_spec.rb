# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountDistinctAiAgentSessionsWithAuditEventsMetric,
  feature_category: :audit_events do
  context 'with time_frame all' do
    before do
      create_list(:audit_events_ai_audit_event, 2, workflow_id: 1)
      create(:audit_events_ai_audit_event, workflow_id: 2)
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end

  context 'with time_frame 28d' do
    # The 28d frame uses the Service Ping monthly window (30.days.ago..2.days.ago),
    # so events older than 30 days AND newer than 2 days ago are both excluded.
    before do
      create_list(:audit_events_ai_audit_event, 2, workflow_id: 1, created_at: 5.days.ago)
      create(:audit_events_ai_audit_event, workflow_id: 2, created_at: 40.days.ago) # too old
      create(:audit_events_ai_audit_event, workflow_id: 3, created_at: 1.day.ago)   # too recent
      create(:audit_events_ai_audit_event, workflow_id: 4, created_at: 10.days.ago)
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: '28d', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end

  context 'when no audit events exist' do
    it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' } do
      let(:expected_value) { 0 }
    end
  end
end
