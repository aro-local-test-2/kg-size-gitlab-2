# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::ScopeHandlers::Groups, :elastic, :sidekiq_inline, feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:groups) do
    (1..25).map { |n| create(:group, :public, name: format('test-group-%02d', n)) }
  end

  let(:order_by) { nil }
  let(:sort) { nil }

  let(:search_results) do
    Gitlab::SearchResults.new(user, 'test-group', order_by: order_by, sort: sort, filters: {})
  end

  let(:handler) { described_class.new(search_results) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    ::Elastic::ProcessInitialBookkeepingService.track!(*groups)
    ensure_elasticsearch_index!
  end

  describe '.scope_name' do
    it 'returns groups' do
      expect(described_class.scope_name).to eq('groups')
    end
  end

  describe '#objects' do
    it 'returns the first page sized by per_page' do
      results = handler.objects(page: 1, per_page: 20)

      expect(results.size).to eq(20)
    end

    it 'returns the remaining records on page 2' do
      results = handler.objects(page: 2, per_page: 20)

      expect(results.size).to eq(5)
    end

    it 'does not overlap records between pages' do
      page1 = handler.objects(page: 1, per_page: 10).map(&:id)
      page2 = described_class.new(search_results).objects(page: 2, per_page: 10).map(&:id)

      expect(page1 & page2).to be_empty
    end

    it 'exposes the total count from Elasticsearch, not the size of the page' do
      results = handler.objects(page: 1, per_page: 20)

      expect(results.total_count).to eq(25)
      expect(results.total_pages).to eq(2)
    end

    it 'preloads routes so rendering full_path does not N+1' do
      results = handler.objects(page: 1, per_page: 20)

      expect(results.first.association(:route)).to be_loaded
    end

    context 'when sorting by created_at' do
      let(:order_by) { 'created_at' }
      let(:sort) { 'asc' }

      it 'applies the sort from the search results, not from filters' do
        ids = handler.objects(page: 1, per_page: 25).map(&:id)

        expect(ids).to eq(groups.sort_by(&:created_at).map(&:id))
      end
    end

    context 'with an order_by the sort map does not cover' do
      let(:order_by) { 'name' }
      let(:sort) { 'asc' }

      it 'returns results instead of raising' do
        results = handler.objects(page: 1, per_page: 20)

        expect(results.size).to eq(20)
        expect(results.total_count).to eq(25)
      end
    end
  end

  describe '#count' do
    it 'returns the Elasticsearch total count' do
      expect(handler.count).to eq(25)
    end

    it 'caps the count at ELASTIC_COUNT_LIMIT' do
      allow(handler).to receive(:total_count).and_return(50_000)

      expect(handler.count).to eq(::Gitlab::Elastic::SearchResults::ELASTIC_COUNT_LIMIT)
    end

    it 'does not cap at the basic search COUNT_LIMIT' do
      allow(handler).to receive(:total_count).and_return(500)

      expect(handler.count).to eq(500)
    end
  end

  describe 'private group visibility' do
    let_it_be(:private_group) { create(:group, :private, name: 'test-group-private') }

    before do
      ::Elastic::ProcessInitialBookkeepingService.track!(private_group)
      ensure_elasticsearch_index!
    end

    context 'when the user is a member' do
      before_all do
        private_group.add_developer(user)
      end

      it 'returns the private group' do
        ids = handler.objects(page: 1, per_page: 30).map(&:id)

        expect(ids).to include(private_group.id)
      end
    end

    context 'when the user is not a member' do
      it 'does not return the private group' do
        ids = handler.objects(page: 1, per_page: 30).map(&:id)

        expect(ids).not_to include(private_group.id)
      end
    end
  end

  describe 'group level search' do
    let_it_be(:parent_group) { create(:group, :public, name: 'test-parent') }
    let_it_be(:subgroup) { create(:group, :public, parent: parent_group, name: 'test-child') }
    let_it_be(:nested_subgroup) { create(:group, :public, parent: subgroup, name: 'test-grandchild') }

    let(:search_results) do
      Gitlab::GroupSearchResults.new(user, 'test', group: parent_group, filters: {})
    end

    before do
      ::Elastic::ProcessInitialBookkeepingService.track!(parent_group, subgroup, nested_subgroup)
      ensure_elasticsearch_index!
    end

    it 'returns descendants of the searched group and excludes the group itself' do
      expect(handler.objects(page: 1, per_page: 30)).to contain_exactly(subgroup, nested_subgroup)
    end

    it 'does not return groups outside the searched group' do
      ids = handler.objects(page: 1, per_page: 30).map(&:id)

      expect(ids).not_to include(*groups.map(&:id))
    end

    it 'scopes the search to the shard holding the hierarchy' do
      expect(::Gitlab::Search::Client).to receive(:execute_search)
        .with(query: anything, options: hash_including(root_ancestor_ids: [parent_group.id]))
        .and_call_original

      handler.objects(page: 1, per_page: 30)
    end

    context 'when the searched group is itself a subgroup' do
      let(:search_results) do
        Gitlab::GroupSearchResults.new(user, 'test', group: subgroup, filters: {})
      end

      it 'scopes by the root ancestor, not the searched group' do
        expect(::Gitlab::Search::Client).to receive(:execute_search)
          .with(query: anything, options: hash_including(root_ancestor_ids: [parent_group.id]))
          .and_call_original

        expect(handler.objects(page: 1, per_page: 30)).to contain_exactly(nested_subgroup)
      end
    end
  end

  describe 'global group search' do
    it 'is not scoped to a hierarchy' do
      expect(::Gitlab::Search::Client).to receive(:execute_search)
        .with(query: anything, options: hash_excluding(:root_ancestor_ids))
        .and_call_original

      handler.objects(page: 1, per_page: 20)
    end
  end

  describe '#highlight_map' do
    it 'returns highlights keyed by group id' do
      handler.objects(page: 1, per_page: 20)

      expect(handler.highlight_map.each_value.first.keys).to include('name')
    end
  end

  describe 'when advanced search is disabled' do
    before do
      stub_ee_application_setting(elasticsearch_search: false)
    end

    it 'does not query Elasticsearch and falls back to basic search' do
      expect(::Gitlab::Search::Client).not_to receive(:execute_search)

      expect(handler.objects(page: 1, per_page: 20).size).to eq(20)
      expect(handler.count).to eq(25)
    end
  end

  describe 'when the backfill migration has not finished' do
    before do
      set_elasticsearch_migration_to(:backfill_groups_to_elasticsearch, including: false)
    end

    it 'does not query Elasticsearch and falls back to basic search' do
      expect(::Gitlab::Search::Client).not_to receive(:execute_search)

      expect(handler.objects(page: 1, per_page: 20).size).to eq(20)
      expect(handler.count).to eq(25)
    end
  end

  describe '#formatted_count' do
    it 'returns the count as a string when below the limit' do
      expect(handler.formatted_count).to eq('25')
    end

    it 'returns a delimited count when below the limit' do
      allow(handler).to receive(:total_count).and_return(1234)

      expect(handler.formatted_count).to eq('1,234')
    end

    it 'returns the delimited Elasticsearch limit message when at the limit' do
      allow(handler).to receive(:total_count).and_return(::Gitlab::Elastic::SearchResults::ELASTIC_COUNT_LIMIT)

      expect(handler.formatted_count).to eq('10,000+')
    end

    it 'returns the delimited Elasticsearch limit message when above the limit' do
      allow(handler).to receive(:total_count).and_return(50_000)

      expect(handler.formatted_count).to eq('10,000+')
    end
  end
end
