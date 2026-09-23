# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountProjectsWithAiAuditEventsStorageEnabledMetric,
  feature_category: :audit_events do
  context 'with projects that enabled AI audit event storage' do
    let_it_be(:enabled_projects) do
      create_list(:project, 2) do |project|
        project.project_setting.update!(ai_audit_events_storage_enabled: true)
      end
    end

    let_it_be(:disabled_project) { create(:project) }

    it_behaves_like 'a correct instrumented metric value', { time_frame: 'none', data_source: 'database' } do
      let(:expected_value) { 2 }
    end
  end
end
