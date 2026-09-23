# frozen_string_literal: true

require 'fast_spec_helper'
require_relative '../../../../../ee/app/events/search/zoekt/task_claim_expired_event'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Search::Zoekt::TaskClaimExpiredEvent, feature_category: :global_search do
  describe '.build' do
    it 'builds a valid cloud event', :aggregate_failures do
      event = described_class.build

      expect(event.event_category).to eq(:search_zoekt)
      expect(event.event_type).to eq(:task_claim_expired)
      expect(event.data[:source]).to eq('instance')
      expect(event.data[:subject]).to eq('search/zoekt/tasks')
      expect(event.event_data).to eq({})
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: {},
    missing_required: [],
    invalid_types: {}

  describe '#data_schema' do
    it 'rejects unexpected properties' do
      event = described_class.build
      invalid_data = event.data.merge(data: { unexpected: 'data' })

      expect { described_class.new(data: invalid_data) }
        .to raise_error(Gitlab::EventStore::InvalidEvent, /does not match/)
    end
  end
end
