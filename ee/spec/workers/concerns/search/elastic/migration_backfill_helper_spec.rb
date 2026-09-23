# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::MigrationBackfillHelper, feature_category: :global_search do
  let(:migration_klass) do
    Class.new do
      include ::Search::Elastic::MigrationBackfillHelper

      const_set(:DOCUMENT_TYPE, Project)

      def batch_size
        100
      end

      def field_name
        'test_field'
      end

      def migration_state
        @migration_state ||= {}
      end

      def set_migration_state(state)
        @migration_state = migration_state.merge(state)
      end

      def log(message, **kwargs); end
      def log_warn(message, **kwargs); end
      def log_raise(message, **kwargs); end

      def helper
        Search::Elastic::Helper.new
      end

      def client
        Gitlab::Search::Client.new
      end

      def index_name
        'test_index'
      end
    end
  end

  let(:helper) { instance_double(Search::Elastic::Helper) }
  let(:client) { instance_double(Gitlab::Search::Client) }

  subject(:migration) { migration_klass.new }

  before do
    allow(migration).to receive_messages(helper: helper, client: client)
    allow(helper).to receive(:refresh_index)
  end

  describe '#migrate' do
    context 'when migration is already completed' do
      before do
        allow(client).to receive(:search)
          .and_return({ 'aggregations' => { 'documents' => { 'doc_count' => 0 } } })
      end

      it 'logs that migration is skipped' do
        allow(migration).to receive(:log)

        migration.migrate

        expect(migration).to have_received(:log).with(
          'Skipping migration since it is already applied',
          field_names: ['test_field'],
          index_name: 'test_index'
        )
      end

      it 'does not issue a batch search' do
        migration.migrate

        # Only one search call: the aggregation query from completed?
        expect(client).to have_received(:search).once
      end
    end

    context 'when migration is not completed' do
      let(:bookkeeping_service) { class_double(Elastic::ProcessInitialBookkeepingService) }

      before do
        allow(client).to receive(:search)
          .and_return(
            { 'aggregations' => { 'documents' => { 'doc_count' => 2 } } },
            { 'hits' => { 'hits' => [] } }
          )
        allow(migration).to receive(:bookkeeping_service).and_return(bookkeeping_service)
        allow(bookkeeping_service).to receive(:track!)
      end

      it 'logs start of backfilling' do
        allow(migration).to receive(:log)

        migration.migrate

        expect(migration).to have_received(:log).with(
          'Start backfilling fields',
          field_names: ['test_field'],
          index_name: 'test_index',
          batch_size: 100
        )
      end

      it 'logs completion of batch processing' do
        allow(migration).to receive(:log)

        migration.migrate

        expect(migration).to have_received(:log).with(
          'Backfilling batch has been processed',
          field_names: ['test_field'],
          index_name: 'test_index',
          documents_count: 0
        )
      end

      it 'clears the memoized document count after the batch so a subsequent completed? re-queries' do
        allow(client).to receive(:search)
          .and_return(
            { 'aggregations' => { 'documents' => { 'doc_count' => 2 } } },
            { 'hits' => { 'hits' => [] } },
            { 'aggregations' => { 'documents' => { 'doc_count' => 0 } } }
          )

        migration.migrate
        migration.completed?

        expect(client).to have_received(:search).exactly(3).times
      end

      it 'wraps missing_field_filter in an outer bool/filter to avoid scoring' do
        migration.migrate

        expect(client).to have_received(:search).with(
          index: 'test_index',
          body: include(
            query: {
              bool: {
                filter: include(
                  bool: include(minimum_should_match: 1)
                )
              }
            }
          )
        )
      end
    end

    context 'when an error occurs' do
      before do
        allow(migration).to receive(:completed?).and_raise(StandardError.new('test error'))
      end

      it 'logs the error' do
        expect(migration).to receive(:log_raise).with('migrate failed with error: StandardError:test error')

        migration.migrate
      end
    end
  end

  describe '#completed?' do
    context 'when no documents are remaining' do
      before do
        allow(client).to receive(:search)
          .and_return({ 'aggregations' => { 'documents' => { 'doc_count' => 0 } } })
      end

      it 'returns true' do
        expect(migration.completed?).to be true
      end

      it 'logs the check with document count' do
        allow(migration).to receive(:log)

        migration.completed?

        expect(migration).to have_received(:log).with(
          'Checking the number of documents without fields',
          field_names: ['test_field'],
          documents_remaining: 0
        )
      end

      it 'refreshes the index before querying' do
        migration.completed?

        expect(helper).to have_received(:refresh_index).with(index_name: 'test_index')
      end

      it 'queries with an aggregation to count documents with missing fields' do
        migration.completed?

        expect(client).to have_received(:search).with(
          index: 'test_index',
          body: include(size: 0, aggs: be_present)
        )
      end

      it 'sets migration state with documents remaining' do
        migration.completed?

        expect(migration.migration_state[:documents_remaining]).to eq(0)
      end

      it 'memoizes the document count so the index is queried only once across multiple completed? calls' do
        results = Array.new(2) { migration.completed? }

        expect(client).to have_received(:search).once
        expect(results).to all(be true)
      end

      it 'uses filter (not must) in the type clause to avoid scoring' do
        migration.completed?

        expect(client).to have_received(:search) do |args|
          filter = args[:body][:aggs][:documents][:filter]
          expect(filter[:bool]).to have_key(:filter)
          expect(filter[:bool]).not_to have_key(:must)
        end
      end
    end

    context 'when documents are remaining' do
      before do
        allow(client).to receive(:search)
          .and_return({ 'aggregations' => { 'documents' => { 'doc_count' => 10 } } })
      end

      it 'returns false' do
        expect(migration.completed?).to be false
      end
    end
  end

  describe 'processing documents' do
    let(:bookkeeping_service) { class_double(Elastic::ProcessInitialBookkeepingService) }
    let(:hits) do
      [
        { '_id' => '1', '_source' => { 'id' => 1 }, '_routing' => 'route1' },
        { '_id' => '2', '_source' => { 'id' => 2 }, '_routing' => 'route2' }
      ]
    end

    before do
      allow(migration).to receive(:bookkeeping_service).and_return(bookkeeping_service)
      allow(bookkeeping_service).to receive(:track!)
      allow(client).to receive(:search)
        .and_return(
          { 'aggregations' => { 'documents' => { 'doc_count' => 2 } } },
          { 'hits' => { 'hits' => hits } }
        )
    end

    it 'searches for documents using the correct batch size' do
      migration.migrate

      expect(client).to have_received(:search).with(
        index: 'test_index',
        body: include(size: 100)
      )
    end

    it 'tracks all document references via the bookkeeping service in a single call' do
      migration.migrate

      expect(bookkeeping_service).to have_received(:track!).once
    end

    it 'logs the number of documents processed' do
      allow(migration).to receive(:log)

      migration.migrate

      expect(migration).to have_received(:log).with(
        'Backfilling batch has been processed',
        field_names: ['test_field'],
        index_name: 'test_index',
        documents_count: 2
      )
    end

    context 'when a hit has no _routing (e.g. projects, users)' do
      let(:hits) do
        [{ '_id' => '1', '_source' => { 'id' => 1 } }]
      end

      before do
        allow(client).to receive(:search)
          .and_return(
            { 'aggregations' => { 'documents' => { 'doc_count' => 1 } } },
            { 'hits' => { 'hits' => hits } }
          )
      end

      it 'does not raise and still tracks the reference' do
        expect { migration.migrate }.not_to raise_error

        expect(bookkeeping_service).to have_received(:track!).once
      end
    end

    context 'when field_name returns an array' do
      before do
        allow(migration).to receive(:field_name).and_return(%w[field1 field2])
      end

      it 'logs with all field names' do
        allow(migration).to receive(:log)

        migration.migrate

        expect(migration).to have_received(:log).with(
          'Start backfilling fields',
          field_names: %w[field1 field2],
          index_name: 'test_index',
          batch_size: 100
        )
      end
    end

    context 'when UPDATE_BATCH_SIZE is defined on the class' do
      before do
        migration_klass.const_set(:UPDATE_BATCH_SIZE, 1)
      end

      it 'slices references into batches of that size when tracking' do
        migration.migrate

        expect(bookkeeping_service).to have_received(:track!).twice
      end
    end
  end

  describe 'search_after cursor' do
    let(:bookkeeping_service) { class_double(Elastic::ProcessInitialBookkeepingService) }
    let(:batch_size) { 2 }
    let(:full_batch) do
      [
        { '_id' => '1', '_source' => { 'id' => 1 }, 'sort' => [10] },
        { '_id' => '2', '_source' => { 'id' => 2 }, 'sort' => [11] }
      ]
    end

    let(:search_bodies) { [] }
    let(:count_response) { { 'aggregations' => { 'documents' => { 'doc_count' => 5 } } } }

    before do
      allow(migration).to receive_messages(bookkeeping_service: bookkeeping_service, batch_size: batch_size)
      allow(bookkeeping_service).to receive(:track!)
    end

    # Routes by body, not call order: the memoized count query shifts an ordered list out of
    # step. deep_dup because process_batch! maps the hits array in place.
    def stub_searches(*batch_responses)
      allow(client).to receive(:search) do |args|
        body = args[:body]
        search_bodies << body

        (body.key?(:aggs) ? count_response : batch_responses.shift).deep_dup
      end
    end

    it 'sorts by the reference primary key so the result order is stable between batches' do
      stub_searches({ 'hits' => { 'hits' => full_batch } })

      migration.migrate

      expect(search_bodies.last[:sort]).to eq([{ 'id' => { order: 'asc' } }])
    end

    it 'omits search_after on the first batch and sends it on the next one' do
      stub_searches(
        { 'hits' => { 'hits' => full_batch } },
        { 'hits' => { 'hits' => full_batch } }
      )

      migration.migrate
      migration.migrate

      batch_queries = search_bodies.select { |body| body.key?(:query) }

      expect(batch_queries.first).not_to have_key(:search_after)
      expect(batch_queries.last[:search_after]).to eq([11])
    end

    it 'persists the last hit sort value as the cursor' do
      stub_searches({ 'hits' => { 'hits' => full_batch } })

      migration.migrate

      expect(migration.migration_state[:search_after]).to eq([11])
    end

    # Negative control: without a cursor both batches issue an identical query and re-select the
    # same documents, because the async reindex has not cleared them from missing_field_filter yet.
    it 'advances past documents the previous batch already enqueued' do
      second_batch = [
        { '_id' => '3', '_source' => { 'id' => 3 }, 'sort' => [12] },
        { '_id' => '4', '_source' => { 'id' => 4 }, 'sort' => [13] }
      ]

      stub_searches(
        { 'hits' => { 'hits' => full_batch } },
        { 'hits' => { 'hits' => second_batch } }
      )

      migration.migrate
      migration.migrate

      batch_queries = search_bodies.select { |body| body.key?(:query) }

      expect(batch_queries.first[:search_after]).to be_nil
      expect(batch_queries.last[:search_after]).to eq([11])
      expect(batch_queries.first).not_to eq(batch_queries.last)
      expect(migration.migration_state[:search_after]).to eq([13])
    end

    it 'resets the cursor when a batch returns fewer hits than the batch size' do
      short_batch = [{ '_id' => '3', '_source' => { 'id' => 3 }, 'sort' => [12] }]

      stub_searches(
        { 'hits' => { 'hits' => full_batch } },
        { 'hits' => { 'hits' => short_batch } }
      )

      migration.migrate

      expect(migration.migration_state[:search_after]).to eq([11])

      migration.migrate

      expect(migration.migration_state[:search_after]).to be_nil
    end

    it 'does not advance the cursor when tracking the batch raises' do
      migration.set_migration_state(search_after: [9])
      stub_searches({ 'hits' => { 'hits' => full_batch } })
      allow(bookkeeping_service).to receive(:track!).and_raise(StandardError.new('bookkeeping down'))
      allow(migration).to receive(:log_raise)

      migration.migrate

      batch_queries = search_bodies.select { |body| body.key?(:query) }

      expect(migration).to have_received(:log_raise)
      expect(batch_queries.last[:search_after]).to eq([9])
      expect(migration.migration_state[:search_after]).to eq([9])
    end

    it 're-reads the same batch on the run after a tracking failure' do
      stub_searches(
        { 'hits' => { 'hits' => full_batch } },
        { 'hits' => { 'hits' => full_batch } }
      )
      allow(migration).to receive(:log_raise)
      allow(bookkeeping_service).to receive(:track!).and_raise(StandardError.new('bookkeeping down'))

      migration.migrate

      allow(bookkeeping_service).to receive(:track!)

      # Each worker run is a fresh object, so the count is not memoized across runs.
      migration.clear_memoization(:remaining_documents_count)

      migration.migrate

      batch_queries = search_bodies.select { |body| body.key?(:query) }

      expect(batch_queries.map { |body| body[:search_after] }).to eq([nil, nil])
      expect(migration.migration_state[:search_after]).to eq([11])
    end

    it 'clears the stored cursor once the migration completes' do
      migration.set_migration_state(search_after: [11])
      allow(client).to receive(:search).and_return(
        { 'aggregations' => { 'documents' => { 'doc_count' => 0 } } }
      )

      migration.migrate

      expect(migration.migration_state[:search_after]).to be_nil
    end

    it 'starts the next sweep from the beginning after a reset' do
      short_batch = [{ '_id' => '3', '_source' => { 'id' => 3 }, 'sort' => [12] }]

      stub_searches(
        { 'hits' => { 'hits' => full_batch } },
        { 'hits' => { 'hits' => short_batch } },
        { 'hits' => { 'hits' => full_batch } }
      )

      3.times { migration.migrate }

      batch_queries = search_bodies.select { |body| body.key?(:query) }

      expect(batch_queries.map { |body| body[:search_after] }).to eq([nil, [11], nil])
    end
  end

  describe 'when required methods are not implemented' do
    let(:incomplete_migration_klass) do
      Class.new do
        include ::Search::Elastic::MigrationBackfillHelper

        def log(message, **kwargs); end

        def log_raise(message, **_kwargs)
          raise(message)
        end

        def migration_state
          {}
        end

        def set_migration_state(_state); end

        def index_name
          'test_index'
        end
      end
    end

    subject(:incomplete_migration) { incomplete_migration_klass.new }

    before do
      allow(incomplete_migration).to receive_messages(helper: helper, client: client)
      allow(helper).to receive(:refresh_index)
    end

    it 'raises when field_name is not implemented' do
      allow(client).to receive(:search)
        .and_return({ 'aggregations' => { 'documents' => { 'doc_count' => 0 } } })

      expect { incomplete_migration.completed? }.to raise_error(NotImplementedError)
    end

    it 'raises when batch_size is not implemented' do
      incomplete_migration_klass.const_set(:DOCUMENT_TYPE, Project)
      allow(incomplete_migration).to receive(:field_name).and_return('test_field')
      allow(client).to receive(:search)
        .and_return(
          { 'aggregations' => { 'documents' => { 'doc_count' => 1 } } },
          { 'hits' => { 'hits' => [] } }
        )

      expect { incomplete_migration.migrate }.to raise_error(NotImplementedError)
    end
  end
end
