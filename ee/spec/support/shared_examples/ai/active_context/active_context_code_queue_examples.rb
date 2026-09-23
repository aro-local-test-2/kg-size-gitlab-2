# frozen_string_literal: true

RSpec.shared_examples 'processes Code collection queue' do
  describe 'queue processing options' do
    shared_examples 'has single shard' do
      it 'forces number_of_shards to 1' do
        expect(described_class.number_of_shards).to eq(1)
      end
    end

    shared_examples 'calculates the shard_limit from the default batch_size' do
      it 'calculates the shard_limit from the batch_size and embeddings rpm' do
        expect(described_class.shard_limit).to eq(
          described_class::TARGET_RPM_FOR_LIMITED_THROUGHPUT *
          Ai::ActiveContext::Embedding::DEFAULT_EMBEDDINGS_REQUEST_BATCH_SIZE
        )
      end
    end

    before do
      allow(described_class).to receive(:limit_throughput?).and_return(false)

      allow(Ai::ActiveContext::Embedding).to receive(:embeddings_request_batch_size).and_call_original
    end

    it 'returns default values' do
      expect(described_class.number_of_shards).to eq(1)
      expect(described_class.shard_limit).to eq(1000)
    end

    context 'when throughput is limited' do
      before do
        allow(described_class).to receive(:limit_throughput?).and_return(true)
      end

      it_behaves_like 'calculates the shard_limit from the default batch_size'
    end

    context 'when a Code collection record exists' do
      let_it_be_with_reload(:collection) { create(:ai_active_context_collection, :code_collection) }

      it 'returns default values' do
        expect(described_class.number_of_shards).to eq(1)
        expect(described_class.shard_limit).to eq(1000)
      end

      context 'when the collection queue-related options are set' do
        before do
          collection.update!(
            options: {
              queue_shard_count: 4,
              queue_shard_limit: configured_shard_limit
            }
          )
        end

        let(:configured_shard_limit) { 999 }

        it 'returns the values defined in the collection options' do
          expect(described_class.number_of_shards).to eq(4)
          expect(described_class.shard_limit).to eq(configured_shard_limit)
        end

        context 'when throughput is limited' do
          before do
            allow(described_class).to receive(:limit_throughput?).and_return(true)
          end

          it_behaves_like 'has single shard'

          it_behaves_like 'calculates the shard_limit from the default batch_size'

          context 'when the configured shard_limit is less than the calculated shard_limit' do
            let(:configured_shard_limit) { 10 }

            it 'uses the configured shard_limit' do
              expect(described_class.shard_limit).to eq(configured_shard_limit)
            end
          end

          context 'when the configured model has a custom batch size' do
            before do
              collection.update_metadata!(
                embedding_model_key => {
                  model_ref: 'model_1',
                  field: 'field_1',
                  embeddings_request_batch_size: model_batch_size
                }
              )
            end

            let(:model_batch_size) { 15 }

            it 'calculates the shard_limit from the metadata batch_size and embeddings rpm' do
              expect(described_class.shard_limit).to eq(
                described_class::TARGET_RPM_FOR_LIMITED_THROUGHPUT * model_batch_size
              )
            end
          end
        end
      end
    end
  end
end

RSpec.shared_examples 'limits throughput conditionally' do
  describe '.limit_throughput?' do
    subject(:limit_throughput) { described_class.limit_throughput? }

    context 'on saas instance' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it { is_expected.to be false }
    end

    context 'on non-saas instance' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to be true }

      context 'when in the development environment' do
        before do
          stub_rails_env('development')
        end

        it { is_expected.to be false }
      end

      context 'when a Code collection record exists' do
        let_it_be_with_reload(:collection) { create(:ai_active_context_collection, :code_collection) }

        it { is_expected.to be true }

        context 'when the embedding model is set' do
          context 'with gitlab-managed model' do
            before do
              collection.update_metadata!(
                embedding_model_key => {
                  model_type: 'gitlab_managed',
                  model_ref: 'text_embedding_005_vertex',
                  field: 'embeddings_v1',
                  dimensions: 768
                }
              )
            end

            it { is_expected.to be true }
          end

          context 'with self-hosted model' do
            before do
              collection.update_metadata!(
                embedding_model_key => {
                  model_type: 'self_hosted',
                  model_ref: '1',
                  field: 'embeddings_v1',
                  dimensions: 768
                }
              )
            end

            it { is_expected.to be false }
          end
        end
      end
    end
  end
end
