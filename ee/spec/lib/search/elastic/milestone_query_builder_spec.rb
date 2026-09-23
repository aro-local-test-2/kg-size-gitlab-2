# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::MilestoneQueryBuilder, :elastic_helpers, feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:private_project) { create(:project, :private) }
  let_it_be(:authorized_project) { create(:project, developers: [user]) }

  let(:base_options) do
    {
      current_user: user,
      project_ids: project_ids,
      group_ids: [],
      search_level: 'global',
      public_and_internal_projects: true
    }
  end

  let(:query) { 'foo' }
  let(:project_ids) { [] }
  let(:options) { base_options }

  subject(:build) { described_class.build(query: query, options: options) }

  # Each membership clause pairs one project id list with the feature predicates that list is allowed to
  # match, so assertions about a predicate have to read the list from its own clause.
  def membership_clauses(scope)
    clauses = []

    visit = ->(node) do
      node = node.to_h if node.is_a?(::Search::Elastic::BoolExpr)

      case node
      when Hash
        clause = membership_clause(node, scope)
        clauses << clause if clause
        node.each_value { |value| visit.call(value) }
      when Array
        node.each { |value| visit.call(value) }
      end
    end

    visit.call(build)
    clauses
  end

  # A clause owns the project id list sitting directly in its own filter array. Searching deeper would
  # also match every ancestor of that clause.
  def membership_clause(node, scope)
    filters = node.dig(:bool, :filter)
    return unless filters.is_a?(Array)

    project_ids = filters.filter_map { |filter| filter[:terms][:project_id] if filter.key?(:terms) }.first
    return unless project_ids

    names = node.extend(Hashie::Extensions::DeepFind).deep_find_all(:_name) || []
    return unless names.grep(/:#{scope}:/).any?

    { names: names, project_ids: project_ids }
  end

  def membership_clause_for(scope, name)
    membership_clauses(scope).find { |clause| clause[:names].include?(name) }
  end

  it 'contains all expected filters' do
    assert_names_in_query(build, with: %w[
      milestone:multi_match:and:search_terms
      milestone:multi_match_phrase:search_terms
      filters:doc:is_a:milestone
      filters:permissions:global:visibility_level:public_and_internal
      filters:non_archived
    ])
  end

  context 'when advanced query syntax is used' do
    let(:query) { 'foo -default' }

    it 'uses simple_query_string in query' do
      assert_names_in_query(build, with: %w[milestone:match:search_terms],
        without: %w[milestone:multi_match:and:search_terms milestone:multi_match_phrase:search_terms])
    end
  end

  describe 'fields' do
    it 'defaults to title and description' do
      assert_fields_in_query(build, with: %w[title^2 description])
    end

    context 'when fields option is provided' do
      let(:options) { base_options.merge(fields: ['title']) }

      it 'uses the provided fields' do
        assert_fields_in_query(build, with: %w[title], without: %w[title^2 description])
      end
    end
  end

  describe 'filters' do
    let(:project_ids) { [authorized_project.id, private_project.id] }

    it_behaves_like 'a query filtered by archived'

    describe 'authorization' do
      it 'uses the new authorization filter' do
        assert_names_in_query(build,
          with: %w[filters:permissions:global:visibility_level:public_and_internal],
          without: %w[filters:project])
      end

      context 'when current_user is nil' do
        let(:base_options) do
          {
            current_user: nil,
            project_ids: project_ids,
            group_ids: [],
            search_level: 'global',
            public_and_internal_projects: true
          }
        end

        it 'restricts the authorization filter to public projects only' do
          assert_names_in_query(build,
            with: %w[filters:permissions:global:visibility_level:public],
            without: %w[filters:permissions:global:visibility_level:public_and_internal])
        end
      end

      context 'when search_level is group' do
        let(:base_options) do
          {
            current_user: user,
            project_ids: [authorized_project.id],
            group_ids: [group.id],
            search_level: 'group',
            public_and_internal_projects: true
          }
        end

        it 'applies group-level authorization filters' do
          assert_names_in_query(build, with: %w[filters:level:group])
        end
      end

      context 'when search_level is project' do
        let(:base_options) do
          {
            current_user: user,
            project_ids: [authorized_project.id],
            group_ids: [],
            search_level: 'project',
            public_and_internal_projects: false
          }
        end

        it 'applies project-level authorization filters' do
          assert_names_in_query(build, with: %w[filters:level:project])
        end
      end

      context 'when a member is below the merge_requests Reporter minimum' do
        let_it_be(:guest_user) { create(:user) }
        let_it_be(:planner_user) { create(:user) }
        let_it_be(:non_member_user) { create(:user) }
        let_it_be(:issues_disabled_project) do
          create(:project, :private, :issues_disabled, guests: [guest_user], planners: [planner_user])
        end

        let(:base_options) do
          {
            current_user: current_user,
            project_ids: [issues_disabled_project.id],
            group_ids: [],
            search_level: 'global',
            public_and_internal_projects: false
          }
        end

        let(:relaxed_filter_names) do
          %w[
            filters:permissions:global:private_access:merge_requests_access_level:enabled
            filters:permissions:global:private_access:project:member
          ]
        end

        context 'with a Guest member' do
          let(:current_user) { guest_user }

          it 'adds the relaxed merge_requests filter' do
            assert_names_in_query(build, with: relaxed_filter_names)
          end

          it 'restricts the relaxed filter to the ENABLED feature access level' do
            query = build.extend(Hashie::Extensions::DeepFind)
            terms = query.deep_find_all(:terms).find { |t| t[:_name] == relaxed_filter_names.first }

            expect(terms[:merge_requests_access_level]).to eq([::ProjectFeature::ENABLED])
          end

          it 'keeps the issues predicate alongside the relaxed one' do
            assert_names_in_query(build,
              with: %w[filters:permissions:global:private_access:issues_access_level:enabled_or_private])
          end

          # The relaxed rule resolves to the same GUEST id list as the issues rule, so the two share a
          # clause instead of repeating that list in the query body.
          it 'serializes the shared project id list once' do
            query = build.extend(Hashie::Extensions::DeepFind)
            project_id_terms = query.deep_find_all(:terms).select { |terms| terms.key?(:project_id) }

            expect(project_id_terms.size).to eq(1)
          end

          # A custom role grants one feature, not the relaxed route to another. The public/internal bucket
          # has to be non-empty here, because that is the list the relaxed clause used to share by
          # reference with the issues clause.
          context 'when a custom role grants the issues ability on another project' do
            let(:public_and_internal_scope) { 'public_and_internal_access' }
            let_it_be(:custom_role_project) { create(:project, :private) }
            let_it_be(:public_issues_disabled_project) do
              create(:project, :public, :issues_disabled, guests: [guest_user])
            end

            before do
              stub_const(
                "#{::Search::Concerns::FeatureCustomAbilityMap}::FEATURE_TO_ABILITY_MAP",
                { issues: :read_issue }
              )

              allow_next_instance_of(::Authz::Project) do |authz|
                allow(authz).to receive(:permitted).and_return(custom_role_project.id => [:read_issue])
              end
            end

            it 'excludes the custom-role project from the relaxed merge_requests clause' do
              relaxed = membership_clause_for(
                public_and_internal_scope,
                'filters:permissions:global:public_and_internal_access:merge_requests_access_level:enabled'
              )

              expect(relaxed[:project_ids]).to include(public_issues_disabled_project.id)
              expect(relaxed[:project_ids]).not_to include(custom_role_project.id)
            end

            it 'keeps the custom-role project reachable through the issues clause' do
              issues = membership_clause_for(
                public_and_internal_scope,
                'filters:permissions:global:public_and_internal_access:issues_access_level:enabled_or_private'
              )

              expect(issues[:project_ids]).to include(custom_role_project.id)
            end

            it 'does not merge the two rules into one clause' do
              expect(membership_clauses(public_and_internal_scope).size).to eq(2)
            end
          end
        end

        context 'with a Planner member' do
          let(:current_user) { planner_user }

          it 'adds the relaxed merge_requests filter' do
            assert_names_in_query(build, with: relaxed_filter_names)
          end
        end

        context 'with a non-member' do
          let(:current_user) { non_member_user }

          it 'does not add the relaxed merge_requests filter' do
            assert_names_in_query(build, without: relaxed_filter_names)
          end
        end

        context 'when access comes from group membership' do
          let_it_be(:group_guest_user) { create(:user) }
          let_it_be(:private_group) { create(:group, :private, guests: [group_guest_user]) }

          let(:current_user) { group_guest_user }

          it 'adds the relaxed merge_requests filter for the group ancestry' do
            assert_names_in_query(build,
              with: %w[filters:permissions:global:private_access:merge_requests_access_level:enabled
                filters:permissions:global:private_access:ancestry_filter:descendants])
          end
        end

        context 'when an external member accesses an internal project' do
          let_it_be(:external_user) { create(:user, :external) }
          let_it_be(:internal_project) do
            create(:project, :internal, :issues_disabled, guests: [external_user])
          end

          let(:current_user) { external_user }
          let(:base_options) do
            {
              current_user: current_user,
              project_ids: [internal_project.id],
              group_ids: [],
              search_level: 'global',
              public_and_internal_projects: true
            }
          end

          # The membership-free public/internal clause is capped at PUBLIC visibility for external
          # users, so only the relaxed membership clause can reach an internal project here.
          it 'adds the relaxed merge_requests filter for public and internal projects' do
            assert_names_in_query(build,
              with: %w[filters:permissions:global:public_and_internal_access:merge_requests_access_level:enabled])
          end
        end
      end
    end
  end

  describe 'formats' do
    it_behaves_like 'a query that sets source_fields'
    it_behaves_like 'a query formatted for size'
  end
end
