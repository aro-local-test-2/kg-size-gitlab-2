# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::References::Code, :aggregate_failures, feature_category: :code_suggestions do
  let(:collection) do
    create(:ai_active_context_collection, :code_collection)
  end

  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:project) { create(:project, group: root_namespace) }

  let(:routing) { project.id }
  let(:identifier) { 'hash-id-123' }
  let(:reference) { described_class.new(collection_id: collection.id, routing: routing, args: identifier) }

  describe '#serialize' do
    it 'serializes correctly' do
      expect(reference.serialize).to eq("#{described_class}|#{collection.id}|#{routing}|#{identifier}")
    end
  end

  describe '#operation' do
    it 'is update' do
      expect(reference.operation).to eq(:update)
    end
  end

  describe '#jsons' do
    it 'contains the identifier and ref fields' do
      expect(reference.jsons).to eq([{ unique_identifier: identifier }])
    end
  end

  describe '.preprocessors' do
    it 'returns all added preprocessors' do
      expect(described_class.preprocessors.pluck(:name)).to eq(
        [:get_content, :resolve_root_namespace, :embeddings]
      )
    end
  end

  describe '.eligible_preprocessors' do
    context 'when not in saas' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'excludes the resolve_root_namespace preprocessor' do
        expect(described_class.eligible_preprocessors.pluck(:name)).to eq(
          [:get_content, :embeddings]
        )
      end
    end

    context 'when in saas' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'includes the resolve_root_namespace preprocessor' do
        expect(described_class.eligible_preprocessors.pluck(:name)).to eq(
          [:get_content, :resolve_root_namespace, :embeddings]
        )
      end
    end
  end

  describe '.preprocess_references' do
    shared_examples 'passes the queue_name param when specified' do
      it 'passes the queue_name to the preprocessor method' do
        expect(described_class).to receive(preprocessor_method).with(
          hash_including(queue_name: 'test_queue')
        ).and_call_original

        described_class.preprocess_references(refs, queue_name: 'test_queue')
      end
    end

    let_it_be(:indexing_embedding_valid_value) do
      { model_ref: 'text_embedding_005_vertex', field: 'embeddings_v1' }
    end

    let_it_be(:collection) do
      create(:ai_active_context_collection, :code_collection).tap do |c|
        c.update_metadata!(current_indexing_embedding_model: indexing_embedding_valid_value)
      end
    end

    let(:identifier_1) { 'hash1' }
    let(:identifier_2) { 'hash2' }
    let(:reference_1) { described_class.new(collection_id: collection.id, routing: routing, args: identifier_1) }
    let(:reference_2) { described_class.new(collection_id: collection.id, routing: routing, args: identifier_2) }

    let(:refs) { [reference_1, reference_2] }

    let(:search_response) do
      [
        { 'id' => identifier_1, 'content' => 'content_1' },
        { 'id' => identifier_2, 'content' => 'content_2' }
      ]
    end

    let(:embedding_1) { [1, 2, 3] }
    let(:embedding_2) { [4, 5, 6] }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)

      allow(::ActiveContext::Logger).to receive(:info)

      allow(::ActiveContext).to receive_message_chain(:adapter, :search).and_return(search_response)
      allow(::ActiveContext).to receive_message_chain(:adapter, :full_collection_name)
        .and_return(ActiveContextHelpers.code_collection_name)

      allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
        allow(embedding_model).to receive(:generate_embeddings).with(
          %w[content_1 content_2],
          root_namespace_id: anything
        ).and_return([embedding_1, embedding_2])
      end

      allow(described_class).to receive(:fetch_content).and_call_original
      allow(described_class).to receive(:resolve_code_root_namespace).and_call_original
      allow(described_class).to receive(:apply_embeddings_by_root_namespace).and_call_original
      allow(described_class).to receive(:apply_embeddings).and_call_original
    end

    it 'processes the references successfully' do
      result = described_class.preprocess_references(refs)

      expect(result[:failed]).to be_empty

      successful_refs = result[:successful]
      expect(successful_refs).to eq([reference_1, reference_2])

      expect(successful_refs.first.root_namespace_id).to eq(root_namespace.id)
      expect(successful_refs.first.jsons).to eq(
        [
          {
            content: 'content_1',
            unique_identifier: identifier_1,
            embeddings_v1: embedding_1
          }
        ]
      )

      expect(successful_refs.second.root_namespace_id).to eq(root_namespace.id)
      expect(successful_refs.second.jsons).to eq(
        [
          {
            content: 'content_2',
            unique_identifier: identifier_2,
            embeddings_v1: embedding_2
          }
        ]
      )
    end

    describe '`get_content` pre-processor' do
      it_behaves_like 'passes the queue_name param when specified' do
        let(:preprocessor_method) { :fetch_content }
      end

      it 'calls `fetch_content` with the correct references' do
        expect(described_class).to receive(:fetch_content).with(
          hash_including(refs: [reference_1, reference_2])
        ).and_call_original

        described_class.preprocess_references(refs)
      end

      context 'when some refs do not have corresponding content' do
        let(:search_response) do
          [
            { 'id' => identifier_1, 'content' => 'content_1' }
          ]
        end

        before do
          allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
            allow(embedding_model).to receive(:generate_embeddings).with(
              %w[content_1],
              root_namespace_id: anything
            ).and_return([embedding_1])
          end
        end

        it 'calls the subsequent pre-processors with the correct references' do
          described_class.eligible_preprocessors.each_with_index do |preprocessor, idx|
            next if idx == 0 # do not check the `get_content` preprocessor

            expect(preprocessor[:block]).to receive(:call).with([reference_1], any_args).and_call_original
          end

          described_class.preprocess_references(refs)
        end

        it 'puts the refs in the correct groups' do
          expect(::ActiveContext::Logger).to receive(:exception).with(anything, hash_including(handling: :retryable))

          results = described_class.preprocess_references(refs)
          successful_refs = results[:successful]
          failed_refs = results[:failed]

          expect(successful_refs).to eq([reference_1])
          expect(successful_refs.first.jsons).to eq(
            [
              {
                content: 'content_1',
                unique_identifier: identifier_1,
                embeddings_v1: embedding_1
              }
            ]
          )

          expect(failed_refs).to eq([reference_2])
        end
      end
    end

    describe '`resolve_root_namespace` pre-processor' do
      it_behaves_like 'passes the queue_name param when specified' do
        let(:preprocessor_method) { :resolve_code_root_namespace }
      end

      it 'calls `resolve_code_root_namespace` with the correct references' do
        expect(described_class).to receive(:resolve_code_root_namespace).with(
          hash_including(refs: [reference_1, reference_2])
        ).and_call_original

        described_class.preprocess_references(refs)
      end

      context 'when not in saas' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'does not invoke the `resolve_code_root_namespace` preprocessor' do
          expect(described_class).not_to receive(:resolve_code_root_namespace)

          result = described_class.preprocess_references(refs)
          successful_refs = result[:successful]

          expect(successful_refs).to eq([reference_1, reference_2])

          expect(successful_refs.first.root_namespace_id).to be_nil
          expect(successful_refs.second.root_namespace_id).to be_nil
        end
      end
    end

    describe '`embeddings` pre-processor' do
      shared_examples 'applies embeddings' do
        it 'calls apply embeddings with the correct arguments' do
          expect(described_class).to receive(apply_embeddings_method).and_wrap_original do |method, **kwargs|
            # references should have the updated content
            passed_refs = kwargs[:refs]
            expect(passed_refs).to eq([reference_1, reference_2])
            expect(passed_refs.first.documents.pluck(:content)).to eq(['content_1'])
            expect(passed_refs.second.documents.pluck(:content)).to eq(['content_2'])

            expect(kwargs[:remove_content]).to be(false)
            method.call(**kwargs)
          end

          expect_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
            expect(embedding_model).to receive(:generate_embeddings).with(
              %w[content_1 content_2],
              root_namespace_id: embeddings_request_root_namespace_id
            ).and_return([embedding_1, embedding_2])
          end

          described_class.preprocess_references(refs)
        end

        context 'when the indexing embedding models are not set' do
          before do
            collection.reload.update_metadata!(current_indexing_embedding_model: nil)
          end

          it 'does not generate embeddings' do
            expect(::ActiveContext::EmbeddingModel).not_to receive(:new)

            result = described_class.preprocess_references(refs)
            successful_refs = result[:successful]
            failed_refs = result[:failed]

            expect(failed_refs).to be_empty

            expect(successful_refs).to eq([reference_1, reference_2])
            expect(successful_refs.first.jsons).to eq(
              [
                {
                  content: 'content_1',
                  unique_identifier: identifier_1
                }
              ]
            )
            expect(successful_refs.second.jsons).to eq(
              [
                {
                  content: 'content_2',
                  unique_identifier: identifier_2
                }
              ]
            )
          end
        end

        context 'when the embeddings generation raises an error' do
          before do
            allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
              allow(embedding_model).to receive(:generate_embeddings).and_raise(StandardError, 'Failure')
            end
          end

          it 'puts the refs in the correct groups' do
            # A plain StandardError is not in EMBEDDINGS_RETRYABLE_ERROR_TYPES.
            # The code treats this error as unexpected and logs it as an error, not a warning.
            expect(::ActiveContext::Logger).to receive(:exception).with(
              anything, hash_including(handling: :unexpected)
            )

            result = described_class.preprocess_references(refs)
            successful_refs = result[:successful]
            failed_refs = result[:failed]

            expect(successful_refs).to be_empty

            expect(failed_refs).to eq([reference_1, reference_2])
            expect(failed_refs.first.jsons).to eq(
              [
                {
                  content: 'content_1',
                  unique_identifier: identifier_1
                }
              ]
            )
            expect(failed_refs.second.jsons).to eq(
              [
                {
                  content: 'content_2',
                  unique_identifier: identifier_2
                }
              ]
            )
          end
        end

        context 'when the embeddings generation raises a declared retryable error' do
          using RSpec::Parameterized::TableSyntax

          where(:case_name, :declared_error) do
            'the AI Gateway error class'    | ::Gitlab::Llm::Embeddings::CodeEmbeddings::EmbeddingsGenerationError
            'a raw network timeout'         | ::Net::ReadTimeout
            'silent mode blocking the POST' | ::Gitlab::HTTP::SilentModeBlockedError
          end

          with_them do
            before do
              allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
                allow(embedding_model).to receive(:generate_embeddings).and_raise(declared_error, 'Failure')
              end
            end

            it 'logs it as a quiet, known-retryable failure' do
              expect(::ActiveContext::Logger).to receive(:exception).with(
                anything, hash_including(handling: :retryable)
              )

              result = described_class.preprocess_references(refs)

              expect(result[:successful]).to be_empty
              expect(result[:failed]).to eq([reference_1, reference_2])
            end
          end
        end

        context 'when the embeddings generation raises a rate limit error' do
          before do
            allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
              allow(embedding_model).to receive(:generate_embeddings).and_raise(
                ::Gitlab::Llm::Concerns::ExponentialBackoff::RateLimitError, 'Failure'
              )
            end
          end

          it 'routes the refs to infinite_retry so they retry without dead-lettering' do
            expect(::ActiveContext::Logger).to receive(:exception).with(
              anything, hash_including(handling: :infinite_retry)
            )

            result = described_class.preprocess_references(refs)

            expect(result[:successful]).to be_empty
            expect(result[:failed]).to be_empty
            expect(result[:infinite_retry]).to eq([reference_1, reference_2])
          end
        end

        shared_examples 'forwards a model-only option to apply embeddings' do |option:|
          context 'with the option specified' do
            where(:model_only) { [true, false] }

            with_them do
              it 'passes the option to the apply embeddings method' do
                expect(described_class).to receive(apply_embeddings_method).with(
                  hash_including(option => model_only)
                ).and_call_original

                described_class.preprocess_references(refs, option => model_only)
              end
            end
          end

          context 'when the option is not specified' do
            it 'defaults to false' do
              expect(described_class).to receive(apply_embeddings_method).with(
                hash_including(option => false)
              ).and_call_original

              described_class.preprocess_references(refs)
            end
          end
        end

        context 'when a next indexing embedding model is configured' do
          before do
            collection.update_metadata!(
              next_indexing_embedding_model: { model_ref: 'text_embedding_006_vertex', field: 'embeddings_v2' }
            )
          end

          describe 'next_model_only option' do
            it_behaves_like 'forwards a model-only option to apply embeddings', option: :next_model_only
          end

          describe 'current_model_only option' do
            it_behaves_like 'forwards a model-only option to apply embeddings', option: :current_model_only

            it 'only populates the current model field, never the next model field' do
              result = described_class.preprocess_references(refs, current_model_only: true)

              doc = result[:successful].first.documents.first

              expect(doc[:embeddings_v1]).to eq(embedding_1)
              expect(doc).not_to have_key(:embeddings_v2)
            end
          end
        end
      end

      context 'when in saas' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it_behaves_like 'applies embeddings' do
          let(:apply_embeddings_method) { :apply_embeddings_by_root_namespace }
          let(:embeddings_request_root_namespace_id) { root_namespace.id }
        end

        it_behaves_like 'passes the queue_name param when specified' do
          let(:preprocessor_method) { :apply_embeddings_by_root_namespace }
        end

        context 'when processing references with different root namespaces' do
          let_it_be(:root_namespace_2) { create(:group) }
          let_it_be(:project_2) { create(:project, group: root_namespace_2) }

          let(:reference_2) do
            described_class.new(collection_id: collection.id, routing: project_2.id, args: identifier_2)
          end

          before do
            allow_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
              allow(embedding_model).to receive(:generate_embeddings)
            end
          end

          it 'generates embeddings by namespace' do
            expect(described_class).to receive(:apply_embeddings_by_root_namespace).with(
              hash_including(refs: [reference_1, reference_2])
            ).and_call_original

            expect_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
              expect(embedding_model).to receive(:generate_embeddings).with(
                %w[content_1],
                root_namespace_id: root_namespace.id
              ).and_return([embedding_1])
            end.ordered
            expect_next_instance_of(::ActiveContext::EmbeddingModel) do |embedding_model|
              expect(embedding_model).to receive(:generate_embeddings).with(
                %w[content_2],
                root_namespace_id: root_namespace_2.id
              ).and_return([embedding_2])
            end.ordered

            described_class.preprocess_references(refs)
          end
        end
      end

      context 'when not in saas' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it_behaves_like 'applies embeddings' do
          let(:apply_embeddings_method) { :apply_embeddings }
          let(:embeddings_request_root_namespace_id) { nil }
        end

        it_behaves_like 'passes the queue_name param when specified' do
          let(:preprocessor_method) { :apply_embeddings }
        end
      end
    end
  end
end
