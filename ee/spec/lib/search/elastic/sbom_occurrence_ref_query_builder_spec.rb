# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::SbomOccurrenceRefQueryBuilder, :elastic_helpers,
  feature_category: :dependency_management do
  let(:base_options) do
    {
      search_level: 'group',
      traversal_ids: ['1-2-'],
      aggregate_by_component_and_version: true
    }
  end

  let(:options) { base_options }

  subject(:build) { described_class.build(query: nil, options: options) }

  it 'applies the group, archived and default ref filters' do
    assert_names_in_query(build, with: %w[
      namespace:ancestry_filter:descendants
      filters:non_archived
      filters:is_default
    ])
  end

  it 'excludes archived projects the way Sbom::AggregationsFinder does' do
    expect(build.dig(:query, :bool, :filter)).to include(
      a_hash_including(bool: a_hash_including(_name: 'filters:non_archived'))
    )
  end

  it 'scopes the group filter to the traversal_ids field' do
    expect(build.dig(:query, :bool, :filter)).to include(
      a_hash_including(bool: a_hash_including(should: [a_hash_including(prefix: a_hash_including(traversal_ids:
        a_hash_including(value: '1-2-')))]))
    )
  end

  it 'aggregates by component and version' do
    expect(build).to include(size: 0, aggs: a_hash_including(dependencies: be_a(Hash)))
  end

  it 'does not have source or sort fields' do
    aggregate_failures do
      expect(build).not_to have_key(:_source)
      expect(build).not_to have_key(:sort)
    end
  end

  describe 'filters' do
    where(:option, :expected_name) do
      [
        [{ component_ids: [1] }, 'filters:component_ids'],
        [{ component_names: %w[express] }, 'filters:component_names'],
        [{ package_managers: %w[npm] }, 'filters:package_managers'],
        [{ component_versions: %w[1.0.0] }, 'filters:component_versions'],
        [{ not_component_versions: %w[1.0.0] }, 'filters:not_component_versions'],
        [{ licenses: %w[MIT] }, 'filters:licenses'],
        [{ malware: true }, 'filters:malware'],
        [{ malware: false }, 'filters:malware'],
        [{ security_project_tracked_context_id: 1 }, 'filters:security_project_tracked_context_id'],
        [{ project_ids: [7] }, 'filters:project_ids'],
        [{ source_types: [0, 1] }, 'filters:source_types'],
        [{ source_types: [0, nil] }, 'filters:source_types']
      ]
    end

    with_them do
      let(:options) { base_options.merge(option) }

      it 'adds the filter to the query' do
        assert_names_in_query(build, with: [expected_name])
      end
    end
  end

  context 'when filtering by a specific tracked context' do
    let(:options) { base_options.merge(security_project_tracked_context_id: 1) }

    it 'does not filter by the default ref' do
      assert_names_in_query(build, without: %w[filters:is_default])
    end
  end

  context 'when tracked_refs_scope is :all_refs' do
    let(:options) { base_options.merge(tracked_refs_scope: :all_refs) }

    it 'does not filter by the default ref' do
      assert_names_in_query(build, without: %w[filters:is_default])
    end
  end

  context 'when archived dependencies are included' do
    let(:options) { base_options.merge(include_archived: true) }

    it 'does not filter by archived' do
      assert_names_in_query(build, without: %w[filters:non_archived])
    end
  end

  context 'when running a document search rather than an aggregation' do
    let(:options) do
      base_options.except(:aggregate_by_component_and_version).merge(
        search_level: 'project',
        project_ids: [7],
        sort_by: 'name',
        sort: 'asc'
      )
    end

    it 'requests the primary key and sorts', :aggregate_failures do
      expect(build[:_source]).to eq(%w[sbom_occurrence_id])
      expect(build[:sort]).to eq({ component_name: { order: :asc }, sbom_occurrence_id: { order: :asc } })
      expect(build).not_to have_key(:aggs)
    end
  end

  describe 'the counts request' do
    let(:options) do
      base_options.except(:aggregate_by_component_and_version)
                  .merge(component_and_version_filters: { 'a' => [1, 10], 'b' => [2, nil] })
    end

    it 'aggregates counts keyed on component and version instead of the page rows' do
      aggregate_failures do
        expect(build[:aggs]).to have_key(:version_counts)
        expect(build[:aggs]).not_to have_key(:dependencies)
        expect(build).to include(size: 0)
      end
    end

    it 'selects the dependencies in the aggregation rather than in the query' do
      aggregate_failures do
        expect(build.dig(:aggs, :version_counts, :filters, :filters).size).to eq(2)
        expect(build.dig(:query, :bool, :filter).to_s).not_to include('component_version_id')
      end
    end

    it 'still applies the structural filters, so counts are not multiplied across refs' do
      assert_names_in_query(build, with: %w[
        namespace:ancestry_filter:descendants
        filters:non_archived
        filters:is_default
      ])
    end
  end
end
