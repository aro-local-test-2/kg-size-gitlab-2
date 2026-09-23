# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::AdvancedFinders::Sbom::AggregationsFinder, :elastic_delete_by_query,
  :elasticsearch_settings_enabled, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:other_group) { create(:group) }

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sibling_project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:archived_project) { create(:project, :archived, group: group) }
  let_it_be(:outside_project) { create(:project, group: other_group) }

  let_it_be(:default_contexts) do
    [project, sibling_project, subgroup_project, archived_project, outside_project]
      .index_with { |current| create(:security_project_tracked_context, :default, project: current) }
  end

  let_it_be(:branch_context) { create(:security_project_tracked_context, project: project) }

  let_it_be(:components) do
    %w[actionpack bootstrap classnames debug entityframework fastify graphql]
      .index_with { |name| create(:sbom_component, name: name) }
  end

  # 'classnames' is deliberately absent: it stands in for a dependency reported without a version.
  let_it_be(:versions) do
    { 'actionpack' => '1.0.0', 'bootstrap' => '2.0.0', 'debug' => '4.0.0',
      'entityframework' => '5.0.0', 'fastify' => '6.0.0', 'graphql' => '7.0.0' }
      .to_h { |name, version| [name, create(:sbom_component_version, component: components[name], version: version)] }
  end

  let_it_be(:occurrence_actionpack) do
    create_occurrence('actionpack', project, :mit, :bundler, highest_severity: :high, vulnerability_count: 2)
  end

  let_it_be(:occurrence_actionpack_sibling) do
    create_occurrence('actionpack', sibling_project, :apache_2, :bundler, highest_severity: :high,
      vulnerability_count: 3)
  end

  let_it_be(:occurrence_bootstrap) do
    create_occurrence('bootstrap', subgroup_project, :apache_2, :npm, highest_severity: :low, vulnerability_count: 1)
  end

  # Nulls in every sort source, and the only fixture exercising `must_not exists`.
  let_it_be(:occurrence_classnames) { create_occurrence('classnames', project, nil, nil, source: nil) }

  # Two refs, so occurrence_count can be told apart from doc_count.
  let_it_be(:occurrence_debug) do
    create_occurrence('debug', project, :mpl_2, :yarn, highest_severity: :critical, vulnerability_count: 5,
      tracked_contexts: [default_contexts[project], branch_context])
  end

  # The one flagged as malware. The indexed `malware` field comes from
  # Sbom::Occurrence#malware_status, which is true when an active malware advisory covers the
  # component version. The advisory has to exist before the `before` block indexes the refs.
  let_it_be(:occurrence_entityframework) do
    create(:pm_malware_affected_package,
      malware_advisory: create(:pm_malware_advisory),
      purl_type: 'npm',
      package_name: 'entityframework',
      affected_range: '=5.0.0')

    create_occurrence('entityframework', project, :unknown, :nuget,
      highest_severity: :medium, vulnerability_count: 1)
  end

  # Two licenses. The traits push in order, so MIT stays the primary.
  let_it_be(:occurrence_fastify) do
    create(:sbom_occurrence, :with_refs, :mit, :apache_2, :npm, project: project,
      component: components['fastify'], component_version: versions['fastify'], highest_severity: :info,
      tracked_contexts: [default_contexts[project]])
  end

  # The three fixtures below must never appear in the rows or in the counts.
  let_it_be(:occurrence_on_branch_only) do
    create_occurrence('graphql', project, :mit, :npm, tracked_contexts: [branch_context])
  end

  let_it_be(:occurrence_archived) do
    create_occurrence('actionpack', archived_project, :mit, :bundler, highest_severity: :high, vulnerability_count: 9)
  end

  let_it_be(:occurrence_outside_group) do
    create_occurrence('actionpack', outside_project, :mit, :bundler, highest_severity: :high, vulnerability_count: 9)
  end

  let(:params) { {} }

  subject(:finder) { described_class.new(group, params: params) }

  before do
    Elastic::ProcessBookkeepingService.track!(*::Sbom::OccurrenceRef.all.to_a)
    ensure_elasticsearch_index!
  end

  describe '#execute' do
    it 'returns one record per component and version in the group' do
      expect(pairs_for(finder))
        .to match_array(pairs('actionpack', 'bootstrap', 'classnames', 'debug', 'entityframework', 'fastify'))
    end

    it 'decorates each record with the aggregate counts' do
      expect(record_for(finder, 'actionpack'))
        .to have_attributes(occurrence_count: 2, project_count: 2, vulnerability_count: 5)
    end

    it 'casts the doubles Elasticsearch reports for min and sum back to integers' do
      record = record_for(finder, 'actionpack')

      expect([record.id, record.vulnerability_count]).to all(be_an(Integer))
    end

    it 'loads the representative occurrence from PostgreSQL', :aggregate_failures do
      record = record_for(finder, 'actionpack')

      expect(record.id).to eq([occurrence_actionpack.id, occurrence_actionpack_sibling.id].min)
      expect(record.version).to eq('1.0.0')
      expect(record.packager).to eq('bundler')
    end

    it 'includes dependencies from descendant groups' do
      expect(pairs_for(finder)).to include(*pairs('bootstrap'))
    end

    it 'excludes archived projects and projects outside the group from the counts' do
      expect(record_for(finder, 'actionpack').occurrence_count).to eq(2)
    end

    it 'scopes the rows to the given group' do
      expect(pairs_for(described_class.new(other_group))).to eq(pairs('actionpack'))
    end

    it 'reports real counts for a dependency without a version' do
      expect(record_for(finder, 'classnames'))
        .to have_attributes(occurrence_count: 1, project_count: 1, vulnerability_count: 0)
    end

    context 'when an occurrence has been deleted from PostgreSQL but not from the index' do
      before do
        ::Sbom::Occurrence.id_in(occurrence_fastify.id).delete_all
      end

      it 'drops the row' do
        expect(names_in(finder)).to match_array(%w[actionpack bootstrap classnames debug entityframework])
      end
    end
  end

  describe 'the returned records' do
    let(:record) { record_for(finder, 'actionpack') }
    let(:occurrence) { ::Sbom::Occurrence.find(record.id) }

    it 'exposes every field ::Sbom::AggregationsFinder selects' do
      expect(record).to respond_to(:id, :component_id, :component_version_id, :package_manager,
        :input_file_path, :licenses, :occurrence_count, :project_count, :vulnerability_count)
    end

    it 'reports the group aggregate, not the per-occurrence vulnerability_count column', :aggregate_failures do
      expect(occurrence.vulnerability_count).to eq(2)
      expect(record.vulnerability_count).to eq(5)
    end

    it 'delegates the remaining dependency list fields to the occurrence', :aggregate_failures do
      %i[uuid name version packager purl_type component_name project_id to_global_id].each do |field|
        expect(record.public_send(field)).to eq(occurrence.public_send(field))
      end
    end

    it 'returns only the primary license', :aggregate_failures do
      record = record_for(finder, 'fastify')

      expect(::Sbom::Occurrence.find(record.id).licenses.size).to eq(2)
      expect(record.licenses).to contain_exactly(a_hash_including('spdx_identifier' => 'MIT'))
    end

    it 'returns an empty license array when the occurrence has none' do
      expect(record_for(finder, 'classnames').licenses).to eq([])
    end
  end

  describe 'tracked refs' do
    it 'returns dependencies on the default ref only' do
      expect(pairs_for(finder)).not_to include(*pairs('graphql'))
    end

    it 'counts an occurrence once even though it has two refs' do
      expect(record_for(finder, 'debug'))
        .to have_attributes(occurrence_count: 1, project_count: 1, vulnerability_count: 5)
    end

    context 'with tracked_refs_scope: :all_refs' do
      let(:params) { { tracked_refs_scope: :all_refs } }

      it 'includes dependencies on non-default refs' do
        expect(pairs_for(finder)).to include(*pairs('graphql'))
      end

      it 'does not multiply the counts by the number of refs' do
        expect(record_for(finder, 'debug')).to have_attributes(occurrence_count: 1, project_count: 1)
      end
    end

    # by_tracked_refs_scope matches on the :all_refs symbol, so a String silently falls back.
    context 'with tracked_refs_scope given as a String' do
      let(:params) { { tracked_refs_scope: 'all_refs' } }

      it 'includes dependencies on non-default refs' do
        expect(pairs_for(finder)).to include(*pairs('graphql'))
      end
    end

    context 'with security_project_tracked_context_id' do
      let(:params) { { security_project_tracked_context_id: branch_context.id } }

      it 'returns the dependencies on that ref without re-applying the default filter' do
        expect(pairs_for(finder)).to match_array(pairs('debug', 'graphql'))
      end
    end
  end

  describe 'filters' do
    context 'with component_ids' do
      let(:params) { { component_ids: [components['actionpack'].id] } }

      it 'returns only that component' do
        expect(pairs_for(finder)).to eq(pairs('actionpack'))
      end
    end

    context 'with component_names' do
      let(:params) { { component_names: %w[bootstrap classnames] } }

      it 'returns only those components' do
        expect(pairs_for(finder)).to match_array(pairs('bootstrap', 'classnames'))
      end
    end

    context 'with component_versions' do
      let(:params) { { component_versions: ['2.0.0'] } }

      it 'returns only that version' do
        expect(pairs_for(finder)).to eq(pairs('bootstrap'))
      end
    end

    context 'with a negated component_versions filter' do
      let(:params) { { not: { component_versions: ['2.0.0'] } } }

      it 'excludes that version' do
        expect(pairs_for(finder)).not_to include(*pairs('bootstrap'))
      end
    end

    context 'with licenses' do
      let(:params) { { licenses: ['MPL-2.0'] } }

      it 'returns only dependencies under that license' do
        expect(pairs_for(finder)).to eq(pairs('debug'))
      end
    end

    context 'with malware' do
      let(:params) { { malware: malware } }

      context 'when true' do
        let(:malware) { true }

        it 'returns only the flagged dependency' do
          expect(names_in(finder)).to contain_exactly('entityframework')
        end
      end

      context 'when false' do
        let(:malware) { false }

        it 'excludes the flagged dependency' do
          expect(names_in(finder)).to match_array(%w[actionpack bootstrap classnames debug fastify])
        end
      end
    end

    context 'with project_ids' do
      let(:params) { { project_ids: [sibling_project.id] } }

      it 'returns only that project, with counts narrowed to it', :aggregate_failures do
        expect(pairs_for(finder)).to eq(pairs('actionpack'))
        expect(record_for(finder, 'actionpack'))
          .to have_attributes(occurrence_count: 1, project_count: 1, vulnerability_count: 3)
      end

      context 'when the project is outside the group' do
        let(:params) { { project_ids: [outside_project.id] } }

        it 'returns nothing, even though that project has one of the components' do
          expect(pairs_for(finder)).to be_empty
        end
      end
    end

    context 'with package_managers' do
      let(:params) { { package_managers: ['yarn'] } }

      it 'returns only dependencies from that package manager' do
        expect(pairs_for(finder)).to eq(pairs('debug'))
      end

      context 'when the dependencies_page_filter_by_package_manager flag is disabled' do
        before do
          stub_feature_flags(dependencies_page_filter_by_package_manager: false)
        end

        it 'ignores the filter, matching ::Sbom::AggregationsFinder' do
          expect(names_in(finder)).to match_array(%w[actionpack bootstrap classnames debug entityframework fastify])
        end
      end
    end

    # ::Sbom::AggregationsFinder reports unfiltered counts here, as its counts subquery
    # ignores the filters.
    context 'when a filter splits a component version across projects' do
      let(:params) { { licenses: ['MIT'] } }

      it 'reports the filtered counts' do
        expect(record_for(finder, 'actionpack'))
          .to have_attributes(occurrence_count: 1, project_count: 1, vulnerability_count: 2)
      end
    end
  end

  describe 'sorting' do
    # 'bootstrap' and 'fastify' share a package manager, and the direction applies to every composite
    # source, so their tie-break reverses along with the sort field.
    where(:sort_by, :sort, :expected) do
      'name'             | 'asc'  | %w[actionpack bootstrap classnames debug entityframework fastify]
      'name'             | 'desc' | %w[fastify entityframework debug classnames bootstrap actionpack]
      'component_name'   | 'desc' | %w[fastify entityframework debug classnames bootstrap actionpack]
      'severity'         | 'asc'  | %w[classnames fastify bootstrap entityframework actionpack debug]
      'severity'         | 'desc' | %w[debug actionpack entityframework bootstrap fastify classnames]
      'highest_severity' | 'asc'  | %w[classnames fastify bootstrap entityframework actionpack debug]
      'packager'         | 'asc'  | %w[actionpack bootstrap fastify entityframework debug classnames]
      'packager'         | 'desc' | %w[classnames debug entityframework fastify bootstrap actionpack]
    end

    with_them do
      it 'orders the rows by the requested field' do
        expect(names_for(sort_by: sort_by, sort: sort)).to eq(expected)
      end
    end

    it 'places nulls where Postgres places them', :aggregate_failures do
      expect(names_for(sort_by: 'packager', sort: 'asc').last).to eq('classnames')
      expect(names_for(sort_by: 'packager', sort: 'desc').first).to eq('classnames')
      expect(names_for(sort_by: 'severity', sort: 'asc').first).to eq('classnames')
      expect(names_for(sort_by: 'severity', sort: 'desc').last).to eq('classnames')
    end

    # 'actionpack' is reported under two licenses. ::Sbom::AggregationsFinder behaves the same way.
    it 'lists a dependency once per distinct sort value, with identical counts on each row' do
      records = described_class.new(group, params: { sort_by: 'license', sort: 'asc' }).execute
      duplicated = records.select { |record| record.name == 'actionpack' }

      expect(records.map(&:name)).to eq(%w[actionpack bootstrap actionpack fastify debug entityframework classnames])
      expect(duplicated.map(&:occurrence_count)).to match_array([2, 2])
      expect(duplicated.map(&:project_count)).to match_array([2, 2])
    end

    it 'falls back to component and version for an unrecognised sort field' do
      expect(names_for(sort_by: 'bogus', sort: 'asc')).to eq(names_for(sort: 'asc'))
    end
  end

  describe 'page size' do
    # Stubbed below the fixture count so the upper clamp is observable at all.
    before do
      stub_const("#{described_class}::MAX_PAGE_SIZE", 4)
    end

    where(:per_page, :expected_size) do
      nil   | 4
      0     | 1
      1     | 1
      '3'   | 3
      500   | 4
    end

    with_them do
      it 'returns at most per_page rows, clamped to MAX_PAGE_SIZE' do
        expect(described_class.new(group, params: { per_page: per_page }).execute.size).to eq(expected_size)
      end
    end

    it 'truncates to the page size in sort order' do
      expect(names_for(sort_by: 'name', sort: 'asc', per_page: 3)).to eq(%w[actionpack bootstrap classnames])
    end
  end

  describe 'query options' do
    it 'sends no nil options to the query builder' do
      expect(described_class.new(group).send(:query_options).values).not_to include(nil)
    end
  end

  describe 'the page #execute returns' do
    # Two rows out of six, so there is always a probe bucket beyond the page.
    let(:page) { described_class.new(group, params: { sort_by: 'name', sort: 'asc', per_page: 2 }).execute }

    it 'enumerates as the rows, so a caller that does not paginate can ignore the rest' do
      expect(page.map(&:name)).to eq(%w[actionpack bootstrap])
    end

    it 'holds at most per_page rows even though a further bucket was fetched' do
      expect(page.size).to eq(2)
    end

    it 'reports another page while buckets remain' do
      expect(page).to have_next_page
    end

    it 'reports no further page once the rows run out' do
      expect(described_class.new(group, params: { per_page: 20 }).execute).not_to have_next_page
    end

    # Elasticsearch rejects an `after` whose field names or arity miss a composite source.
    it 'keys the rows at either end by every composite source', :aggregate_failures do
      expect(page.first_key.keys).to match_array(%w[component_name component_id component_version_id])
      expect(page.first_key['component_name']).to eq('actionpack')
      expect(page.last_key['component_name']).to eq('bootstrap')
    end

    # Elasticsearch's response after_key is the probe's, so a cursor cut from it skips a row.
    it 'keys the last row from the page, not from the probe bucket' do
      expect(page.last_key['component_name']).not_to eq('classnames')
    end

    it 'is empty and final when nothing matches', :aggregate_failures do
      empty = described_class.new(group, params: { component_names: ['nope'] }).execute

      expect(empty).to be_empty
      expect(empty).not_to have_next_page
      expect(empty.first_key).to be_nil
    end
  end

  describe 'after_key' do
    let(:page) { described_class.new(group, params: { sort_by: 'name', sort: 'asc', per_page: 2 }).execute }

    it 'starts the page after the given key' do
      next_page = described_class.new(group,
        params: { sort_by: 'name', sort: 'asc', per_page: 2, after_key: page.last_key })

      expect(names_in(next_page)).to eq(%w[classnames debug])
    end

    it 'accepts a null source value, which is how a missing_bucket row is paged past' do
      after_key = page.first_key.merge('component_version_id' => nil)

      expect do
        described_class.new(group, params: { sort_by: 'name', sort: 'asc', after_key: after_key }).execute.to_a
      end.not_to raise_error
    end
  end

  describe 'Elasticsearch requests' do
    it 'issues one search for the rows and one for the counts' do
      expect(Gitlab::Search::Client).to receive(:execute_search).twice.and_call_original

      finder.execute
    end

    it 'routes both searches to the shard holding the root namespace' do
      expect(Gitlab::Search::Client).to receive(:execute_search)
        .twice
        .with(query: anything, options: {
          index_name: ::Search::Elastic::References::Sbom::OccurrenceRef.index,
          root_ancestor_ids: [group.id]
        })
        .and_call_original

      finder.execute
    end

    it 'skips the counts search when no rows come back' do
      expect(Gitlab::Search::Client).to receive(:execute_search).once.and_call_original

      expect(described_class.new(group, params: { component_names: ['nope'] }).execute).to be_empty
    end

    it 'over-fetches one bucket as the probe and keeps it out of the counts search', :aggregate_failures do
      rows_options = nil
      counts_keys = nil

      builder = ::Search::Elastic::SbomOccurrenceRefQueryBuilder
      allow(builder).to receive(:build).and_wrap_original do |original, **kwargs|
        rows_options ||= kwargs[:options] if kwargs[:options][:aggregate_by_component_and_version]
        counts_keys ||= kwargs[:options][:component_and_version_filters]

        original.call(**kwargs)
      end

      described_class.new(group, params: { sort_by: 'name', sort: 'asc', per_page: 2 }).execute.to_a

      expect(rows_options[:bucket_size]).to eq(3)
      expect(counts_keys.size).to eq(2)
    end

    it 'memoizes both searches across repeated calls' do
      expect(Gitlab::Search::Client).to receive(:execute_search).twice.and_call_original

      finder.execute
      finder.execute
    end
  end

  def create_occurrence(name, project, license_trait, packager_trait, tracked_contexts: nil, **attributes)
    traits = [:with_refs, license_trait, packager_trait].compact

    create(:sbom_occurrence, *traits,
      project: project,
      component: components[name],
      component_version: versions[name],
      tracked_contexts: tracked_contexts || [default_contexts[project]],
      **attributes)
  end

  def pairs(*names)
    names.map { |name| [components[name].id, versions[name]&.id] }
  end

  def pairs_for(finder)
    finder.execute.map { |record| [record.component_id, record.component_version_id] }
  end

  def names_in(finder)
    finder.execute.map(&:name)
  end

  def names_for(sort_params)
    names_in(described_class.new(group, params: sort_params))
  end

  def record_for(finder, name)
    finder.execute.detect { |record| record.name == name }
  end
end
