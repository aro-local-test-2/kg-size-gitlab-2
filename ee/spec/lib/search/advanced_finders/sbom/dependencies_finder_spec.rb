# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::AdvancedFinders::Sbom::DependenciesFinder, :elastic_delete_by_query,
  :elasticsearch_settings_enabled, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:other_group) { create(:group) }

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sibling_project) { create(:project, group: group) }
  let_it_be(:outside_project) { create(:project, group: other_group) }

  let_it_be(:default_contexts) do
    [project, sibling_project, outside_project]
      .index_with { |current| create(:security_project_tracked_context, :default, project: current) }
  end

  let_it_be(:branch_context) { create(:security_project_tracked_context, :tracked, project: project) }

  let_it_be(:components) do
    %w[actionpack bootstrap classnames debug entityframework fastify graphql]
      .index_with { |name| create(:sbom_component, name: name) }
  end

  let_it_be(:versions) do
    components.keys.index_with { |name| create(:sbom_component_version, component: components[name]) }
  end

  let_it_be(:actionpack) { create_occurrence('actionpack', :mit, :bundler, highest_severity: :high) }
  let_it_be(:bootstrap) { create_occurrence('bootstrap', :mpl_2, :npm, highest_severity: :low) }
  let_it_be(:debug) { create_occurrence('debug', :apache_2, :mit, :yarn, highest_severity: :medium) }
  let_it_be(:classnames) { create_occurrence('classnames', :registry_occurrence) }
  let_it_be(:fastify) { create_occurrence('fastify', source: nil) }
  let_it_be(:graphql) { create_occurrence('graphql', :npm) }

  let_it_be(:actionpack_other_file) do
    create(:sbom_occurrence, :with_refs, :mit, :bundler,
      project: project,
      component: components['actionpack'],
      component_version: versions['actionpack'],
      tracked_contexts: [default_contexts[project]])
  end

  let_it_be(:branch_only) do
    create_occurrence('entityframework', :npm, tracked_contexts: [branch_context])
  end

  let_it_be(:sibling_occurrence) do
    create(:sbom_occurrence, :with_refs, :npm,
      project: sibling_project,
      component: components['bootstrap'],
      component_version: versions['bootstrap'],
      tracked_contexts: [default_contexts[sibling_project]])
  end

  let_it_be(:outside_occurrence) do
    create(:sbom_occurrence, :with_refs, :npm,
      project: outside_project,
      component: components['bootstrap'],
      component_version: versions['bootstrap'],
      tracked_contexts: [default_contexts[outside_project]])
  end

  let(:default_source_types) { ::Sbom::Source::DEFAULT_SOURCES.keys.map(&:to_s) + ['nil_source'] }
  let(:params) { {} }
  let(:finder) { described_class.new(project, params: params) }

  before do
    ::Elastic::ProcessBookkeepingService.track!(*::Sbom::OccurrenceRef.all.to_a)
    ensure_elasticsearch_index!
  end

  describe '#execute' do
    it 'returns a relation of Sbom::Occurrence records' do
      expect(finder.execute).to be_a(::Search::Elastic::Relation)
      expect(ids_in(finder)).to all(be_a(Integer))
      expect(records_in(finder)).to all(be_a(::Sbom::Occurrence))
    end

    it 'only returns default-branch dependencies of the given project' do
      expect(ids_in(finder)).to contain_exactly(
        actionpack.id, actionpack_other_file.id, bootstrap.id, debug.id,
        classnames.id, fastify.id, graphql.id
      )
    end

    it 'excludes a sibling project in the same namespace' do
      expect(ids_in(finder)).not_to include(sibling_occurrence.id)
    end

    it 'excludes a project outside the namespace' do
      expect(ids_in(finder)).not_to include(outside_occurrence.id)
    end

    it 'excludes a dependency that only exists on a non-default ref' do
      expect(ids_in(finder)).not_to include(branch_only.id)
    end

    # Sbom::Occurrence is unique on (project, component, version, source).
    it 'returns the same component and version once per source' do
      returned = records_in(finder).select { |record| record.name == 'actionpack' }

      expect(returned.map(&:id)).to contain_exactly(actionpack.id, actionpack_other_file.id)
      expect(returned.map(&:input_file_path).uniq.size).to eq(2)
    end
  end

  describe 'filters' do
    context 'with component_names' do
      let(:params) { { component_names: %w[bootstrap] } }

      it { expect(ids_in(finder)).to contain_exactly(bootstrap.id) }
    end

    context 'with component_ids' do
      let(:params) { { component_ids: [components['bootstrap'].id] } }

      it { expect(ids_in(finder)).to contain_exactly(bootstrap.id) }
    end

    context 'with package_managers' do
      let(:params) { { package_managers: %w[bundler] } }

      it { expect(ids_in(finder)).to contain_exactly(actionpack.id, actionpack_other_file.id) }
    end

    context 'with component_versions' do
      let(:params) { { component_names: %w[bootstrap], component_versions: [versions['bootstrap'].version] } }

      it { expect(ids_in(finder)).to contain_exactly(bootstrap.id) }
    end

    context 'with negated component_versions' do
      let(:params) do
        { component_names: %w[bootstrap], not: { component_versions: [versions['bootstrap'].version] } }
      end

      it { expect(ids_in(finder)).to be_empty }
    end

    context 'with malware' do
      let(:params) { { malware: true } }

      it { expect(ids_in(finder)).to be_empty }
    end

    context 'with licenses matching a primary license' do
      let(:params) { { licenses: %w[MPL-2.0] } }

      it { expect(ids_in(finder)).to contain_exactly(bootstrap.id) }
    end

    context 'with licenses matching a secondary license' do
      let(:params) { { licenses: %w[MIT] } }

      it { expect(ids_in(finder)).to contain_exactly(actionpack.id, actionpack_other_file.id, debug.id) }
    end

    context 'with the default source_types' do
      let(:params) { { source_types: default_source_types } }

      it 'excludes container_scanning_for_registry but keeps the source-less dependency' do
        expect(ids_in(finder)).to include(fastify.id)
        expect(ids_in(finder)).not_to include(classnames.id)
      end
    end

    context 'with source_types naming only the registry scanner' do
      let(:params) { { source_types: %w[container_scanning_for_registry] } }

      it { expect(ids_in(finder)).to contain_exactly(classnames.id) }
    end

    context 'with source_types that resolve to no known type' do
      let(:params) { { source_types: %w[bogus] } }

      it { expect(ids_in(finder)).to be_empty }
    end

    context 'with source_types of nil_source alone' do
      let(:params) { { source_types: %w[nil_source] } }

      it { expect(ids_in(finder)).to contain_exactly(fastify.id) }
    end
  end

  describe 'sorting' do
    where(:sort_by, :sort, :expected_first) do
      'name'     | 'asc'  | 'actionpack'
      'name'     | 'desc' | 'graphql'
      'severity' | 'desc' | 'actionpack'
      'packager' | 'asc'  | 'actionpack'
    end

    with_them do
      let(:params) { { sort_by: sort_by, sort: sort } }

      it 'orders by the requested field' do
        expect(names_in(finder).first).to eq(expected_first)
      end
    end

    it 'falls back to the occurrence id for an unrecognised sort field' do
      expect(ids_in(described_class.new(project, params: { sort_by: 'bogus' })))
        .to eq(ids_in(described_class.new(project, params: {})))
    end

    it 'breaks ties on the occurrence id' do
      ids = ids_in(described_class.new(project, params: { component_names: %w[actionpack], sort_by: 'name' }))

      expect(ids).to match_array([actionpack.id, actionpack_other_file.id])
      expect(ids).to eq(ids.sort)
    end
  end

  describe 'keyset pagination' do
    describe 'walking forward' do
      where(:sort_field, :direction) do
        %w[name packager severity license].product(%w[asc desc])
      end

      with_them do
        it 'covers every page without gaps or repeats' do
          expected = ids_in(described_class.new(project, params: { sort_by: sort_field, sort: direction }))
          walked = walk_forward(sort_by: sort_field, sort: direction, max_pages: expected.size)

          expect(walked.uniq).to eq(walked)
          expect(walked).to eq(expected)
        end
      end
    end

    it 'walks backward to the preceding page' do
      relation = described_class.new(project, params: { sort_by: 'name', sort: 'asc' }).execute
      first_page = relation.first(2)
      cursor = relation.cursor_for(first_page.last)

      second = described_class.new(project, params: { sort_by: 'name', sort: 'asc' }).execute
      second.after(*cursor)
      second_page = second.first(2)
      back_cursor = second.cursor_for(second_page.first)

      previous = described_class.new(project, params: { sort_by: 'name', sort: 'asc' }).execute
      previous.before(*back_cursor)

      expect(previous.last(2).map(&:id)).to eq(first_page.map(&:id))
    end

    it 'walks backward from a null sort value' do
      relation = described_class.new(project, params: { sort_by: 'packager', sort: 'asc' }).execute
      all_records = relation.first(20)
      null_record = all_records.find { |record| record.package_manager.nil? }
      expect(null_record).to be_present

      cursor = relation.cursor_for(null_record)

      expect(cursor.first).to be_nil

      previous = described_class.new(project, params: { sort_by: 'packager', sort: 'asc' }).execute
      previous.before(*cursor)

      expect(previous.last(2).map(&:id)).to eq(all_records[all_records.index(null_record) - 2, 2].map(&:id))
    end
  end

  describe 'preloading' do
    it 'preloads through the relation' do
      records = finder.execute.preload(:component_version).first(20)

      expect(records.first.association(:component_version)).to be_loaded
    end
  end

  def create_occurrence(name, *traits, tracked_contexts: nil, **attributes)
    create(:sbom_occurrence, :with_refs, *traits,
      project: project,
      component: components[name],
      component_version: versions[name],
      tracked_contexts: tracked_contexts || [default_contexts[project]],
      **attributes)
  end

  def records_in(finder)
    finder.execute.first(50)
  end

  def ids_in(finder)
    records_in(finder).map(&:id)
  end

  def names_in(finder)
    records_in(finder).map(&:name)
  end

  # `max_pages` bounds the walk: at one row per page it can never need more pages than there are
  # rows, so exhausting it means the cursor stopped advancing.
  def walk_forward(sort_by:, sort:, params: {}, per_page: 2, max_pages: 25)
    ids = []
    cursor = nil
    terminated = false

    max_pages.times do
      relation = described_class.new(project, params: params.merge(sort_by: sort_by, sort: sort)).execute
      relation.after(*cursor) if cursor
      page = relation.first(per_page + 1)

      if page.empty?
        terminated = true
        break
      end

      has_next = page.size > per_page
      ids.concat(page.first(per_page).map(&:id))

      unless has_next
        terminated = true
        break
      end

      cursor = relation.cursor_for(page.first(per_page).last)
    end

    expect(terminated).to be(true),
      "#{sort_by} #{sort} did not terminate within #{max_pages} pages; " \
        "collected #{ids.size} ids, last cursor #{cursor.inspect}"

    ids
  end
end
