# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::Queues::CodeBackfill, feature_category: :code_suggestions do
  before do
    allow(::ActiveContext).to receive_message_chain(:adapter, :full_collection_name)
      .and_return(ActiveContextHelpers.code_collection_name)
  end

  describe 'inheritance' do
    it 'inherits from Code queue' do
      expect(described_class).to be < Ai::ActiveContext::Queues::Code
    end
  end

  it_behaves_like 'processes Code collection queue' do
    let(:embedding_model_key) { :next_indexing_embedding_model }
  end

  it_behaves_like 'limits throughput conditionally' do
    let(:embedding_model_key) { :next_indexing_embedding_model }
  end

  describe '.preprocess_options' do
    it 'returns queue_name and next_model_only option set to true' do
      expect(described_class.preprocess_options).to eq({
        queue_name: 'code_backfill',
        next_model_only: true
      })
    end
  end

  describe '.extra_preprocess_options' do
    it 'returns next_model_only option set to true' do
      expect(described_class.extra_preprocess_options).to eq({ next_model_only: true })
    end
  end

  describe '.queues' do
    it 'includes the code backfill queue' do
      expect(ActiveContext::Queues.queues).to include('ai_activecontext_queues:{code_backfill}')
    end
  end
end
