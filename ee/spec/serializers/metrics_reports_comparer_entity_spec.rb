# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MetricsReportsComparerEntity, feature_category: :continuous_integration do
  let(:base_report) { build(:ci_reports_metrics_report, :base_metrics) }
  let(:head_report) { build(:ci_reports_metrics_report, :head_metrics) }
  let(:comparer) { Gitlab::Ci::Reports::Metrics::ReportsComparer.new(base_report, head_report) }
  let(:entity) { described_class.new(comparer) }

  describe '#as_json' do
    subject(:serialized_report) { entity.as_json }

    it 'contains the new metrics' do
      expect(serialized_report).to have_key(:new_metrics)
      expect(serialized_report[:new_metrics][0][:name]).to eq('extra_metric_name')
    end

    it 'contains existing metrics' do
      expect(serialized_report).to have_key(:existing_metrics)
      expect(serialized_report[:existing_metrics].count).to be(1)
    end

    it 'contains removed metrics' do
      expect(serialized_report).to have_key(:removed_metrics)
      expect(serialized_report[:removed_metrics][0][:name]).to eq('second_metric_name')
    end
  end
end
