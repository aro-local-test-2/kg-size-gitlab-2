# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountNamespacesWithAiAuditEventsStorageEnabledMetric,
  feature_category: :audit_events do
  context 'with namespaces that enabled AI audit event storage' do
    let_it_be(:enabled_groups) do
      create_list(:group, 2) do |group|
        group.namespace_settings.update!(ai_audit_events_storage_enabled: true)
      end
    end

    let_it_be(:disabled_group) { create(:group) }

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'none', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end
end
