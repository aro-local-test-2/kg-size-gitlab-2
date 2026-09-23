# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WorkItem state aggregation', :elastic, :sidekiq_inline, feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:label) { create(:group_label, group: group, title: 'bug') }

  # All work items are created at file level so that every example indexes the
  # same set of documents. The index is not reset between examples in a file, so
  # creating a work item inside one example would leak into the others.
  let_it_be(:opened_issue) { create(:work_item, :issue, project: project, title: 'search term') }
  let_it_be(:other_opened_issue) { create(:work_item, :issue, project: project, title: 'search term') }
  let_it_be(:closed_issue) { create(:work_item, :issue, :closed, project: project, title: 'search term') }
  let_it_be(:labeled_closed_issue) do
    create(:work_item, :issue, :closed, project: project, title: 'search term', labels: [label])
  end

  let(:helper) { Search::Elastic::Helper.default }
  let(:client) { helper.client }
  let(:query_builder) { ::Search::Elastic::WorkItemQueryBuilder }

  let(:base_options) do
    {
      current_user: user,
      project_ids: [project.id],
      group_ids: [group.id],
      search_level: :group,
      aggregation: true,
      state_aggregation: true,
      public_and_internal_projects: false,
      index_name: ::Search::Elastic::References::WorkItem.index
    }
  end

  before_all do
    project.add_developer(user)
  end

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)

    Elastic::ProcessBookkeepingService.track!(opened_issue, other_opened_issue, closed_issue, labeled_closed_issue)
    ensure_elasticsearch_index!
  end

  def state_counts(options)
    query_hash = query_builder.build(query: 'search term', options: options)
    response = client.search(index: options[:index_name], body: query_hash)

    response.dig('aggregations', 'state', 'buckets').to_h { |bucket| [bucket['key'], bucket['doc_count']] }
  end

  it 'returns per-state doc counts' do
    expect(state_counts(base_options)).to eq('opened' => 2, 'closed' => 2)
  end

  it 'restricts the counts to work items matching the other filters' do
    expect(state_counts(base_options.merge(label_name: [label.title]))).to eq('closed' => 1)
  end

  # This is the reason the aggregation is opt-in: a state-scoped query can only ever
  # return the selected state's bucket, which is useless for open/closed tab counts.
  it 'ignores the state filter so both buckets survive' do
    expect(state_counts(base_options.merge(state: 'opened'))).to eq('opened' => 2, 'closed' => 2)
  end

  it 'still scopes results by state when the aggregation is not requested' do
    options = base_options.merge(state_aggregation: false, state: 'opened', aggregation: false)
    query_hash = query_builder.build(query: 'search term', options: options)
    response = client.search(index: options[:index_name], body: query_hash)

    expect(response.dig('hits', 'total', 'value')).to eq(2)
    expect(response['aggregations']).to be_nil
  end
end
