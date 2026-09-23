# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ingestion::BulkUpdatableTask, feature_category: :vulnerability_management do
  let_it_be(:pipeline) { create(:ci_pipeline) }
  let_it_be(:vulnerability_1) { create(:vulnerability, :with_finding, severity: :low) }
  let_it_be(:vulnerability_2) { create(:vulnerability, :with_finding, severity: :low) }

  let(:task) do
    Class.new(Security::Ingestion::AbstractTask) do
      include Gitlab::Ingestion::BulkUpdatableTask

      self.model = Vulnerability

      # Emulates a task receiving its input in an arbitrary, unsorted order.
      attr_accessor :input_attributes

      def attributes
        input_attributes
      end
    end
  end

  let(:service_object) { task.new(pipeline, []) }
  let(:ordered_ids) { [vulnerability_1.id, vulnerability_2.id].sort }

  before do
    # Provide the attributes in descending primary key order to prove
    # the module re-orders the VALUES list.
    service_object.input_attributes = ordered_ids.reverse.map do |id|
      { id: id, severity: :high }
    end
  end

  describe '#execute' do
    it 'updates the records' do
      expect { service_object.execute }
        .to change { vulnerability_1.reload.severity }.to('high')
        .and change { vulnerability_2.reload.severity }.to('high')
    end

    it 'orders the bulk update VALUES list by primary key to keep a consistent row lock order',
      :aggregate_failures do
      lower_id, higher_id = ordered_ids

      recorder = ActiveRecord::QueryRecorder.new { service_object.execute }

      bulk_updates = recorder.log.select do |query|
        query.match?(/UPDATE\s+"?vulnerabilities"?/i) && query.include?('VALUES')
      end

      expect(bulk_updates).not_to be_empty
      bulk_updates.each do |query|
        expect(query.index(/\(\s*#{lower_id}\s*,/)).to be < query.index(/\(\s*#{higher_id}\s*,/)
      end
    end

    context 'when the attributes do not contain the primary key' do
      before do
        service_object.input_attributes = [{ severity: :high }]
      end

      it 'raises a descriptive error' do
        expect { service_object.execute }
          .to raise_error(ArgumentError, /Primary key `id` not found in attribute_names/)
      end
    end
  end
end
