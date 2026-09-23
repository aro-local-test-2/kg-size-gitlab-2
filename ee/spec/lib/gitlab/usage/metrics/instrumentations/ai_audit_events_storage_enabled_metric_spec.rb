# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::AiAuditEventsStorageEnabledMetric,
  feature_category: :audit_events do
  using RSpec::Parameterized::TableSyntax

  where(:ai_audit_events_storage_enabled, :expected_value) do
    false | false
    true  | true
  end

  with_them do
    before do
      stub_application_setting(ai_audit_events_storage_enabled: ai_audit_events_storage_enabled)
    end

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'none' }
  end
end
