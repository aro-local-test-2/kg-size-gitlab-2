# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::DailyAggregate, feature_category: :consumables_cost_management do
  describe 'factory' do
    it 'produces a valid record' do
      expect(build(:billable_usage_daily_aggregate)).to be_valid
    end

    it 'produces a valid record with the :gauge trait' do
      expect(build(:billable_usage_daily_aggregate, :gauge)).to be_valid
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_aggregate_uuid) }
    it { is_expected.to validate_presence_of(:usage_date) }
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:unit_of_measure) }
    it { is_expected.to validate_presence_of(:feature_qualified_name) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_presence_of(:events_count) }

    it { is_expected.to validate_length_of(:event_type).is_at_most(255) }
    it { is_expected.to validate_length_of(:feature_qualified_name).is_at_most(255) }
    it { is_expected.to validate_length_of(:unit_of_measure).is_at_most(64) }
    it { is_expected.to validate_length_of(:operation_type).is_at_most(64) }

    it 'allows a nil operation_type, since only some products report one' do
      record = build(:billable_usage_daily_aggregate, operation_type: nil)

      expect(record).to be_valid
    end

    it 'accepts an event type it does not know about' do
      record = build(:billable_usage_daily_aggregate, event_type: 'some_future_event', unit_of_measure: 'executions')

      expect(record).to be_valid
    end

    describe 'events_count' do
      it 'is valid at zero' do
        record = build(:billable_usage_daily_aggregate, events_count: 0)

        expect(record).to be_valid
      end

      it 'is invalid below zero' do
        record = build(:billable_usage_daily_aggregate, events_count: -1)

        expect(record).to be_invalid
        expect(record.errors[:events_count]).to be_present
      end

      it 'is invalid when not a whole number' do
        record = build(:billable_usage_daily_aggregate, events_count: 1.5)

        expect(record).to be_invalid
        expect(record.errors[:events_count]).to be_present
      end
    end

    describe 'quantity ceiling' do
      # The ceiling comes from the downstream Iglu `billable_usage` schema, which caps
      # `quantity` at this value in every version (see described_class::MAX_QUANTITY).
      it 'is valid at MAX_QUANTITY' do
        record = build(:billable_usage_daily_aggregate, quantity: described_class::MAX_QUANTITY)

        expect(record).to be_valid
      end

      it 'is invalid above MAX_QUANTITY' do
        record = build(:billable_usage_daily_aggregate, quantity: described_class::MAX_QUANTITY + 1)

        expect(record).to be_invalid
        expect(record.errors[:quantity]).to be_present
      end

      it 'is valid at zero' do
        record = build(:billable_usage_daily_aggregate, quantity: 0)

        expect(record).to be_valid
      end

      it 'is invalid below zero' do
        record = build(:billable_usage_daily_aggregate, quantity: -1)

        expect(record).to be_invalid
        expect(record.errors[:quantity]).to be_present
      end
    end
  end

  describe 'database uniqueness' do
    let(:usage_date) { Date.current }

    it 'raises when (usage_date, event_type, feature_qualified_name) is duplicated' do
      create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
        feature_qualified_name: 'a')

      expect do
        create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
          feature_qualified_name: 'a')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permits a second record when only feature_qualified_name differs' do
      create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
        feature_qualified_name: 'a')

      expect do
        create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
          feature_qualified_name: 'b')
      end.to change { described_class.count }.by(1)
    end

    it 'permits a second record when only root_namespace_id differs' do
      create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_stored',
        feature_qualified_name: 'secrets_stored', root_namespace_id: 1)

      expect do
        create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_stored',
          feature_qualified_name: 'secrets_stored', root_namespace_id: 2)
      end.to change { described_class.count }.by(1)
    end

    it 'permits a second record when only operation_type differs' do
      create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'agent_llm',
        feature_qualified_name: 'software_development/v1', operation_type: 'regular')

      expect do
        create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'agent_llm',
          feature_qualified_name: 'software_development/v1', operation_type: 'compaction_auto')
      end.to change { described_class.count }.by(1)
    end

    # NULLS NOT DISTINCT: without it two null scopes would be treated as different rows.
    it 'raises when the tuple is duplicated and root_namespace_id is null on both' do
      create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
        feature_qualified_name: 'a', root_namespace_id: nil)

      expect do
        create(:billable_usage_daily_aggregate, usage_date: usage_date, event_type: 'secrets_read',
          feature_qualified_name: 'a', root_namespace_id: nil)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
