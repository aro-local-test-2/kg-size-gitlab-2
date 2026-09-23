# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::Envelope, feature_category: :duo_agent_platform do
  describe '.wrap' do
    it 'builds a Category/Content envelope with a JSON-encoded Content string' do
      envelope = described_class.wrap(category: 'some_category', fields: { 'a' => 1 })

      expect(envelope).to eq(
        'Category' => 'some_category',
        'Content' => '{"a":1}'
      )
    end

    context 'when version is given' do
      it 'adds a metadata key with the version' do
        envelope = described_class.wrap(category: 'some_category', fields: { 'a' => 1 }, version: '1.0.0')

        expect(envelope['metadata']).to eq('version' => '1.0.0')
      end
    end

    context 'when version is nil' do
      it 'omits the metadata key entirely' do
        envelope = described_class.wrap(category: 'some_category', fields: { 'a' => 1 }, version: nil)

        expect(envelope.key?('metadata')).to be(false)
      end
    end
  end
end
