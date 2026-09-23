# frozen_string_literal: true

require 'fast_spec_helper'
require_relative '../../../../../../ee/app/events/ai/active_context/code/create_enabled_namespace_event'
require_relative '../../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Ai::ActiveContext::Code::CreateEnabledNamespaceEvent, feature_category: :duo_chat do
  describe '.build' do
    it 'builds a valid cloud event with the given last_processed_id', :aggregate_failures do
      event = described_class.build(last_processed_id: 42)

      expect(event.event_category).to eq(:ai_active_context_code)
      expect(event.event_type).to eq(:create_enabled_namespace)
      expect(event.data[:source]).to eq('instance')
      expect(event.data[:subject]).to eq('ai_active_context/code/enabled_namespaces')
      expect(event.event_data).to eq(last_processed_id: 42)
    end

    it 'builds a valid cloud event without a last_processed_id' do
      event = described_class.build

      expect(event.event_data).to eq(last_processed_id: nil)
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: {},
    missing_required: [],
    invalid_types: { last_processed_id: 'invalid' }

  describe '#data_schema' do
    it 'rejects unexpected properties' do
      event = described_class.build
      invalid_data = event.data.merge(data: event.event_data.merge(unexpected: 'data'))

      expect { described_class.new(data: invalid_data) }
        .to raise_error(Gitlab::EventStore::InvalidEvent, /does not match/)
    end
  end
end
