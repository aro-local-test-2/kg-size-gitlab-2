# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::AdvancedFinders::GroupsFinder, :elastic, :sidekiq_inline,
  feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:parent_group) { create(:group, :public, name: 'test-parent') }
  let_it_be(:subgroup) { create(:group, :public, parent: parent_group, name: 'test-child') }
  let_it_be(:other_group) { create(:group, :public, name: 'test-other') }

  let(:params) { { search: 'test' } }

  subject(:finder) { described_class.new(user, params) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    ::Elastic::ProcessInitialBookkeepingService.track!(parent_group, subgroup, other_group)
    ensure_elasticsearch_index!
  end

  describe '#use_elasticsearch_finder?' do
    it 'is true when every precondition holds' do
      expect(finder.use_elasticsearch_finder?).to be(true)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(advanced_groups_finder_elasticsearch: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when advanced search is disabled' do
      before do
        stub_ee_application_setting(elasticsearch_search: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when indexing is paused' do
      before do
        stub_ee_application_setting(elasticsearch_pause_indexing: true)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when the backfill migration has not finished' do
      before do
        set_elasticsearch_migration_to(:backfill_groups_to_elasticsearch, including: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    describe 'filter allowlist' do
      where(:params, :supported) do
        [
          [{ search: 'test' }, true],
          # The index stores the group's own archived flag; GroupsFinder is ancestor-aware.
          [{ search: 'test', archived: true }, false],
          [{ search: 'test', archived: false }, false],
          [{ search: 'test', include_parent_descendants: true }, true],
          [{ search: 'test', ids: [1] }, true],
          [{ search: 'test', exclude_group_ids: [1] }, true],
          [{ search: 'test', sort: 'created_desc' }, true],
          [{ search: 'test', visibility: 'public' }, true],
          [{ search: 'test', min_access_level: Gitlab::Access::DEVELOPER }, false],
          [{ search: 'test', all_available: false }, false],
          [{ search: 'test', include_parent_shared_groups: true }, false],
          [{ search: 'test', custom_attributes: { foo: 'bar' } }, false]
        ]
      end

      with_them do
        it 'only claims the query when every filter is expressible in Elasticsearch' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(supported)
        end
      end
    end

    # An unfiltered listing always exceeds RESULT_LIMIT on a real instance, so #execute
    # would discard the hits. Declining up front avoids the wasted round trip.
    describe 'without a search term' do
      where(:params) { [{}, { search: '' }, { search: nil }, { include_parent_descendants: true }] }

      with_them do
        it 'is false' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(false)
        end
      end
    end

    describe 'params that do not narrow the query' do
      where(:params, :supported) do
        [
          [{ search: 'test', with_statistics: true }, false],
          [{ search: 'test', owned: false }, true],
          [{ search: 'test', owned: true }, false],
          [{ search: 'test', top_level_only: false }, true],
          [{ search: 'test', filter_expired_saml_session_groups: false }, true],
          [{ search: 'test', filter_expired_saml_session_groups: true }, false],
          [{ search: 'test', with_knowledge_graph_enabled: false }, true],
          [{ search: 'test', with_knowledge_graph_enabled: true }, false],
          # GroupsFinder skips a filter whose value is nil, so nil does not narrow.
          [{ search: 'test', active: nil }, true],
          [{ search: 'test', archived: nil }, true],
          # Except where GroupsFinder reads the param with a truthy-default fetch, which
          # makes an explicit nil behave like false rather than like an absent key.
          [{ search: 'test', all_available: nil }, false],
          [{ search: 'test', include_ancestors: nil }, false],
          # A GraphQL request with every default applied.
          [{ search: 'test', with_statistics: false, all_available: true, owned: false,
             top_level_only: false, active: nil, sort: 'name_asc', allow_similarity_sort: true }, true]
        ]
      end

      with_them do
        it 'ignores no-op values and honours real ones' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(supported)
        end
      end
    end

    # Namespaces::GroupsFinder passes ActionController::Parameters through untouched, so
    # the allowlist check has to cope with a non-Enumerable params object.
    describe 'with ActionController::Parameters' do
      it 'reads the params without raising' do
        params = ActionController::Parameters.new(search: 'test')

        expect(described_class.new(user, params).use_elasticsearch_finder?).to be(true)
      end

      it 'still rejects an unsupported filter' do
        params = ActionController::Parameters.new(search: 'test', owned: true)

        expect(described_class.new(user, params).use_elasticsearch_finder?).to be(false)
      end
    end

    describe 'sorting' do
      # Sorting runs in PostgreSQL on the re-hydrated relation, so no sort disqualifies
      # Elasticsearch, including name_asc which the groups index cannot sort on.
      where(:sort) { %w[name_asc name_desc path_asc created_asc updated_desc similarity id_desc] }

      with_them do
        it 'still uses Elasticsearch' do
          expect(described_class.new(user, search: 'test', sort: sort).use_elasticsearch_finder?)
            .to be(true)
        end
      end
    end
  end

  describe '#execute' do
    it 'returns an ActiveRecord::Relation so callers can paginate and chain scopes' do
      expect(finder.execute).to be_a(ActiveRecord::Relation)
      expect(finder.execute.page(1).per(2).size).to eq(2)
    end

    it 'returns the matching groups' do
      expect(finder.execute).to contain_exactly(parent_group, subgroup, other_group)
    end

    it 'preloads routes so rendering full_path does not N+1' do
      expect(finder.execute.first.association(:route)).to be_loaded
    end

    describe 'ordering' do
      let(:params) { { search: 'test', sort: 'name_asc', allow_similarity_sort: true } }

      it 'orders by name even though the index cannot sort on it' do
        expect(finder.execute.map(&:name)).to eq(%w[test-child test-other test-parent])
      end

      it 'matches the order PostgreSQL would have produced' do
        expected = GroupsFinder.new(user, params).execute.map(&:id)

        expect(finder.execute.map(&:id)).to eq(expected)
      end

      context 'with a descending sort' do
        let(:params) { { search: 'test', sort: 'name_desc' } }

        it 'reverses the order' do
          expect(finder.execute.map(&:name)).to eq(%w[test-parent test-other test-child])
        end
      end
    end

    describe 'filtering by visibility' do
      let_it_be(:internal_group) { create(:group, :internal, name: 'test-internal') }
      let_it_be(:private_group) { create(:group, :private, name: 'test-private') }

      before_all do
        private_group.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(internal_group, private_group)
        ensure_elasticsearch_index!
      end

      context 'with a single level' do
        let(:params) { { search: 'test', visibility: 'internal' } }

        it 'returns only groups at that level' do
          expect(finder.execute).to contain_exactly(internal_group)
        end
      end

      context 'with several levels' do
        let(:params) { { search: 'test', visibility: %w[internal private] } }

        it 'returns groups at any of them' do
          expect(finder.execute).to contain_exactly(internal_group, private_group)
        end
      end

      context 'without the filter' do
        let(:params) { { search: 'test' } }

        it 'returns every visible group' do
          expect(finder.execute).to include(internal_group, private_group, parent_group)
        end
      end

      it 'matches what PostgreSQL returns' do
        %w[public internal private].each do |level|
          params = { search: 'test', visibility: level }
          expected = GroupsFinder.new(user, params).execute

          expect(described_class.new(user, params).execute).to match_array(expected)
        end
      end

      # An anonymous user can only ever see public groups, so intersecting that with a
      # request for private levels leaves nothing. The filter must return no results
      # rather than being skipped, which is the case an `if levels.blank?` guard in the
      # Elasticsearch filter would get wrong.
      context 'when the user cannot access any of the requested levels' do
        let(:params) { { search: 'test', visibility: 'private' } }

        it 'returns nothing rather than ignoring the filter' do
          expect(described_class.new(nil, params).execute).to be_empty
        end

        it 'matches what PostgreSQL returns' do
          expect(described_class.new(nil, params).execute)
            .to match_array(GroupsFinder.new(nil, params).execute)
        end
      end
    end

    # Asserting on use_elasticsearch_finder? alone is not enough: an allowed filter that
    # search_options never maps is ignored by Elasticsearch, which returns a wider set
    # than PostgreSQL without any error. Every entry in ALLOWED_ES_FILTERS needs a case
    # here comparing actual results.
    describe 'parity with GroupsFinder for every allowed filter' do
      let_it_be(:grandchild) { create(:group, :public, parent: subgroup, name: 'test-grandchild') }
      let_it_be(:archived_group) { create(:group, :public, :archived, name: 'test-archived') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(grandchild, archived_group)
        ensure_elasticsearch_index!
      end

      # Built inside the example because the params reference let_it_be records.
      def params_for(case_name)
        case case_name
        when :search_only then {}
        when :ids then { ids: [other_group.id] }
        when :exclude_group_ids then { exclude_group_ids: [other_group.id] }
        when :organization then { organization: parent_group.organization }
        # GroupsFinder accepts an id here, and dropping the filter would widen the query.
        when :organization_id then { organization: parent_group.organization.id }
        when :parent_children then { parent: parent_group }
        when :parent_descendants then { parent: parent_group, include_parent_descendants: true }
        when :visibility then { visibility: 'public' }
        end
      end

      where(:case_name) do
        %i[search_only ids exclude_group_ids organization organization_id parent_children
          parent_descendants visibility]
      end

      with_them do
        it 'returns the same groups as GroupsFinder' do
          params = { search: 'test' }.merge(params_for(case_name))
          expected = GroupsFinder.new(user, params).execute

          finder = ::Search::AdvancedFinders::GroupsFinder.new(user, params)

          expect(finder.use_elasticsearch_finder?).to be(true), "#{case_name} unexpectedly fell back"
          expect(finder.execute).to match_array(expected), "#{case_name} diverged"
        end
      end
    end

    # Regressions the match_array parity cases could not see.

    # The index stores each group's own archived flag, while GroupsFinder is
    # ancestor-aware, so a subgroup under an archived parent would diverge.
    context 'with an archived ancestor' do
      let_it_be(:archived_parent) { create(:group, :public, :archived, name: 'test-archived-parent') }
      let_it_be(:child_of_archived) { create(:group, :public, parent: archived_parent, name: 'test-under-archived') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(archived_parent, child_of_archived)
        ensure_elasticsearch_index!
      end

      where(:archived) { [true, false] }

      with_them do
        it 'falls back rather than diverging on inherited archived state' do
          finder = ::Search::AdvancedFinders::GroupsFinder.new(user, search: 'test', archived: archived)

          expect(finder.use_elasticsearch_finder?).to be(false)
        end
      end
    end

    # GroupQueryBuilder matches description by default; Group.search does not.
    context 'when the term only appears in a description' do
      let_it_be(:described) do
        create(:group, :public, name: 'unrelated-name', description: 'test-only-in-description')
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(described)
        ensure_elasticsearch_index!
      end

      it 'does not return the group, matching GroupsFinder' do
        params = { search: 'test-only-in-description' }

        expect(::Search::AdvancedFinders::GroupsFinder.new(user, params).execute)
          .to match_array(GroupsFinder.new(user, params).execute)
      end
    end

    # GroupsFinder's in_organization accepts either shape, and a dropped filter would
    # widen across every organization instead of erroring.
    context 'with an organization filter' do
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:foreign_group) do
        create(:group, :public, organization: other_organization, name: 'test-foreign')
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(foreign_group)
        ensure_elasticsearch_index!
      end

      where(:organization) { [ref(:other_organization), lazy { other_organization.id }] }

      with_them do
        it 'scopes to the organization for a record and for an id' do
          finder = described_class.new(user, search: 'test', organization: organization)

          expect(finder.execute).to contain_exactly(foreign_group)
        end
      end
    end

    # match_array hides ordering, so similarity needs an ordered comparison.
    it 'orders identically to GroupsFinder for similarity' do
      params = { search: 'test', sort: 'similarity', allow_similarity_sort: true }
      expected = GroupsFinder.new(user, params).execute.map(&:id)

      expect(::Search::AdvancedFinders::GroupsFinder.new(user, params).execute.map(&:id)).to eq(expected)
    end

    it 'preloads namespace_details like GroupsFinder, so description_html does not N+1' do
      expect(finder.execute.first.association(:namespace_details)).to be_loaded
    end

    context 'when Elasticsearch truncated the match set' do
      before do
        stub_const('EE::Search::AdvancedFinders::GroupsFinder::RESULT_LIMIT', 1)
      end

      it 'returns nil rather than sorting an incomplete set' do
        expect(finder.execute).to be_nil
      end
    end

    context 'when scoped to a parent' do
      let(:params) { { search: 'test', parent: parent_group } }

      it 'returns descendants and excludes the parent itself' do
        expect(finder.execute).to contain_exactly(subgroup)
      end

      it 'routes the query to the shard holding the hierarchy' do
        expect(::Gitlab::Search::Client).to receive(:execute_search)
          .with(query: anything, options: hash_including(root_ancestor_ids: [parent_group.id]))
          .and_call_original

        finder.execute
      end
    end

    context 'when nothing matches' do
      let(:params) { { search: 'no-such-group-anywhere' } }

      it 'returns an empty relation rather than every group' do
        expect(finder.execute).to be_empty
        expect(finder.execute).to be_a(ActiveRecord::Relation)
      end
    end

    context 'with a private group the user cannot see' do
      let_it_be(:private_group) { create(:group, :private, name: 'test-private') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_group)
        ensure_elasticsearch_index!
      end

      it 'does not return it' do
        expect(finder.execute).not_to include(private_group)
      end

      context 'when the user is a member' do
        before_all do
          private_group.add_developer(user)
        end

        it 'returns it' do
          expect(finder.execute).to include(private_group)
        end
      end
    end

    # Group.search reads the routes table when no parent is given, so a term that only
    # hits an ancestor's name still returns the descendant on PostgreSQL.
    context 'when the term only matches an ancestor name' do
      let_it_be(:unrelated_child) { create(:group, :public, parent: parent_group, name: 'unrelated') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(unrelated_child)
        ensure_elasticsearch_index!
      end

      it 'returns the descendant, matching GroupsFinder' do
        params = { search: 'test' }

        expect(described_class.new(user, params).execute)
          .to match_array(GroupsFinder.new(user, params).execute)
        expect(described_class.new(user, params).execute).to include(unrelated_child)
      end

      context 'when a parent is given' do
        it 'stops matching the route, matching GroupsFinder' do
          params = { search: 'test', parent: parent_group }

          expect(described_class.new(user, params).execute)
            .to match_array(GroupsFinder.new(user, params).execute)
          expect(described_class.new(user, params).execute).not_to include(unrelated_child)
        end
      end
    end

    # GroupsFinder authorizes through `authorized_groups.self_and_ancestors`, so
    # membership on a subgroup also reveals its private parents.
    context 'with membership on a private subgroup only' do
      let_it_be(:private_parent) { create(:group, :private, name: 'test-private-parent') }
      let_it_be(:private_child) { create(:group, :private, parent: private_parent, name: 'test-private-child') }

      before_all do
        private_child.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_parent, private_child)
        ensure_elasticsearch_index!
      end

      it 'returns the private ancestor too, matching GroupsFinder' do
        expect(finder.execute).to include(private_parent, private_child)
        expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
      end

      context 'when the user is not a member' do
        let_it_be(:other_user) { create(:user) }

        it 'returns neither' do
          expect(described_class.new(other_user, params).execute)
            .not_to include(private_parent, private_child)
        end
      end
    end

    # `authorized_groups` also covers groups reached only through project membership.
    context 'with access derived from a project membership' do
      let_it_be(:private_parent) { create(:group, :private, name: 'test-project-parent') }
      let_it_be(:private_child) { create(:group, :private, parent: private_parent, name: 'test-project-child') }
      let_it_be(:project) { create(:project, :private, group: private_child) }

      before_all do
        project.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_parent, private_child)
        ensure_elasticsearch_index!
      end

      it 'returns the group hierarchy above the project, matching GroupsFinder' do
        expect(finder.execute).to include(private_parent, private_child)
        expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
      end
    end

    context 'when Elasticsearch fails' do
      it 'falls back rather than raising on an error response' do
        allow(::Gitlab::Search::Client).to receive(:execute_search).and_yield({ 'error' => { 'type' => 'timeout' } })

        expect(finder.execute).to be_nil
      end

      it 'falls back rather than raising on a transport error' do
        allow(::Gitlab::Search::Client).to receive(:execute_search)
          .and_raise(::Elasticsearch::Transport::Transport::Errors::GatewayTimeout)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        expect(finder.execute).to be_nil
      end
    end
  end
end
