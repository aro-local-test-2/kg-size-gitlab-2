# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::TriggerContextBuilder, feature_category: :duo_agent_platform do
  let(:schema_path) do
    Rails.root.join('app/validators/json_schemas/agent_platform/agent_platform_trigger_context/1.0.0.json')
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  subject(:fields) { described_class.build(event_type: event_type, triggering_conversation: triggering_conversation) }

  shared_examples 'a schema-conformant context' do
    it 'is valid against the schema' do
      expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
    end
  end

  context 'when neither event_type nor triggering_conversation is set' do
    let(:event_type) { nil }
    let(:triggering_conversation) { nil }

    it { is_expected.to be_nil }
  end

  context 'when both are set' do
    let(:event_type) { 'mention' }
    let(:triggering_conversation) { 'explain this finding' }

    include_examples 'a schema-conformant context'

    it 'builds both fields' do
      expect(fields).to eq('event_type' => 'mention', 'triggering_conversation' => 'explain this finding')
    end
  end

  context 'when only event_type is set' do
    let(:event_type) { 'assign' }
    let(:triggering_conversation) { nil }

    it 'builds only the set field' do
      expect(fields).to eq('event_type' => 'assign')
    end
  end
end
