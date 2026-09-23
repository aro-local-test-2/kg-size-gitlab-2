# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountSarifSecurityScansMetric, feature_category: :service_ping do
  before_all do
    create(:security_scan, scanner_external_id: 'semgrep', created_at: 45.days.ago)
    create(:security_scan, scanner_external_id: 'semgrep', created_at: 3.days.ago)
    create(:security_scan, scanner_external_id: nil, created_at: 3.days.ago)
  end

  context 'with time_frame all' do
    let(:expected_value) { 2 }
    let(:expected_query) do
      <<~SQL.squish
        SELECT COUNT("security_scans"."build_id") FROM "security_scans"
        WHERE "security_scans"."scanner_external_id" IS NOT NULL
      SQL
    end

    it_behaves_like 'a correct instrumented metric value and query',
      { time_frame: 'all', data_source: 'database' }
  end

  context 'with time_frame 28d' do
    let(:expected_value) { 1 }
    let(:start) { 30.days.ago.to_fs(:db) }
    let(:finish) { 2.days.ago.to_fs(:db) }
    let(:expected_query) do
      <<~SQL.squish
        SELECT COUNT("security_scans"."build_id") FROM "security_scans"
        WHERE "security_scans"."scanner_external_id" IS NOT NULL
        AND "security_scans"."created_at" BETWEEN '#{start}' AND '#{finish}'
      SQL
    end

    it_behaves_like 'a correct instrumented metric value and query',
      { time_frame: '28d', data_source: 'database' }
  end
end
