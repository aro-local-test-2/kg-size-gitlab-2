# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::Aggregations, feature_category: :global_search do
  let(:query_hash) { {} }
  let(:options) { { aggregation: true } }

  describe '#by_label_ids' do
    it 'adds size and aggs to query_hash' do
      expect(described_class.by_label_ids(query_hash: query_hash, options: options)).to eq({ size: 0,
        aggs: {
          'labels' => {
            terms: {
              field: 'label_ids',
              size: described_class::LABEL_AGGREGATION_LIMIT
            }
          }
        } })
    end

    context 'when max_size is passed' do
      it 'overrides the aggregation size' do
        expect(described_class.by_label_ids(query_hash: query_hash, options: options, max_size: 5))
          .to eq({ size: 0,
                   aggs: {
                     'labels' => {
                       terms: {
                         field: 'label_ids',
                         size: 5
                       }
                     }
                   } })
      end
    end

    context 'when options[:aggregation] is not set' do
      let(:options) { {} }

      it 'returns the query_hash unchanged' do
        expect(described_class.by_label_ids(query_hash: query_hash, options: options)).to eq(query_hash)
      end
    end
  end

  describe '#by_work_item_type_ids' do
    it 'adds size and aggs to query_hash' do
      expect(described_class.by_work_item_type_ids(query_hash: query_hash, options: options)).to eq({ size: 0,
        aggs: {
          'work_item_type_ids' => {
            terms: {
              field: 'work_item_type_id',
              size: described_class::WORK_ITEM_TYPE_AGGREGATION_LIMIT
            }
          }
        } })
    end

    context 'when max_size is passed' do
      it 'overrides the aggregation size' do
        expect(described_class.by_work_item_type_ids(query_hash: query_hash, options: options, max_size: 10))
          .to eq({ size: 0,
                   aggs: {
                     'work_item_type_ids' => {
                       terms: {
                         field: 'work_item_type_id',
                         size: 10
                       }
                     }
                   } })
      end
    end

    context 'when options[:aggregation] is not set' do
      let(:options) { {} }

      it 'returns the query_hash unchanged' do
        expect(described_class.by_work_item_type_ids(query_hash: query_hash, options: options)).to eq(query_hash)
      end
    end
  end

  describe '#by_state' do
    let(:options) { { state_aggregation: true } }

    it 'adds size and aggs to query_hash' do
      expect(described_class.by_state(query_hash: query_hash, options: options)).to eq({ size: 0,
        aggs: {
          'state' => {
            terms: {
              field: 'state'
            }
          }
        } })
    end

    context 'when only the generic options[:aggregation] is set' do
      let(:options) { { aggregation: true } }

      it 'returns the query_hash unchanged' do
        expect(described_class.by_state(query_hash: query_hash, options: options)).to eq(query_hash)
      end
    end

    context 'when no aggregation option is set' do
      let(:options) { {} }

      it 'returns the query_hash unchanged' do
        expect(described_class.by_state(query_hash: query_hash, options: options)).to eq(query_hash)
      end
    end
  end

  describe 'chaining aggregations' do
    it 'deep merges label and work_item_type_ids aggregations' do
      result = described_class.by_label_ids(query_hash: query_hash, options: options)
      result = described_class.by_work_item_type_ids(query_hash: result, options: options)

      expect(result).to eq({
        size: 0,
        aggs: {
          'labels' => {
            terms: {
              field: 'label_ids',
              size: described_class::LABEL_AGGREGATION_LIMIT
            }
          },
          'work_item_type_ids' => {
            terms: {
              field: 'work_item_type_id',
              size: described_class::WORK_ITEM_TYPE_AGGREGATION_LIMIT
            }
          }
        }
      })
    end

    it 'deep merges the state aggregation alongside the others', :aggregate_failures do
      state_options = options.merge(state_aggregation: true)
      result = described_class.by_label_ids(query_hash: query_hash, options: state_options)
      result = described_class.by_work_item_type_ids(query_hash: result, options: state_options)
      result = described_class.by_state(query_hash: result, options: state_options)

      expect(result[:size]).to eq(0)
      expect(result[:aggs].keys).to contain_exactly('labels', 'work_item_type_ids', 'state')
      expect(result.dig(:aggs, 'state')).to eq({ terms: { field: 'state' } })
    end
  end
end
