# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::Queues::Code, feature_category: :code_suggestions do
  before do
    allow(::ActiveContext).to receive_message_chain(:adapter, :full_collection_name)
      .and_return(ActiveContextHelpers.code_collection_name)
  end

  it_behaves_like 'processes Code collection queue' do
    let(:embedding_model_key) { :current_indexing_embedding_model }
  end

  it_behaves_like 'limits throughput conditionally' do
    let(:embedding_model_key) { :current_indexing_embedding_model }
  end

  describe '.preprocess_options' do
    it 'returns queue_name and current_model_only option set to true' do
      expect(described_class.preprocess_options).to eq({
        queue_name: 'code',
        current_model_only: true
      })
    end
  end

  describe '.extra_preprocess_options' do
    it 'returns current_model_only option set to true' do
      expect(described_class.extra_preprocess_options).to eq({ current_model_only: true })
    end
  end

  describe '.queues' do
    it 'includes the code queue' do
      expect(ActiveContext::Queues.queues).to include('ai_activecontext_queues:{code}')
    end
  end
end
