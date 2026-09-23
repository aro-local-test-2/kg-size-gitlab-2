# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Sbom::DependenciesResolver, feature_category: :vulnerability_management do
  include GraphqlHelpers

  before do
    stub_licensed_features(security_dashboard: true, dependency_scanning: true)
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { create(:group, developers: user) }
  let_it_be(:project_1) { create(:project, namespace: namespace) }
  let_it_be(:project_2) { create(:project, namespace: namespace) }

  let_it_be(:component_1) { create(:sbom_component, name: "activestorage") }
  let_it_be(:occurrence_1) { create(:sbom_occurrence, component: component_1, project: project_1) }

  let_it_be(:component_2) { create(:sbom_component, name: "activesupport") }
  let_it_be(:occurrence_2) { create(:sbom_occurrence, component: component_2, project: project_1) }
  let_it_be(:occurrence_3) { create(:sbom_occurrence, component: component_2, project: project_2) }

  let_it_be(:mit_component) { create(:sbom_component, name: "mit-licensed") }
  let_it_be(:occurrence_mit) { create(:sbom_occurrence, :mit, component: mit_component, project: project_1) }

  let_it_be(:apache_component) { create(:sbom_component, name: "apache-licensed") }
  let_it_be(:occurrence_apache) { create(:sbom_occurrence, :apache_2, component: apache_component, project: project_1) }

  subject(:sync_resolve) { sync(resolve_dependencies(args: args)) }

  shared_examples 'supports filtering by component name' do
    let(:args) { { component_names: [component_1.name] } }

    it { is_expected.to match_array([occurrence_1]) }
  end

  shared_examples 'supports filtering by license' do
    context 'when a matching license is given' do
      let(:args) { { licenses: ['MIT'] } }

      it { is_expected.to match_array([occurrence_mit]) }
    end

    context 'when a non-matching license is given' do
      let(:args) { { licenses: ['BSD-3-Clause'] } }

      it { is_expected.to be_empty }
    end
  end

  shared_examples 'rejects the malware filter' do
    context 'when malware: true is given' do
      let(:args) { { malware: true } }

      it 'returns a GraphQL ArgumentError' do
        expect_graphql_error_to_be_created(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The malware filter is not available.'
        ) { sync_resolve }
      end
    end

    context 'when malware: false is given' do
      let(:args) { { malware: false } }

      it 'returns a GraphQL ArgumentError' do
        expect_graphql_error_to_be_created(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The malware filter is not available.'
        ) { sync_resolve }
      end
    end
  end

  # The flag guards the argument on every mount, so an unavailable flag is rejected everywhere.
  shared_examples 'rejects the malware filter when the flag is disabled' do
    context 'when malicious_packages_dependency_list_filtering feature flag is disabled' do
      before do
        stub_feature_flags(malicious_packages_dependency_list_filtering: false)
      end

      it_behaves_like 'rejects the malware filter'
    end
  end

  shared_examples 'drops the malware filter instead of rejecting it' do
    let(:args) { { malware: true } }

    it 'returns the unfiltered dependency list' do
      expect(::Search::AdvancedFinders::Sbom::DependenciesFinder).not_to receive(:new)

      expect(sync_resolve).to match_array(unfiltered_occurrences)
    end
  end

  shared_examples 'rejects the malware filter on non-default tracked refs for dependencies' do
    let_it_be(:default_tracked_ref) { create(:security_project_tracked_context, :default, project: project_1) }
    let_it_be(:non_default_tracked_ref) { create(:security_project_tracked_context, project: project_1) }

    shared_examples 'returns the conflict error' do
      it 'returns a GraphQL ArgumentError' do
        expect_graphql_error_to_be_created(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The malware filter cannot be combined with non-default tracked refs.'
        ) { sync_resolve }
      end
    end

    context 'when malware: true is combined with the ALL_REFS scope' do
      let(:args) { { malware: true, tracked_refs_scope: 'ALL_REFS' } }

      it_behaves_like 'returns the conflict error'
    end

    context 'when malware: false is combined with the ALL_REFS scope' do
      let(:args) { { malware: false, tracked_refs_scope: 'ALL_REFS' } }

      it_behaves_like 'returns the conflict error'
    end

    context 'when malware is combined with a non-default tracked ref' do
      let(:args) { { malware: true, tracked_ref_ids: [non_default_tracked_ref.to_global_id] } }

      it_behaves_like 'returns the conflict error'
    end

    context 'when malware is combined with both a default and a non-default tracked ref' do
      let(:args) do
        {
          malware: true,
          tracked_ref_ids: [default_tracked_ref.to_global_id, non_default_tracked_ref.to_global_id]
        }
      end

      it_behaves_like 'returns the conflict error'
    end
  end

  shared_examples 'does not use the advanced dependency finder' do
    let(:args) { { malware: true } }

    before do
      allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
        .to receive(:advanced_dependency_management_allowed?).and_return(true)
    end

    it 'resolves from Postgres' do
      expect(::Search::AdvancedFinders::Sbom::DependenciesFinder).not_to receive(:new)

      expect(sync_resolve).to match_array(unfiltered_occurrences)
    end
  end

  context 'when given a project' do
    let(:project_or_namespace) { project_1 }
    let(:unfiltered_occurrences) { [occurrence_1, occurrence_2, occurrence_mit, occurrence_apache] }

    it_behaves_like 'supports filtering by component name'
    it_behaves_like 'supports filtering by license'
    it_behaves_like 'rejects the malware filter when the flag is disabled'
    it_behaves_like 'rejects the malware filter on non-default tracked refs for dependencies'

    # Sbom::AdvancedDependencyManagementPolicy prevents the ability when the sbom_occurrence_refs
    # index cannot serve reads, which is the default in specs.
    context 'when advanced dependency management is unavailable' do
      it_behaves_like 'rejects the malware filter'
    end

    context 'when given component_ids' do
      let(:args) do
        {
          component_ids: [component_1.to_gid]
        }
      end

      it { is_expected.to match_array([occurrence_1]) }

      it "triggers an internal event" do
        expect { sync_resolve }.to trigger_internal_events('called_dependency_api').with(
          user: user,
          project: project_1,
          additional_properties: { label: 'graphql' }
        )
      end
    end

    describe 'switching to the advanced dependency finder' do
      let(:index_available) { true }
      let(:relation) { instance_double(::Search::Elastic::Relation) }
      let(:advanced_finder) do
        instance_double(::Search::AdvancedFinders::Sbom::DependenciesFinder, execute: relation)
      end

      before do
        allow(relation).to receive(:preload).and_return(relation)
        allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
          .to receive(:advanced_dependency_management_allowed?).and_return(index_available)
        allow(::Search::AdvancedFinders::Sbom::DependenciesFinder).to receive(:new).and_return(advanced_finder)
      end

      shared_examples 'uses the advanced finder' do |expected_params|
        # The relation is handed to the connection unwrapped, so ElasticConnection keyset-paginates
        # it rather than OffsetPaginatedRelation.
        it 'forwards the filter and returns the relation unwrapped' do
          expect(sync_resolve.items).to eq(relation)

          expect(::Search::AdvancedFinders::Sbom::DependenciesFinder).to have_received(:new)
            .with(project_1, params: hash_including(expected_params))
        end
      end

      shared_examples 'stays on Postgres' do
        it 'does not use the advanced finder' do
          sync_resolve

          expect(::Search::AdvancedFinders::Sbom::DependenciesFinder).not_to have_received(:new)
        end
      end

      context 'when malware: true is given' do
        let(:args) { { malware: true } }

        it_behaves_like 'uses the advanced finder', malware: true
      end

      context 'when malware: false is given' do
        let(:args) { { malware: false } }

        it_behaves_like 'uses the advanced finder', malware: false
      end

      context 'when no advanced filter is given' do
        let(:args) { { component_names: [component_1.name] } }

        it_behaves_like 'stays on Postgres'
      end

      context 'when malware is combined with only default tracked refs' do
        let_it_be(:default_ref) { create(:security_project_tracked_context, :default, project: project_1) }

        let(:args) { { malware: true, tracked_ref_ids: [default_ref.to_global_id] } }

        it_behaves_like 'uses the advanced finder', malware: true
      end

      # An id that resolves to nothing is not a non-default ref, so it is not rejected here.
      context 'when malware is combined with a tracked ref that does not exist' do
        let(:args) do
          {
            malware: true,
            tracked_ref_ids: [
              ::Gitlab::GlobalId.build(model_name: 'Security::ProjectTrackedContext', id: non_existing_record_id)
            ]
          }
        end

        it_behaves_like 'uses the advanced finder', malware: true
      end

      # A ref outside the queried project is out of scope, so it reads the same as an unknown
      # id rather than erroring and revealing that it exists.
      context 'when malware is combined with a non-default tracked ref from another project' do
        let_it_be(:other_project_ref) { create(:security_project_tracked_context, project: project_2) }

        let(:args) { { malware: true, tracked_ref_ids: [other_project_ref.to_global_id] } }

        it_behaves_like 'uses the advanced finder', malware: true
      end

      context 'when policy_violations is combined with an advanced filter' do
        let(:args) { { malware: true, policy_violations: [:dismissed_in_mr] } }

        it 'returns a GraphQL ArgumentError' do
          expect_graphql_error_to_be_created(
            ::Gitlab::Graphql::Errors::ArgumentError,
            'The policy_violations filter cannot be combined with the malware filter.'
          ) { sync_resolve }
        end

        context 'when the sbom_occurrence_refs index is not available' do
          let(:index_available) { false }

          it 'still returns a GraphQL ArgumentError' do
            expect_graphql_error_to_be_created(
              ::Gitlab::Graphql::Errors::ArgumentError,
              'The policy_violations filter cannot be combined with the malware filter.'
            ) { sync_resolve }
          end
        end
      end
    end
  end

  context 'when given a namespace' do
    let(:project_or_namespace) { namespace }
    let(:unfiltered_occurrences) { [occurrence_1, occurrence_2, occurrence_3, occurrence_mit, occurrence_apache] }

    it_behaves_like 'supports filtering by component name'
    it_behaves_like 'supports filtering by license'
    it_behaves_like 'rejects the malware filter when the flag is disabled'
    it_behaves_like 'drops the malware filter instead of rejecting it'
    it_behaves_like 'rejects the malware filter on non-default tracked refs for dependencies'
    # The advanced finder is project-scoped, so a namespace stays on Postgres.
    it_behaves_like 'does not use the advanced dependency finder'

    context 'when given component_ids' do
      let(:args) do
        {
          component_ids: [component_2.to_gid]
        }
      end

      it { is_expected.to match_array([occurrence_2, occurrence_3]) }

      it "triggers an internal event" do
        expect { sync_resolve }.to trigger_internal_events('called_dependency_api').with(
          user: user,
          namespace: namespace,
          additional_properties: { label: 'graphql' }
        )
      end
    end
  end

  context 'when given a vulnerability' do
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project_1) }
    let_it_be(:vulnerable_occurrence) do
      create(:sbom_occurrences_vulnerability, occurrence: occurrence_1, vulnerability: vulnerability)
      occurrence_1
    end

    let(:project_or_namespace) { vulnerability }
    let(:unfiltered_occurrences) { [vulnerable_occurrence] }

    before do
      allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
        .to receive(:advanced_dependency_management_allowed?).and_return(true)
    end

    context 'when no malware filter is given' do
      let(:args) { {} }

      it { is_expected.to match_array(unfiltered_occurrences) }
    end

    it_behaves_like 'rejects the malware filter when the flag is disabled'
    it_behaves_like 'drops the malware filter instead of rejecting it'
    it_behaves_like 'rejects the malware filter on non-default tracked refs for dependencies'

    context 'when malware: true is given' do
      let(:args) { { malware: true } }

      it 'resolves from Postgres without raising' do
        expect(::Search::AdvancedFinders::Sbom::DependenciesFinder).not_to receive(:new)

        expect { sync_resolve }.not_to raise_error
        expect(sync_resolve).to match_array(unfiltered_occurrences)
      end
    end
  end

  # The unit specs above stub the finder, so they cannot show which connection class the schema
  # picks for a real Search::Elastic::Relation, nor that records map back out of the index.
  describe 'resolving through the advanced finder', :elastic_delete_by_query, :elasticsearch_settings_enabled do
    let_it_be(:es_project) { create(:project, namespace: namespace) }
    let_it_be(:default_context) { create(:security_project_tracked_context, :default, project: es_project) }
    let_it_be(:branch_context) { create(:security_project_tracked_context, :tracked, project: es_project) }

    let_it_be(:default_occurrence) do
      create(:sbom_occurrence, :with_refs, project: es_project, tracked_contexts: [default_context])
    end

    let_it_be(:branch_occurrence) do
      create(:sbom_occurrence, :with_refs, project: es_project, tracked_contexts: [branch_context])
    end

    let(:project_or_namespace) { es_project }

    before do
      ::Elastic::ProcessBookkeepingService.track!(*::Sbom::OccurrenceRef.all.to_a)
      ensure_elasticsearch_index!
    end

    # The finder always restricts to the default branch. Postgres has no notion of tracked refs
    # and would return the non-default occurrence too, so excluding it proves the index served
    # the query.
    context 'when malware is given' do
      let(:args) { { malware: false } }

      it 'keyset-paginates the relation instead of applying the offset wrapper' do
        expect(resolve_dependencies(args: args)).to be_a(::Gitlab::Graphql::Pagination::ElasticConnection)
      end

      it { is_expected.to match_array([default_occurrence]) }
    end
  end

  describe 'malware N+1 queries (group level)' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project_a) { create(:project, namespace: group) }
    let_it_be(:project_b) { create(:project, namespace: group) }
    let_it_be(:user_with_access) { create(:user) }

    let(:query) do
      %(
        query {
          group(fullPath: "#{group.full_path}") {
            dependencies {
              nodes {
                name
                malware
              }
            }
          }
        }
      )
    end

    before_all do
      group.add_developer(user_with_access)
    end

    before do
      stub_licensed_features(security_dashboard: true, dependency_scanning: true)
    end

    it 'avoids N+1 database queries when fetching malware across group dependencies', :request_store do
      component_1 = create(:sbom_component)
      occurrence_1 = create(:sbom_occurrence, component: component_1, project: project_a)
      vulnerability_1 = create(:vulnerability, :with_finding, project: project_a)
      create(:sbom_occurrences_vulnerability, occurrence: occurrence_1, vulnerability: vulnerability_1)
      vulnerability_1.vulnerability_read.update!(identifier_names: ['CVE-2021-1234'])

      control = ActiveRecord::QueryRecorder.new do
        GitlabSchema.execute(query, context: { current_user: user_with_access })
      end

      # Add more occurrences across multiple projects to verify no N+1
      3.times do
        component = create(:sbom_component)
        occurrence = create(:sbom_occurrence, component: component, project: project_b)
        vulnerability = create(:vulnerability, :with_finding, project: project_b)
        create(:sbom_occurrences_vulnerability, occurrence: occurrence, vulnerability: vulnerability)
        vulnerability.vulnerability_read.update!(identifier_names: ['CVE-2021-1234'])
      end

      expect do
        GitlabSchema.execute(query, context: { current_user: user_with_access })
      end.not_to exceed_query_limit(control)
    end
  end

  private

  def resolve_dependencies(args: {})
    resolve(
      described_class,
      obj: project_or_namespace,
      args: args,
      ctx: { current_user: user }
    )
  end
end
