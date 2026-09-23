# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'IP-restricted snippet notes are not exposed by the search routes',
  feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:root_group) { create(:group, developers: user) }
  let_it_be(:project) { create(:project, :private, group: root_group) }

  # `let_it_be_with_reload` (reload: true, freeze: false) is required: creating a
  # Note calls `.touch` on an already-loaded noteable, which raises FrozenError
  # against this project's `default_modifiers[:freeze] = true`. `reload: true`
  # alone does not clear the freeze.
  let_it_be_with_reload(:snippet) do
    create(:project_snippet, :private, project: project, author: user)
  end

  let_it_be(:snippet_note) { create(:note, project: project, noteable: snippet, author: user) }

  before do
    stub_licensed_features(group_ip_restriction: true)
    create(:ip_restriction, group: root_group, range: '192.168.0.0/24')
  end

  context 'when the caller IP is outside the allowed range' do
    before do
      allow(::Gitlab::IpAddressState).to receive(:current).and_return('10.0.0.1')
    end

    it 'denies :read_note on the snippet note, which is what backstops the Elasticsearch route' do
      expect(Ability.allowed?(user, :read_note, snippet_note)).to be(false)
    end

    it 'denies :read_project, so a project-scoped notes search is unreachable' do
      # Basic notes search is only offered at project level (lib/search/scopes.rb:87-95),
      # so an out-of-range user cannot reach it at all.
      expect(Ability.allowed?(user, :read_project, project)).to be(false)
    end

    it 'resolves SearchService#project to nil and falls back to global level', :aggregate_failures do
      service = SearchService.new(user, project_id: project.id, scope: 'notes', search: 'anything')

      expect(service.project).to be_nil
      expect(service.level).to eq('global')
    end

    it 'redacts the snippet note out of search results' do
      service = SearchService.new(user, project_id: project.id, scope: 'notes', search: snippet_note.note)

      # Kaminari-paginated rather than a bare Array: that is the shape the
      # Elasticsearch route returns, and the branch of
      # redact_unauthorized_results it exercises (app/services/search_service.rb:176-181).
      allow(service).to receive(:search_results).and_return(
        instance_double(
          Gitlab::ProjectSearchResults,
          objects: Kaminari.paginate_array([snippet_note]).page(1).per(20)
        )
      )

      expect(service.search_objects).not_to include(snippet_note)
    end
  end

  context 'when the caller IP is inside the allowed range' do
    before do
      allow(::Gitlab::IpAddressState).to receive(:current).and_return('192.168.0.2')
    end

    it 'allows :read_note on the snippet note' do
      expect(Ability.allowed?(user, :read_note, snippet_note)).to be(true)
    end
  end

  # Snippet.allowed_for_ip joins through Project#group (the DIRECT namespace),
  # while Gitlab::IpRestriction::Enforcer resolves the ROOT ancestor -- so the
  # scope is the weaker guard. The subgroup divergence, its fix and its coverage
  # live in https://gitlab.com/gitlab-org/gitlab/-/merge_requests/254363, and
  # asserting it here would couple the two merge orders.
  describe 'Snippet.allowed_for_ip vs Gitlab::IpRestriction::Enforcer' do
    before do
      allow(::Gitlab::IpAddressState).to receive(:current).and_return('10.0.0.1')
    end

    it 'drops a snippet whose project hangs directly off the restricted group' do
      expect(::Snippet.allowed_for_ip('10.0.0.1')).not_to include(snippet)
    end
  end

  # Accepted, not fixed: a Planner holds :read_confidential_issues, but the
  # Elasticsearch filter pins a minimum access level of REPORTER, so the routed
  # path is strictly more restrictive for Planners. See the MR description.
  describe 'accepted divergence: Planner loses confidential-note visibility on the Elasticsearch route' do
    let_it_be(:planner) { create(:user) }

    before_all do
      project.add_planner(planner)
    end

    it 'grants a Planner :read_confidential_issues, which is what the Postgres path honours' do
      expect(::Authz::Role.get(:planner).permissions(:project)).to include(:read_confidential_issues)
    end

    it 'pins the Elasticsearch note filter to REPORTER, an access level a Planner does not reach',
      :aggregate_failures do
      # Read back through production code (ProjectTeam#max_member_access) rather
      # than comparing the constants, which would hold even if no role resolved
      # to PLANNER.
      expect(::Project.find(project.id).team.max_member_access(planner.id))
        .to be < ::Gitlab::Access::REPORTER

      # ee/lib/elastic/latest/note_class_proxy.rb:74-76
      proxy = ::Elastic::Latest::NoteClassProxy.new(::Note, use_separate_indices: true)

      expect(::Search::Elastic::Filters).to receive(:by_note_confidentiality).with(
        query_hash: {},
        options: hash_including(
          min_access_level_confidential: ::Gitlab::Access::REPORTER,
          min_access_level_confidential_public_internal: ::Gitlab::Access::REPORTER
        )
      )

      proxy.send(:confidentiality_filter, {}, { current_user: user })
    end
  end
end
