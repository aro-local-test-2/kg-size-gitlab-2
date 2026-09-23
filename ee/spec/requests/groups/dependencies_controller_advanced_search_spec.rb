# frozen_string_literal: true

require 'spec_helper'

# Exercises the Elasticsearch branch of Groups::DependenciesController#dependencies, which is
# taken only when the malware filter is asked for.
RSpec.describe Groups::DependenciesController, :elastic_delete_by_query, :elasticsearch_settings_enabled,
  feature_category: :dependency_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:tracked_context) { create(:security_project_tracked_context, :default, project: project) }

  let_it_be(:clean_names) { %w[actionpack bootstrap classnames debug entityframework] }

  let_it_be(:clean_occurrences) do
    clean_names.map { |name| create_occurrence(name) }
  end

  # Sbom::Occurrence#malware_status is true when an active malware advisory covers the component
  # version. The advisory has to exist before the `before` block indexes the refs.
  let_it_be(:malicious_occurrence) do
    create(:pm_malware_affected_package,
      malware_advisory: create(:pm_malware_advisory),
      purl_type: 'npm',
      package_name: 'malicious',
      affected_range: '=1.0.0')

    create_occurrence('malicious')
  end

  before_all do
    group.add_developer(user)
  end

  before do
    stub_licensed_features(dependency_scanning: true, security_dashboard: true)
    stub_feature_flags(malicious_packages_dependency_list_filtering: true)
    allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
      .to receive(:advanced_dependency_management_allowed?).and_return(true)
    sign_in(user)

    Elastic::ProcessBookkeepingService.track!(*::Sbom::OccurrenceRef.all.to_a)
    ensure_elasticsearch_index!
  end

  def get_page(cursor: nil, per_page: 2, malware: 'false', **overrides)
    get group_dependencies_path(
      { group_id: group.full_path, format: :json, sort_by: 'name', sort: 'asc',
        per_page: per_page, cursor: cursor, malware: malware }.merge(overrides)
    )
  end

  def names
    Gitlab::Json::SafeParser.parse(response.body)['dependencies'].pluck('name')
  end

  describe 'serving the list from Elasticsearch' do
    it 'returns only the packages that are not malware' do
      get_page(per_page: 20)

      expect(response).to have_gitlab_http_status(:ok)
      expect(names).to eq(clean_names)
    end

    it 'returns only the packages that are malware' do
      get_page(per_page: 20, malware: 'true')

      expect(names).to eq(%w[malicious])
    end

    it 'carries the aggregate counts on each row' do
      get_page(per_page: 20)

      expect(Gitlab::Json::SafeParser.parse(response.body)['dependencies'].first)
        .to include('occurrence_count' => 1, 'project_count' => 1)
    end

    it 'stays on the Postgres finder when no malware filter is asked for' do
      expect(::Search::AdvancedFinders::Sbom::AggregationsFinder).not_to receive(:new)

      get_page(per_page: 20, malware: nil)

      expect(names).to match_array(clean_names + %w[malicious])
    end
  end

  describe 'with a project filter' do
    let_it_be(:sibling_project) { create(:project, group: group) }
    let_it_be(:sibling_context) { create(:security_project_tracked_context, :default, project: sibling_project) }

    # Same component version as 'malicious', so the two collapse into one aggregated row and only
    # the project filter can tell them apart. The advisory covers the version itself, so this
    # occurrence is malware too without any per-project setup.
    let_it_be(:sibling_malicious_occurrence) do
      create(:sbom_occurrence, :with_refs, :mit, :npm,
        project: sibling_project,
        component: malicious_occurrence.component,
        component_version: malicious_occurrence.component_version,
        tracked_contexts: [sibling_context])
    end

    let_it_be(:sibling_clean_occurrence) do
      component = create(:sbom_component, name: 'fastify')

      create(:sbom_occurrence, :with_refs, :mit, :npm,
        project: sibling_project,
        component: component,
        component_version: create(:sbom_component_version, component: component, version: '1.0.0'),
        tracked_contexts: [sibling_context])
    end

    before do
      stub_feature_flags(dependency_malware_detection: group)
    end

    def malware_flags
      Gitlab::Json::SafeParser.parse(response.body)['dependencies'].pluck('malware')
    end

    it 'applies both filters instead of dropping the malware one', :aggregate_failures do
      get_page(per_page: 20, malware: 'true', project_ids: [sibling_project.id])

      expect(response).to have_gitlab_http_status(:ok)
      expect(names).to eq(%w[malicious])
      expect(malware_flags).to eq([true])
    end

    it 'restricts the list to the selected project', :aggregate_failures do
      get_page(per_page: 20, project_ids: [sibling_project.id])

      expect(names).to eq(%w[fastify])
      expect(malware_flags).to eq([false])
    end

    it 'still pages with a cursor' do
      get_page(per_page: 20, project_ids: [sibling_project.id])

      expect(response.header['X-Page-Type']).to eq('cursor')
    end
  end

  describe 'pagination' do
    it 'sets the cursor pagination headers', :aggregate_failures do
      get_page

      expect(response.header['X-Page-Type']).to eq('cursor')
      expect(response.header['X-Per-Page']).to eq(2)
      expect(response.header['X-Next-Page']).to be_present
      expect(response.header['X-Prev-Page']).to be_blank
    end

    it 'walks forward through every page exactly once' do
      walked = []
      cursor = nil

      clean_names.size.times do
        get_page(cursor: cursor)
        walked.concat(names)
        cursor = response.header['X-Next-Page']
        break if cursor.blank?
      end

      expect(walked).to eq(clean_names)
    end

    it 'pages backwards to the previous page, not the first page' do
      get_page
      get_page(cursor: response.header['X-Next-Page'])
      get_page(cursor: response.header['X-Next-Page'])

      expect(names).to eq(%w[entityframework])

      get_page(cursor: response.header['X-Prev-Page'])

      expect(names).to eq(%w[classnames debug])
    end

    it 'rejects an unparseable cursor', :aggregate_failures do
      get_page(cursor: 'not-a-cursor')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('Invalid cursor')
    end

    it 'rejects a cursor whose after_key names fields the aggregation does not have', :aggregate_failures do
      cursor = Search::Elastic::CompositePagination::Paginator::CURSOR_CONVERTER.dump(
        after_key: { 'not_a_source' => 'x' }, sort_by: 'name', sort: 'asc', _kd: 'n'
      )

      get_page(cursor: cursor)

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('Invalid cursor after_key')
    end

    it 'rejects a cursor minted under a different sort', :aggregate_failures do
      get_page
      cursor = response.header['X-Next-Page']

      get_page(cursor: cursor, sort_by: 'severity')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('The cursor was created for a different ordering')
    end
  end

  # Postgres cannot filter by malware, so every fallback below ignores the filter.
  describe 'when the malware filter is not available' do
    shared_examples 'falling back to Postgres' do
      it 'does not reach the Elasticsearch finder' do
        expect(::Search::AdvancedFinders::Sbom::AggregationsFinder).not_to receive(:new)

        request_page
      end

      it 'serves the list with the malware filter ignored', :aggregate_failures do
        request_page

        expect(response).to have_gitlab_http_status(:ok)
        expect(names).to match_array(clean_names + %w[malicious])
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(malicious_packages_dependency_list_filtering: false)
      end

      it_behaves_like 'falling back to Postgres' do
        let(:request_page) { get_page(per_page: 20) }
      end
    end

    context 'when the index is not ready for reads' do
      before do
        allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
          .to receive(:advanced_dependency_management_allowed?).and_return(false)
      end

      it_behaves_like 'falling back to Postgres' do
        let(:request_page) { get_page(per_page: 20) }
      end

      context 'when a project filter is also applied' do
        it_behaves_like 'falling back to Postgres' do
          let(:request_page) { get_page(per_page: 20, project_ids: [project.id]) }
        end

        it 'paginates by offset rather than cursor' do
          get_page(per_page: 20, project_ids: [project.id])

          expect(response.header['X-Page-Type']).to be_nil
        end
      end
    end
  end

  def create_occurrence(name)
    component = create(:sbom_component, name: name)

    create(:sbom_occurrence, :with_refs, :mit, :npm,
      project: project,
      component: component,
      component_version: create(:sbom_component_version, component: component, version: '1.0.0'),
      tracked_contexts: [tracked_context])
  end
end
