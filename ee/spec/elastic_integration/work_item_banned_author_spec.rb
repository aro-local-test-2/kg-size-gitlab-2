# frozen_string_literal: true

require 'spec_helper'

# Postgres hides a banned author's work items with a live anti-join
# (Issue.without_hidden), but Elasticsearch stores Issue#hidden? at index time.
# The ban fan-out in EE::Users::BannedUser covers project level work items; it
# skipped group level ones, whose documents stayed visible after a ban.
RSpec.describe 'Work item search follows the author ban state', :elastic_delete_by_query, :sidekiq_inline,
  feature_category: :global_search do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :public, group: group) }

  # freeze: false, because the examples ban this user. A plain let_it_be record
  # is deep-frozen and `ban!` raises FrozenError.
  let_it_be_with_reload(:author) { create(:user) }

  let_it_be(:project_work_item) do
    create(:work_item, :issue, project: project, title: 'findmeterm project level', author: author)
  end

  let_it_be(:group_work_item) do
    create(:work_item, :issue, namespace: group, project: nil, title: 'findmeterm group level', author: author)
  end

  let(:index_name) { ::Search::Elastic::References::WorkItem.index }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)

    Elastic::ProcessBookkeepingService.track!(project_work_item, group_work_item)
    ensure_elasticsearch_index!
  end

  def indexed_hidden_flags
    items_in_index(index_name, source: true).to_h { |source| [source['id'], source['hidden']] }
  end

  it 'starts with both work items indexed as not hidden' do
    expect(indexed_hidden_flags)
      .to eq(project_work_item.id => false, group_work_item.id => false)
  end

  context 'when the author is banned' do
    before do
      author.ban!
      ensure_elasticsearch_index!
    end

    it 'flips the indexed hidden flag on both, without either work item being touched' do
      expect(indexed_hidden_flags)
        .to eq(project_work_item.id => true, group_work_item.id => true)
    end

    it 'stops returning them from Elasticsearch' do
      expect(searched_ids).to be_empty
    end

    context 'and the author is then unbanned' do
      before do
        author.unban!
        ensure_elasticsearch_index!
      end

      it 'clears the indexed hidden flag on both' do
        expect(indexed_hidden_flags)
          .to eq(project_work_item.id => false, group_work_item.id => false)
      end

      it 'returns them again' do
        expect(searched_ids).to contain_exactly(project_work_item.id, group_work_item.id)
      end
    end
  end

  def searched_ids
    options = {
      current_user: create(:user),
      project_ids: [project.id],
      group_ids: [group.id],
      search_level: :group,
      public_and_internal_projects: false,
      index_name: index_name
    }

    query_hash = ::Search::Elastic::WorkItemQueryBuilder.build(query: 'findmeterm', options: options)
    response = Search::Elastic::Helper.default.client.search(index: index_name, body: query_hash)

    response.dig('hits', 'hits').map { |hit| hit['_source']['id'] }
  end
end
