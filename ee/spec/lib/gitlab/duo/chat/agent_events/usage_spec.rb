# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::Chat::AgentEvents::Usage, feature_category: :duo_chat do
  describe '#usage' do
    subject { described_class.new(data).usage }

    context 'with usage in data' do
      let(:data) do
        { 'usage' => { 'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 } } }
      end

      it { is_expected.to eq({ 'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 } }) }
    end

    context 'with more than one model' do
      let(:data) do
        {
          'usage' => {
            'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 },
            'claude-haiku-4-5' => { 'input_tokens' => 3, 'output_tokens' => 4 }
          }
        }
      end

      it 'keeps the counts separate per model' do
        usage = described_class.new(data).usage

        expect(usage.keys).to contain_exactly('claude-sonnet-4-5', 'claude-haiku-4-5')
        expect(usage['claude-haiku-4-5']).to eq({ 'input_tokens' => 3, 'output_tokens' => 4 })
      end
    end

    context 'with no usage' do
      let(:data) { { 'other_info' => 'hello' } }

      it { is_expected.to be_nil }
    end
  end

  describe '#metadata?' do
    it 'marks the event as metadata rather than part of the answer' do
      expect(described_class.new({ 'usage' => {} })).to be_metadata
    end
  end
end
