# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::RecordAggregateService, feature_category: :consumables_cost_management do
  let(:aggregate_class) { Utilization::BillableUsage::DailyAggregate }

  let(:context) do
    {
      event_type: 'secrets_read',
      unit_of_measure: 'request',
      timestamp: '2026-08-10T09:15:00Z',
      quantity: 1,
      root_namespace_id: 1,
      metadata: { feature_qualified_name: 'secrets_read', pipeline_id: 7 }
    }
  end

  def execute(context, quantity_kind: Gitlab::BillingEvents::Client::COUNTER, **options)
    described_class.new(context, quantity_kind: quantity_kind, **options).execute
  end

  def find_aggregate(
    feature_qualified_name: 'secrets_read', event_type: 'secrets_read', root_namespace_id: 1,
    operation_type: nil)
    aggregate_class.find_by!(event_type: event_type, feature_qualified_name: feature_qualified_name,
      root_namespace_id: root_namespace_id, operation_type: operation_type)
  end

  describe '#execute' do
    context 'with a counter quantity kind' do
      it 'accumulates quantity and events_count across repeated executions', :aggregate_failures do
        3.times { execute(context) }

        expect(aggregate_class.count).to eq(1)

        aggregate = find_aggregate
        expect(aggregate.quantity).to eq(3)
        expect(aggregate.events_count).to eq(3)
        expect(aggregate.unit_of_measure).to eq('request')
        expect(aggregate.schema_version).to eq(1)
      end

      it 'folds in a batched write as its whole events_count', :aggregate_failures do
        execute(context.merge(quantity: 10), events_count: 4)

        aggregate = find_aggregate
        expect(aggregate.quantity).to eq(10)
        expect(aggregate.events_count).to eq(4)

        execute(context.merge(quantity: 6), events_count: 3)

        aggregate = find_aggregate
        expect(aggregate.quantity).to eq(16)
        expect(aggregate.events_count).to eq(7)
      end
    end

    context 'with a snapshot quantity kind' do
      it 'replaces quantity but keeps incrementing events_count', :aggregate_failures do
        execute(context.merge(quantity: 1150), quantity_kind: Gitlab::BillingEvents::Client::SNAPSHOT)
        execute(context.merge(quantity: 1162), quantity_kind: Gitlab::BillingEvents::Client::SNAPSHOT)

        expect(aggregate_class.count).to eq(1)

        aggregate = find_aggregate
        expect(aggregate.quantity).to eq(1162)
        expect(aggregate.events_count).to eq(2)
      end
    end

    context 'with more than one root namespace' do
      it 'keeps a separate row per scope rather than folding them together', :aggregate_failures do
        3.times { execute(context.merge(root_namespace_id: 1)) }
        2.times { execute(context.merge(root_namespace_id: 2)) }

        expect(aggregate_class.count).to eq(2)
        expect(find_aggregate(root_namespace_id: 1).quantity).to eq(3)
        expect(find_aggregate(root_namespace_id: 2).quantity).to eq(2)
      end

      it 'replaces a snapshot within its own scope only', :aggregate_failures do
        snapshot = Gitlab::BillingEvents::Client::SNAPSHOT

        execute(context.merge(root_namespace_id: 1, quantity: 10), quantity_kind: snapshot)
        execute(context.merge(root_namespace_id: 2, quantity: 20), quantity_kind: snapshot)
        execute(context.merge(root_namespace_id: 1, quantity: 11), quantity_kind: snapshot)

        expect(aggregate_class.count).to eq(2)
        expect(find_aggregate(root_namespace_id: 1).quantity).to eq(11)
        expect(find_aggregate(root_namespace_id: 2).quantity).to eq(20)
      end

      it 'derives a different event_aggregate_uuid per scope' do
        execute(context.merge(root_namespace_id: 1))
        execute(context.merge(root_namespace_id: 2))

        expect(find_aggregate(root_namespace_id: 1).event_aggregate_uuid)
          .not_to eq(find_aggregate(root_namespace_id: 2).event_aggregate_uuid)
      end
    end

    context 'with more than one operation type' do
      let(:dap_context) do
        context.merge(event_type: 'duo_agent_platform_workflow_completion',
          metadata: { feature_qualified_name: 'software_development/v1' })
      end

      it 'keeps a separate row per operation type', :aggregate_failures do
        4.times { execute(dap_context.merge(metadata: dap_context[:metadata].merge(operation_type: 'regular'))) }
        execute(dap_context.merge(metadata: dap_context[:metadata].merge(operation_type: 'compaction_auto')))

        expect(aggregate_class.count).to eq(2)
        expect(find_aggregate(feature_qualified_name: 'software_development/v1',
          event_type: 'duo_agent_platform_workflow_completion', operation_type: 'regular').quantity).to eq(4)
        expect(find_aggregate(feature_qualified_name: 'software_development/v1',
          event_type: 'duo_agent_platform_workflow_completion', operation_type: 'compaction_auto').quantity).to eq(1)
      end

      it 'derives a different event_aggregate_uuid per operation type' do
        execute(dap_context.merge(metadata: dap_context[:metadata].merge(operation_type: 'regular')))
        execute(dap_context.merge(metadata: dap_context[:metadata].merge(operation_type: 'compaction_auto')))

        uuids = aggregate_class.pluck(:event_aggregate_uuid)
        expect(uuids.uniq.size).to eq(2)
      end
    end

    it 'computes a stable, deterministic event_aggregate_uuid', :aggregate_failures do
      2.times { execute(context) }

      expected_uuid = Digest::UUID.uuid_v5(
        Gitlab::GlobalAnonymousId.instance_uuid,
        '["2026-08-10","secrets_read","secrets_read",1,null]'
      )

      expect(aggregate_class.count).to eq(1)
      expect(find_aggregate.event_aggregate_uuid).to eq(expected_uuid)
    end

    context 'when metadata.feature_qualified_name is missing' do
      let(:context_without_feature_name) { context.merge(metadata: { pipeline_id: 7 }) }

      it 'logs an error and does not persist a row', :aggregate_failures do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(
            message: 'BillingEvents: aggregate not recorded, metadata.feature_qualified_name is missing'
          )
        )

        expect { execute(context_without_feature_name) }.not_to change { aggregate_class.count }
      end
    end

    context 'when the record is invalid' do
      let(:invalid_context) { context.merge(quantity: Utilization::BillableUsage::DailyAggregate::MAX_QUANTITY + 1) }

      it 'logs an error and does not persist a row', :aggregate_failures do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(message: 'BillingEvents: aggregate not recorded, record is invalid')
        )

        expect { execute(invalid_context) }.not_to change { aggregate_class.count }
      end
    end

    describe 'usage_date derivation' do
      where(:timestamp, :expected_usage_date) do
        [
          ['2026-08-10T23:30:00+02:00', Date.new(2026, 8, 10)],
          ['2026-08-11T00:30:00+02:00', Date.new(2026, 8, 10)]
        ]
      end

      with_them do
        it 'derives usage_date from the timestamp in UTC' do
          execute(context.merge(timestamp: timestamp))

          expect(find_aggregate.usage_date).to eq(expected_usage_date)
        end
      end
    end

    it 'creates distinct rows for distinct feature_qualified_name values', :aggregate_failures do
      execute(context.merge(event_type: 'code_review', metadata: { feature_qualified_name: 'code_review/v1' }))
      execute(context.merge(event_type: 'code_review', metadata: { feature_qualified_name: 'code_review/v2' }))

      expect(aggregate_class.where(event_type: 'code_review').count).to eq(2)
      expect(aggregate_class.where(event_type: 'code_review').pluck(:feature_qualified_name))
        .to contain_exactly('code_review/v1', 'code_review/v2')
    end
  end
end
