# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::UpdateEmbeddingsRequestBatchSizeService, feature_category: :global_search do
  let(:collection_class) { ::Ai::ActiveContext::Collections::Code }

  let_it_be(:connection) { create(:ai_active_context_connection, :elasticsearch) }
  let_it_be_with_reload(:collection_record) do
    create(:ai_active_context_collection, :code_collection, connection: connection)
  end

  let(:for_next_model) { false }
  let(:batch_size) { 25 }

  let_it_be(:embedding_model_metadata) do
    {
      model_ref: 'text_embedding_005_vertex',
      model_type: 'gitlab_managed',
      field: 'embeddings_v1'
    }
  end

  subject(:execute) do
    described_class.new(
      collection_class: collection_class,
      batch_size: batch_size,
      for_next_model: for_next_model
    ).execute
  end

  shared_examples 'updates the indexing model' do
    it 'updates the batch size and returns a success response' do
      expect(execute).to be_success

      expect(collection_record.reload.public_send(indexing_model).symbolize_keys)
        .to eq(embedding_model_metadata.merge(embeddings_request_batch_size: batch_size))
    end

    context 'when the batch_size is nil' do
      let(:batch_size) { nil }

      it 'updates the batch size and returns a success response' do
        expect(execute).to be_success

        expect(collection_record.reload.public_send(indexing_model).symbolize_keys)
          .to eq(embedding_model_metadata.merge(embeddings_request_batch_size: nil))
      end
    end

    context 'when the batch_size is invalid' do
      let(:batch_size) { 0 }

      it 'returns an error response and does not update the metadata' do
        expect(execute).to be_error
        expect(execute.message).to match(/Ai::ActiveContext::Collection/)

        expect(collection_record.reload.public_send(indexing_model))
          .not_to have_key('embeddings_request_batch_size')
      end
    end

    context 'when an unexpected error is raised' do
      before do
        allow(collection_record).to receive(:update_metadata!).and_raise(StandardError, 'some error')
      end

      it 'logs the error and returns a generic error response' do
        logger = ::Logger.new(File::NULL)
        allow(::ActiveContext::Config).to receive(:logger).and_return(logger)

        expect(logger).to receive(:error).with(
          hash_including(
            'message' => 'some error',
            'error_class' => 'StandardError'
          )
        )

        expect(execute).to be_error
        expect(execute.message).to eq('unexpected error')
      end
    end
  end

  describe '#execute' do
    context 'when the collection record does not exist' do
      before do
        allow(collection_class).to receive(:collection_record).and_return(nil)
      end

      it 'returns an error response' do
        expect(execute).to be_error
        expect(execute.message).to eq('collection_record not found')
      end
    end

    context 'when the collection record exists' do
      before do
        allow(collection_class).to receive(:collection_record).and_return(collection_record)
      end

      context 'when the current indexing model is not set' do
        it 'returns an error response' do
          expect(execute).to be_error
          expect(execute.message).to eq("current_indexing_embedding_model not set")
        end
      end

      context 'when the current indexing model is set' do
        before do
          collection_record.update_metadata!(current_indexing_embedding_model: embedding_model_metadata)
        end

        it_behaves_like 'updates the indexing model' do
          let(:indexing_model) { :current_indexing_embedding_model }
        end

        context 'when the batch size exceeds the default for a gitlab-managed model' do
          let(:batch_size) { 31 }

          it 'returns an error response' do
            expect(execute).to be_error
            expect(execute.message).to eq(
              "embeddings request batch size for model 'text_embedding_005_vertex' must not exceed 30"
            )
          end
        end

        context 'when the search model is not set' do
          before do
            collection_record.update_metadata!(search_embedding_model: nil)
          end

          it 'does not update the search model' do
            execute

            expect(collection_record.reload.search_embedding_model).to be_nil
          end
        end

        context 'when the search model is set' do
          before do
            collection_record.update_metadata!(search_embedding_model: embedding_model_metadata)
          end

          it 'updates the search embedding model batch size' do
            expect(execute).to be_success

            expect(collection_record.reload.search_embedding_model.symbolize_keys)
              .to eq(embedding_model_metadata.merge(embeddings_request_batch_size: batch_size))
          end
        end

        context 'when there is a next indexing model' do
          before do
            collection_record.update_metadata!(next_indexing_embedding_model: embedding_model_metadata)
          end

          it 'returns an error response and does not update the metadata' do
            response = execute

            expect(response).to be_error
            expect(response.message).to eq(
              'cannot update current embedding model batch size while switching to a new embedding model'
            )

            expect(collection_record.reload.current_indexing_embedding_model)
              .not_to have_key('embeddings_request_batch_size')
          end
        end
      end

      context 'for next indexing model' do
        let(:for_next_model) { true }

        context 'when the next indexing model is not set' do
          it 'returns an error response' do
            expect(execute).to be_error
            expect(execute.message).to eq("next_indexing_embedding_model not set")
          end
        end

        context 'when the next indexing model is set' do
          before do
            collection_record.update_metadata!(next_indexing_embedding_model: embedding_model_metadata)
          end

          context 'when `BackfillEmbeddings` does not exist' do
            it 'returns an error response' do
              response = execute

              expect(response).to be_error
              expect(response.message).to eq(
                'no backfill task present; there is no need to update the next embedding model batch size'
              )
            end
          end

          context 'when the latest `BackfillEmbeddings` task is completed' do
            before do
              create(
                :ai_active_context_task,
                :completed,
                connection: connection,
                name: Ai::ActiveContext::Tasks::BackfillEmbeddings.name,
                params: { 'collection' => collection_record.name_without_prefix }
              )
            end

            it 'returns an error response' do
              response = execute

              expect(response).to be_error
              expect(response.message).to eq(
                'backfill already completed for the new embedding model; ' \
                  'update the current embedding model batch size once the switch is complete'
              )
            end
          end

          context 'when the latest `BackfillEmbeddings` task is not completed' do
            before do
              create(
                :ai_active_context_task,
                :in_progress,
                connection: connection,
                name: Ai::ActiveContext::Tasks::BackfillEmbeddings.name,
                params: { 'collection' => collection_record.name_without_prefix }
              )
            end

            it_behaves_like 'updates the indexing model' do
              let(:indexing_model) { :next_indexing_embedding_model }
            end

            context 'when the batch size exceeds the default for a gitlab-managed model' do
              let(:batch_size) { 31 }

              it 'returns an error response' do
                expect(execute).to be_error
                expect(execute.message).to eq(
                  "embeddings request batch size for model 'text_embedding_005_vertex' must not exceed 30"
                )
              end
            end

            context 'when the `UpdateCollectionMetadata` task exists' do
              let_it_be(:task_metadata) do
                {
                  'current_indexing_embedding_model' => embedding_model_metadata.stringify_keys,
                  'search_embedding_model' => embedding_model_metadata.stringify_keys
                }
              end

              let_it_be(:update_collection_metadata_task) do
                create(
                  :ai_active_context_task,
                  connection: connection,
                  name: Ai::ActiveContext::Tasks::UpdateCollectionMetadata.name,
                  params: { 'metadata' => task_metadata, 'collection' => collection_record.name_without_prefix }
                )
              end

              it 'sets the batch size on each model and leaves the other fields unchanged' do
                response = execute
                expect(response).to be_success

                model_with_batch_size = embedding_model_metadata.stringify_keys.merge(
                  'embeddings_request_batch_size' => batch_size
                )

                expect(update_collection_metadata_task.reload.params['metadata']).to eq(
                  'current_indexing_embedding_model' => model_with_batch_size,
                  'search_embedding_model' => model_with_batch_size
                )
              end

              context 'when there is an error when updating the task params' do
                let(:logger) { ::Logger.new(File::NULL) }

                before do
                  allow(::ActiveContext::Config).to receive(:logger).and_return(logger)

                  allow(Ai::ActiveContext::Task).to receive(:latest_by_name_and_collection).and_call_original
                  allow(Ai::ActiveContext::Task).to receive(:latest_by_name_and_collection).with(
                    name: Ai::ActiveContext::Tasks::UpdateCollectionMetadata.name,
                    collection_name: collection_record.name_without_prefix
                  ).and_return(update_collection_metadata_task)
                  allow(update_collection_metadata_task).to receive(:update!).and_raise(StandardError, 'some error')
                end

                it 'logs the error and still returns a success response' do
                  expect(logger).to receive(:error).with(
                    hash_including(
                      'message' => 'model_switching_task_sync_failed',
                      'details' => 'failed to update the `UpdateCollectionMetadata` metadata params, skipping',
                      'error_class' => 'StandardError'
                    )
                  )

                  expect(execute).to be_success
                end
              end
            end

            context 'when `UpdateCollectionMetadata` does not exist' do
              it 'updates the next indexing model and returns a success response' do
                response = execute

                expect(response).to be_success
                expect(collection_record.reload.next_indexing_embedding_model.symbolize_keys)
                  .to eq(embedding_model_metadata.merge(embeddings_request_batch_size: batch_size))
              end
            end

            context 'when the search model is not set' do
              before do
                collection_record.update_metadata!(search_embedding_model: nil)
              end

              it 'does not update the search model' do
                execute

                expect(collection_record.reload.search_embedding_model).to be_nil
              end
            end

            context 'when the search model is set' do
              before do
                collection_record.update_metadata!(search_embedding_model: embedding_model_metadata)
              end

              it 'does not update the search model batch size' do
                expect { execute }.not_to change {
                  collection_record.reload.search_embedding_model[:embeddings_request_batch_size]
                }
              end
            end
          end
        end
      end
    end
  end
end
