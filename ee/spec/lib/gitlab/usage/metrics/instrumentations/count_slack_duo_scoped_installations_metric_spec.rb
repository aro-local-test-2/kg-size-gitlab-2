# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountSlackDuoScopedInstallationsMetric,
  feature_category: :integrations do
  let_it_be(:duo_scoped_integration) do
    create(:slack_integration, :project, authorized_scope_names: %w[commands chat:write app_mentions:read])
  end

  let_it_be(:legacy_scoped_integration) do
    create(:slack_integration, :project, authorized_scope_names: %w[commands chat:write chat:write.public])
  end

  let(:expected_value) { 1 }

  it_behaves_like 'a correct instrumented metric value', { time_frame: 'all', data_source: 'database' }
end
