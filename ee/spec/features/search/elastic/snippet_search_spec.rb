# frozen_string_literal: true

require 'spec_helper'

# This file deliberately keeps ONE browser example.
#
# It used to run a full 12-example snippet visibility matrix (anonymous /
# regular / authorized / admin-with-and-without-admin-mode, across two search
# fields), each example paying a Capybara page load on top of a shared
# Elasticsearch index build. That matrix is authorization logic, and it is
# asserted without a browser -- with the gaps named below:
#
#   * ee/spec/services/ee/search/snippet_service_spec.rb drives
#     `permission_table_for_project_snippet_access` (public/internal/private
#     snippet x project visibility x feature access level x membership x admin
#     mode) and `permission_table_for_personal_snippet_access` through
#     Elasticsearch. Both are :elastic_delete_by_query, so they exercise the
#     same indexed-search path this file did. Two classes of row assert
#     nothing, though:
#       - eight project-snippet rows are listed in `pendings` -- the
#         non-member and admin-without-admin-mode cells for a public/internal
#         snippet in a public/internal project with snippets enabled,
#         including the exact row this file's discriminator relies on (public
#         snippet, public project, non-member);
#       - every `:anonymous` row passes vacuously, because
#         `user_from_membership(:anonymous)` returns nil and
#         `expect_search_results` starts with `users = Array(users)`, so the
#         `users.each` body never runs.
#   * spec/services/search/snippet_service_spec.rb asserts the same *personal*
#     snippet visibility outcomes against the Postgres path, in its
#     'unauthenticated' and 'authenticated' contexts. Project snippets differ
#     between the two engines -- see the fixture note below.
#   * ee/spec/lib/search/elastic/snippet_search_results_spec.rb ('when user is
#     nil') covers the anonymous case on the Elasticsearch path for *personal*
#     snippets only: a private one returns nothing and a public one is found.
#
# So the deleted examples did assert cells the specs above do not, and the
# residue is worth naming: after this change the anonymous/internal and
# anonymous/project-snippet cells have no direct Elasticsearch-path
# assertion, and the pending and vacuous rows above remain a pre-existing gap
# in those tables.
#
# The anonymous-user redirect that this file also covered is asserted in
# spec/controllers/search_controller_spec.rb (redirects to
# new_user_session_path when global_search_block_anonymous_searches_enabled).
#
# The description-matching branch this file also touched --
# Elastic::Latest::SnippetClassProxy#elastic_search searches
# basic_query_hash(%w[title description], query) -- is covered by
# ee/spec/models/concerns/elastic/snippet_spec.rb, which asserts a
# description-only match is found.
#
# What none of those cover is that the snippet search *page* renders indexed
# results at all -- the wiring from the explore snippets page through the
# search UI to Elasticsearch. That is what remains here, and the fixtures are
# chosen so the example fails if that wiring silently falls back to basic
# search: a public project snippet in a project the user is not a member of is
# returned by the Postgres path (spec/services/search/snippet_service_spec.rb,
# 'authenticated') but excluded by the Elasticsearch path, which matches
# project snippets only in the user's authorized projects
# (Elastic::Latest::SnippetClassProxy#filter_project_snippets). That exclusion
# is the known limitation recorded as the eight pending rows above. If it is
# ever lifted, the discriminator stops discriminating: replace it with another
# engine-divergent fixture rather than flipping the assertion, or this example
# silently stops detecting a fallback to basic search. The member project
# snippet keeps render-level coverage of the project branch of
# app/views/search/results/_snippet_title.html.haml.
RSpec.describe 'Snippet elastic search', :js, :elastic_delete_by_query, :aggregate_failures,
  :with_current_organization, feature_category: :global_search do
  let_it_be(:regular_user) { create(:user) }
  let_it_be(:non_member_project) { create(:project, :public) }
  let_it_be(:member_project) { create(:project, :private, maintainers: regular_user) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)

    Sidekiq::Testing.inline! do
      create(:personal_snippet, :public, title: 'public personal snippet',
        description: 'a public personal snippet description')
      create(:personal_snippet, :private, title: 'private personal snippet',
        description: 'a private personal snippet description')
      create(:project_snippet, :public, project: non_member_project,
        title: 'non-member project snippet', description: 'a non-member project snippet description')
      create(:project_snippet, :private, project: member_project,
        title: 'member project snippet', description: 'a member project snippet description')

      ensure_elasticsearch_index!
    end

    sign_in(regular_user)
    visit explore_snippets_path
  end

  it 'renders indexed results through the Elasticsearch path' do
    submit_search('snippet')

    within('.results') do
      expect(page).to have_content('public personal snippet')
      expect(page).not_to have_content('private personal snippet')

      # Only the Elasticsearch path excludes a public project snippet in a
      # project the user is not a member of; basic search returns it.
      expect(page).to have_content('member project snippet')
      expect(page).not_to have_content('non-member project snippet')
    end
  end
end
