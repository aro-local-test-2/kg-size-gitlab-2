# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Search, :clean_gitlab_redis_rate_limiting, factory_default: :keep, feature_category: :global_search do
  include ProjectForksHelper

  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be(:group) { create(:group) }
  let_it_be(:label) { create(:label, group: group) }
  let_it_be(:project, freeze: false) do
    create(:project, :public, :repository, :wiki_repo, name: 'awesome project', group: group)
  end

  let_it_be(:forked_project) { fork_project(project, nil, repository: true) }
  let_it_be(:milestone) { create(:milestone, project: project) }
  let_it_be(:token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  shared_examples 'response is correct' do |schema:, size: 1|
    it 'responds correctly' do
      expect(response).to have_gitlab_http_status(:ok)
      expect(response).to match_response_schema(schema)
      expect(response).to include_limited_pagination_headers
      expect(json_response.size).to eq(size)
    end
  end

  shared_examples 'support for elasticsearch timeouts' do
    it 'returns 408 and reports the timeout' do
      allow_next_instance_of(SearchService) do |service|
        allow(service).to receive(:search_objects).and_raise(::Elastic::TimeoutError)
      end

      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(::Elastic::TimeoutError))

      get api(endpoint, user), params: { scope: 'issues', search: 'awesome' }

      expect(response).to have_gitlab_http_status(:request_timeout)
      expect(json_response['message']).to eq('Request timed out')
    end
  end

  shared_examples 'pagination' do |scope:, search: '*'|
    it 'returns a different result for each page' do
      get api(endpoint, user), params: { scope: scope, search: search, page: 1, per_page: 1 }
      expect(response).to have_gitlab_http_status(:success)
      expect(json_response.count).to eq(1)

      first = json_response.first

      get api(endpoint, user), params: { scope: scope, search: search, page: 2, per_page: 1 }
      second = Gitlab::Json.parse(response.body).first

      expect(first).not_to eq(second)

      get api(endpoint, user), params: { scope: scope, search: search, per_page: 2 }

      expect(Gitlab::Json.parse(response.body).count).to eq(2)
    end
  end

  shared_examples 'orderable by created_at' do |scope:|
    it 'allows ordering results by created_at asc' do
      get api(endpoint, user), params: { scope: scope, search: '*', order_by: 'created_at', sort: 'asc' }

      expect(response).to have_gitlab_http_status(:success)
      expect(json_response.count).to be > 1

      created_ats = json_response.map { |r| Time.parse(r['created_at']) }

      expect(created_ats).to eq(created_ats.sort)
    end

    it 'allows ordering results by created_at desc' do
      get api(endpoint, user), params: { scope: scope, search: '*', order_by: 'created_at', sort: 'desc' }

      expect(response).to have_gitlab_http_status(:success)
      expect(json_response.count).to be > 1

      created_ats = json_response.map { |r| Time.parse(r['created_at']) }

      expect(created_ats).to eq(created_ats.sort.reverse)
    end
  end

  shared_examples 'elasticsearch disabled' do
    it 'returns 400 error for wiki_blobs, blobs and commits scope' do
      get api(endpoint, user), params: { scope: 'wiki_blobs', search: 'awesome' }

      expect(response).to have_gitlab_http_status(:bad_request)

      get api(endpoint, user), params: { scope: 'blobs', search: 'monitors' }

      expect(response).to have_gitlab_http_status(:bad_request)

      get api(endpoint, user), params: { scope: 'commits', search: 'folder' }

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'returns bad_request when fields param is passed' do
      get api(endpoint, user), params: { scope: 'issues', search: 'awesome', fields: ['title'] }

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'returns bad_request when num_context_lines param is passed' do
      get api(endpoint, user), params: { scope: 'issues', search: 'awesome', num_context_lines: 3 }

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it_behaves_like 'merge request filters are rejected'
  end

  shared_examples 'merge request filters are rejected' do
    let(:base_mr_params) { { scope: 'merge_requests', search: 'awesome' } }

    {
      'source_branch' => { source_branch: 'x' },
      'target_branch' => { target_branch: 'x' },
      'author_username' => { author_username: 'x' },
      'label_name' => { label_name: ['x'] },
      'not[source_branch]' => { not: { source_branch: 'x' } },
      'not[target_branch]' => { not: { target_branch: 'x' } },
      'not[author_username]' => { not: { author_username: 'x' } }
    }.each do |expected_name, filter_params|
      it "returns bad_request naming #{expected_name} as the client sent it" do
        get api(endpoint, user), params: base_mr_params.merge(filter_params)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to eq("#{expected_name} is supported only for advanced search")
      end
    end

    it 'returns bad_request for a merge request filter on another scope' do
      get api(endpoint, user), params: { scope: 'issues', search: 'awesome', source_branch: 'x' }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('source_branch is supported only for merge_requests')
    end

    it 'names every offending filter in one response' do
      get api(endpoint, user),
        params: { scope: 'issues', search: 'awesome', source_branch: 'x', target_branch: 'y' }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('source_branch, target_branch is supported only for merge_requests')
    end

    it 'rejects an undeclared not sub-key rather than dropping it' do
      get api(endpoint, user), params: {
        scope: 'issues', search: 'awesome',
        not: { label_names: ['x'], milestone_title: 'y' }
      }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to eq('not[label_names], not[milestone_title] is not a supported filter')
    end

    it 'copies no undeclared negated sub-key out of the not hash' do
      copied = nil
      allow(SearchService).to receive(:new).and_wrap_original do |original, *args|
        copied = args.last[:not]
        original.call(*args)
      end

      get api(endpoint, user), params: { scope: 'issues', search: 'awesome' }

      expect(response).to have_gitlab_http_status(:ok)
      expect(copied).to be_nil
    end

    context 'for mcp request' do
      it 'returns ok when fields param is passed' do
        get api(endpoint, oauth_access_token: token), params: { scope: 'issues', search: 'foo', fields: ['title'] }

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'returns bad_request when a merge request filter is passed to basic search, unlike fields' do
        get api(endpoint, oauth_access_token: token), params: base_mr_params.merge(source_branch: 'x')

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to eq('source_branch is supported only for advanced search')
      end

      it 'returns bad_request when a merge request filter is passed with an unsupported scope' do
        get api(endpoint, oauth_access_token: token),
          params: { scope: 'milestones', search: 'foo', author_username: 'x' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message'])
          .to eq('author_username is supported only for issues, merge_requests, work_items')
      end

      it 'returns ok when num_context_lines param is passed' do
        get api(endpoint, oauth_access_token: token), params: { scope: 'issues', search: 'foo', num_context_lines: 3 }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  shared_examples 'elasticsearch enabled' do |level:|
    before do
      ::Elastic::ProcessInitialBookkeepingService.backfill_projects!(project)

      ensure_elasticsearch_index!
    end

    context 'for merge_requests scope' do
      before_all do
        create_list(:merge_request, 3, :unique_branches, source_project: project, author: user, labels: [label])
      end

      it_behaves_like 'pagination', scope: 'merge_requests'
      it_behaves_like 'orderable by created_at', scope: 'merge_requests'

      it 'avoids N+1 queries' do
        control = ActiveRecord::QueryRecorder.new do
          get api(endpoint, user), params: { scope: 'merge_requests', search: '*' }
        end
        create_list(:merge_request, 3, :unique_branches, source_project: project, author: user, labels: [label])
        ensure_elasticsearch_index!

        expect do
          get api(endpoint, user), params: { scope: 'merge_requests', search: '*' }
          # Threshold required for specs to pass, see: https://gitlab.com/gitlab-org/gitlab/-/work_items/587748.
        end.not_to exceed_query_limit(control).with_threshold(3)
      end

      it 'returns ok response with fields param' do
        get api(endpoint, user), params: { scope: 'merge_requests', search: 'title', fields: ['title'] }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.size).to eq 3
      end

      describe 'merge request filters' do
        # A fixture merge request visible to sibling examples changes their
        # expected sizes and their N+1 controls.
        let_it_be(:other_author) { create(:user, developer_of: group) }
        # `LabelsFinder` only sees labels reachable from the searched group.
        let_it_be(:other_label) { create(:group_label, group: group, title: 'mr-filter-label') }
        let_it_be(:second_label) { create(:group_label, group: group, title: 'mr-filter-label-2') }
        let_it_be(:unapplied_label) { create(:group_label, group: group, title: 'mr-filter-label-absent') }
        let_it_be(:filtered_merge_request) do
          create(:merge_request, source_project: project, author: other_author,
            labels: [other_label, second_label],
            source_branch: 'mr-filter-source', target_branch: 'mr-filter-target')
        end

        let(:all_ids) { search({}) }

        # An unregistered parameter is dropped silently and still answers 200.
        def search(params)
          get api(endpoint, user), params: { scope: 'merge_requests', search: '*' }.merge(params)

          expect(response).to have_gitlab_http_status(:ok)
          json_response.map { |mr| mr['id'] }
        end

        it 'filters by source_branch and its negation' do
          expect(all_ids).to include(filtered_merge_request.id)

          expect(search(source_branch: 'mr-filter-source')).to contain_exactly(filtered_merge_request.id)
          expect(search(not: { source_branch: 'mr-filter-source' }))
            .to match_array(all_ids - [filtered_merge_request.id])
        end

        it 'filters by target_branch and its negation' do
          expect(search(target_branch: 'mr-filter-target')).to contain_exactly(filtered_merge_request.id)
          expect(search(not: { target_branch: 'mr-filter-target' }))
            .to match_array(all_ids - [filtered_merge_request.id])
        end

        it 'filters by author_username and its negation' do
          expect(search(author_username: other_author.username)).to contain_exactly(filtered_merge_request.id)
          expect(search(not: { author_username: other_author.username }))
            .to match_array(all_ids - [filtered_merge_request.id])
        end

        it 'filters by label_name' do
          expect(search(label_name: [other_label.title])).to contain_exactly(filtered_merge_request.id)
        end

        it 'accepts label_name as a comma-separated string' do
          expect(search(label_name: "#{other_label.title},#{second_label.title}"))
            .to contain_exactly(filtered_merge_request.id)
        end

        it 'requires every label_name given' do
          expect(search(label_name: [other_label.title, second_label.title]))
            .to contain_exactly(filtered_merge_request.id)
          expect(search(label_name: [other_label.title, unapplied_label.title])).to be_empty
        end

        # `minimum_should_match: 1`, so an AND implementation fails here.
        it 'combines a branch filter with its negation as an OR' do
          expect(search(source_branch: 'mr-filter-source', not: { source_branch: 'no-such-branch' }))
            .to match_array(all_ids)
          expect(search(target_branch: 'mr-filter-target', not: { target_branch: 'no-such-branch' }))
            .to match_array(all_ids)
        end

        it 'serves an unresolved author_username unfiltered, applying only the negation' do
          expect(search(author_username: 'no-such-user')).to match_array(all_ids)

          expect(search(author_username: 'no-such-user', not: { author_username: other_author.username }))
            .to match_array(all_ids - [filtered_merge_request.id])
        end

        it 'serves unresolved label names unfiltered and applies only resolved ones' do
          expect(search(label_name: ['no-such-label'])).to match_array(all_ids)

          expect(search(label_name: [other_label.title, 'no-such-label']))
            .to contain_exactly(filtered_merge_request.id)
        end

        it 'counts the filtered result set in X-Total' do
          get api(endpoint, user), params: { scope: 'merge_requests', search: '*' }
          unfiltered_total = response.headers['X-Total'].to_i

          get api(endpoint, user),
            params: { scope: 'merge_requests', search: '*', source_branch: 'mr-filter-source' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.headers['X-Total'].to_i).to eq(1)
          expect(unfiltered_total).to be > 1
        end

        it 'rejects an undeclared not sub-key' do
          get api(endpoint, user),
            params: { scope: 'merge_requests', search: '*', not: { milestone_title: 'no-such-milestone' } }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('not[milestone_title] is not a supported filter')
        end
      end
    end

    context 'for wiki_blobs scope', :sidekiq_inline do
      before do
        wiki = create(:project_wiki, project: project)
        create(:wiki_page, wiki: wiki, title: 'home', content: "Awesome page")
        create(:wiki_page, wiki: wiki, title: 'other', content: "Another page")

        project.wiki.index_wiki_blobs
        ensure_elasticsearch_index!
      end

      it_behaves_like 'response is correct', schema: 'public_api/v4/wiki_blobs' do
        before do
          get api(endpoint, user), params: { scope: 'wiki_blobs', search: 'awesome' }
        end
      end

      it_behaves_like 'pagination', scope: 'wiki_blobs'
    end

    context 'for commits and blobs', :sidekiq_inline do
      before do
        project.repository.index_commits_and_blobs
        ensure_elasticsearch_index!
      end

      context 'for commits scope' do
        it_behaves_like 'response is correct', schema: 'public_api/v4/commits_details', size: 2 do
          before do
            get api(endpoint, user), params: { scope: 'commits', search: 'folder' }
          end
        end

        it_behaves_like 'pagination', scope: 'commits'

        it 'avoids N+1 queries' do
          project_2 = create(:project, :public, :repository, group: group)
          project_2.repository.index_commits_and_blobs
          ensure_elasticsearch_index!

          api_endpoint = level == :project ? "/projects/#{project_2.id}/-/search" : endpoint

          control = ActiveRecord::QueryRecorder.new do
            get api(api_endpoint, user), params: { scope: 'commits', search: 'folder' }
          end

          initial_count = json_response.count

          3.times do |i|
            commit_sha = project_2.repository.create_file(user, i.to_s, "folder #{i}",
              message: "committing folder #{i}", branch_name: 'master')
            project_2.repository.commit(commit_sha)
          end

          project_2.repository.index_commits_and_blobs
          ensure_elasticsearch_index!

          expect do
            get api(api_endpoint, user), params: { scope: 'commits', search: 'folder' }
          end.not_to exceed_query_limit(control)
          expect(json_response.count).to eq(initial_count + 3)
        end
      end

      context 'for blobs scope' do
        it_behaves_like 'response is correct', schema: 'public_api/v4/blobs' do
          before do
            get api(endpoint, user), params: { scope: 'blobs', search: 'folder' }
          end
        end

        it_behaves_like 'pagination', scope: 'blobs'

        it 'returns ok response with num_context_lines param for advanced search' do
          api_endpoint = level == :project ? "/projects/#{project.id}/-/search" : endpoint
          get api(api_endpoint, user), params: { scope: 'blobs', search: 'folder', num_context_lines: 3 }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'avoids N+1 queries' do
          project_2 = create(:project, :public, :repository, group: group)
          project_2.repository.index_commits_and_blobs
          ensure_elasticsearch_index!

          api_endpoint = level == :project ? "/projects/#{project_2.id}/-/search" : endpoint

          control = ActiveRecord::QueryRecorder.new do
            get api(api_endpoint, user), params: { scope: 'blobs', search: 'Issue team' }
          end

          initial_count = json_response.count

          3.times do |i|
            commit_sha = project_2.repository.create_file(user, i.to_s, "Issue team #{i}", message: i.to_s,
              branch_name: 'master')
            project_2.repository.commit(commit_sha)
          end

          project_2.repository.index_commits_and_blobs
          ensure_elasticsearch_index!

          expect do
            get api(api_endpoint, user), params: { scope: 'blobs', search: 'Issue team' }
          end.not_to exceed_query_limit(control)
          expect(json_response.count).to eq(initial_count + 3)
        end

        context 'with filters' do
          def results_filenames
            json_response.filter_map { |h| h['filename'] }
          end

          def results_paths
            json_response.filter_map { |h| h['path'] }
          end

          context 'with an including filter' do
            it 'by filename' do
              get api("/projects/#{project.id}/search", user),
                params: { scope: 'blobs', search: 'mon* filename:PROCESS.md' }

              expect(response).to have_gitlab_http_status(:ok)
              expect(json_response.size).to eq(1)
              expect(results_filenames).to all(match(%r{PROCESS.md$}))
            end

            it 'by path' do
              get api("/projects/#{project.id}/search", user), params: { scope: 'blobs', search: 'mon* path:markdown' }

              expect(response).to have_gitlab_http_status(:ok)
              expect(json_response.size).to eq(1)
              expect(results_paths).to all(match(%r{^files/markdown/}))
            end

            it 'by extension' do
              get api("/projects/#{project.id}/search", user), params: { scope: 'blobs', search: 'mon* extension:md' }

              expect(response).to have_gitlab_http_status(:ok)
              expect(json_response.size).to eq(3)
              expect(results_filenames).to all(match(%r{.*.md$}))
            end
          end

          context 'with an excluding filter' do
            it 'by filename' do
              get api(endpoint, user), params: { scope: 'blobs', search: '* -filename:PROCESS.md' }

              expect(response).to have_gitlab_http_status(:ok)
              expect(results_filenames).not_to include('PROCESS.md')
              expect(json_response.size).to eq(20)
            end

            it 'by path' do
              get api(endpoint, user), params: { scope: 'blobs', search: '* -path:files/markdown' }

              expect(response).to have_gitlab_http_status(:ok)
              expect(results_paths).not_to include(a_string_matching(%r{^files/markdown/}))
              expect(json_response.size).to eq(20)
            end

            it 'by extension' do
              get api(endpoint, user), params: { scope: 'blobs', search: '* -extension:md' }

              expect(response).to have_gitlab_http_status(:ok)

              expect(results_filenames).not_to include(a_string_matching(%r{.*.md$}))
              expect(json_response.size).to eq(20)
            end
          end
        end

        context 'for mcp request' do
          it 'returns ok response with regex param' do
            get api(endpoint, oauth_access_token: token), params: { scope: 'blobs', search: 'test', regex: true }

            expect(response).to have_gitlab_http_status(:ok)
          end

          it 'returns ok response with exclude_forks param' do
            params = { scope: 'blobs', search: 'aa', exclude_forks: true }
            get api(endpoint, oauth_access_token: token), params: params

            expect(response).to have_gitlab_http_status(:ok)
          end

          it 'returns ok response with num_context_lines param' do
            get api(endpoint, oauth_access_token: token),
              params: { scope: 'blobs', search: 'monitors', num_context_lines: 3 }

            expect(response).to have_gitlab_http_status(:ok)
          end
        end

        it 'returns bad request with regex param' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'test', regex: true }

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns bad request with exclude_forks param' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'aa', exclude_forks: true }

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns ok response with num_context_lines param for advanced search' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'monitors', num_context_lines: 3 }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'returns bad request with out-of-range num_context_lines param' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'monitors', num_context_lines: -1 }

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns bad request with num_context_lines param exceeding maximum' do
          get api(endpoint, user),
            params: { scope: 'blobs', search: 'monitors',
                      num_context_lines: ::Gitlab::Elastic::SearchResults::MAX_NUM_CONTEXT_LINES + 1 }

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end

    context 'for issues scope' do
      before_all do
        create_list(:issue, 2, project: project)
      end

      it 'avoids N+1 queries', :use_sql_query_cache do
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          get api(endpoint, user), params: { scope: 'issues', search: '*' }
        end

        create_list(:issue, 2, project: project)
        create_list(:issue, 2, project: create(:project, group: group))
        create_list(:issue, 2)

        ensure_elasticsearch_index!

        expect do
          get api(endpoint, user), params: { scope: 'issues', search: '*' }
        end.not_to exceed_query_limit(control).allow_skip_cache_inconsistency
      end

      it 'returns ok response with fields param' do
        get api(endpoint, user), params: { scope: 'issues', search: 'title', fields: ['title'] }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.size).to eq 2
      end

      it_behaves_like 'pagination', scope: 'issues'
      it_behaves_like 'orderable by created_at', scope: 'issues'

      describe 'filters shared with the merge_requests scope' do
        let_it_be(:issue_author) { create(:user, developer_of: group) }
        let_it_be(:issue_label) { create(:group_label, group: group, title: 'issue-filter-label') }
        let_it_be(:filtered_issue) do
          create(:issue, project: project, author: issue_author, labels: [issue_label])
        end

        def search(params)
          get api(endpoint, user), params: { scope: 'issues', search: '*' }.merge(params)

          expect(response).to have_gitlab_http_status(:ok)
          json_response.map { |issue| issue['id'] }
        end

        it 'filters by author_username and its negation' do
          expect(search(author_username: issue_author.username)).to contain_exactly(filtered_issue.id)
          expect(search(not: { author_username: issue_author.username })).not_to include(filtered_issue.id)
        end

        it 'filters by label_name' do
          expect(search(label_name: [issue_label.title])).to contain_exactly(filtered_issue.id)
        end

        it 'still rejects a branch filter this scope cannot honour' do
          get api(endpoint, user), params: { scope: 'issues', search: '*', source_branch: 'x' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('source_branch is supported only for merge_requests')
        end
      end
    end

    unless level == :project
      context 'for projects scope', :sidekiq_inline do
        before do
          create(:project, :public, name: 'second project', group: group)

          ensure_elasticsearch_index!
        end

        it_behaves_like 'pagination', scope: 'projects'

        it 'avoids N+1 queries', :use_sql_query_cache do
          control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
            get api(endpoint, user), params: { scope: 'projects', search: '*' }
          end

          create_list(:project, 3, :public, group: group)
          create_list(:project, 4, :public)

          ensure_elasticsearch_index!

          expect do
            get api(endpoint, user), params: { scope: 'projects', search: '*' }
          end.not_to exceed_query_limit(control).allow_skip_cache_inconsistency
        end
      end
    end

    context 'for milestones scope' do
      before_all do
        create_list(:milestone, 2, project: project)
      end

      it_behaves_like 'pagination', scope: 'milestones'

      it 'avoids N+1 queries' do
        control = ActiveRecord::QueryRecorder.new do
          get api(endpoint, user), params: { scope: 'milestones', search: '*' }
        end
        create_list(:milestone, 3, project: project)
        create_list(:milestone, 2, project: create(:project, :public))

        ensure_elasticsearch_index!

        expect do
          get api(endpoint, user), params: { scope: 'milestones', search: '*' }
        end.not_to exceed_query_limit(control)
      end
    end

    context 'for users scope' do
      before do
        create_list(:user, 2).each_with_index do |user, index|
          user.update!(name: "foo_#{index}")
          project.add_developer(user)
        end

        ensure_elasticsearch_index!
      end

      it_behaves_like 'pagination', scope: 'users', search: 'foo_'

      it 'avoids N+1 queries' do
        control = ActiveRecord::QueryRecorder.new { get api(endpoint, user), params: { scope: 'users', search: '*' } }
        create_list(:user, 2).each do |user|
          project.add_developer(user)
        end

        ensure_elasticsearch_index!

        # Threshold required: pre-existing N+1 loading user + user_status for newly added users,
        # exposed by moving elasticsearch_indexed_namespace setup to before_all.
        expect { get api(endpoint, user), params: { scope: 'users', search: '*' } }
          .not_to exceed_query_limit(control).with_threshold(2)
      end
    end

    context 'for notes scope' do
      before do
        create(:note_on_merge_request, project: project, note: 'awesome note')
        mr = create(:merge_request, source_project: project, target_branch: 'another_branch')
        create(:note, project: project, noteable: mr, note: 'another note')

        ensure_elasticsearch_index!
      end

      it_behaves_like 'pagination', scope: 'notes'
    end

    if level == :global
      context 'for snippet_titles scope' do
        before do
          create_list(:personal_snippet, 2, :public, title: 'Some code', content: 'Check it out')

          ensure_elasticsearch_index!
        end

        it_behaves_like 'pagination', scope: 'snippet_titles'
      end
    end
  end

  shared_examples 'exact code search enabled' do |level:|
    before_all do
      zoekt_ensure_project_indexed!(project)
      zoekt_ensure_project_indexed!(forked_project)
    end

    it_behaves_like 'response is correct', schema: 'public_api/v4/blobs', size: 20 do
      before do
        get api(endpoint, user), params: { scope: 'blobs', search: 'Issue' }
      end
    end

    describe 'blobs scope' do
      let(:api_endpoint) do
        case level
        when :project
          "/projects/#{project.id}/-/search"
        when :group
          "/groups/#{group.id}/-/search"
        else
          endpoint
        end
      end

      context 'with filters' do
        context 'for exclude_forks' do
          let(:project) { forked_project }
          let(:group) { forked_project.namespace }

          it 'excludes forks by default' do
            get api(api_endpoint, user), params: { scope: 'blobs', search: 'monitors' }
            expect(response).to have_gitlab_http_status(:success)

            project_ids_in_response = json_response.pluck('project_id').uniq
            if level == :project
              expect(project_ids_in_response).to include(forked_project.id)
            else
              expect(project_ids_in_response).not_to include(forked_project.id)
            end
          end

          context 'when exclude_forks is true' do
            it 'excludes forks' do
              get api(api_endpoint, user), params: { scope: 'blobs', search: 'monitors', exclude_forks: true }
              expect(response).to have_gitlab_http_status(:success)

              project_ids_in_response = json_response.pluck('project_id').uniq
              if level == :project
                expect(project_ids_in_response).to include(forked_project.id)
              else
                expect(project_ids_in_response).not_to include(forked_project.id)
              end
            end
          end

          context 'when exclude_forks is false' do
            it 'includes forks' do
              get api(api_endpoint, user), params: { scope: 'blobs', search: 'monitors', exclude_forks: false }

              expect(response).to have_gitlab_http_status(:success)

              project_ids_in_response = json_response.pluck('project_id').uniq
              expect(project_ids_in_response).to include(forked_project.id)
            end
          end
        end
      end

      context 'for regex search' do
        it 'performs regex search by default' do
          get api(api_endpoint, user), params: { scope: 'blobs', search: 'path_.*ex' }

          expect(response).to have_gitlab_http_status(:success)
          expect(json_response.pluck('project_id').uniq).to include(project.id)
        end

        context 'when regex is passed as false' do
          it 'does not perform regex search' do
            get api(api_endpoint, user), params: { scope: 'blobs', search: 'path_.*ex', regex: false }

            expect(response).to have_gitlab_http_status(:success)
            expect(json_response).to be_empty
          end
        end

        context 'when regex is passed as true' do
          it 'performs regex search' do
            get api(api_endpoint, user), params: { scope: 'blobs', search: 'path_.*ex', regex: true }

            expect(response).to have_gitlab_http_status(:success)
            expect(json_response.pluck('project_id').uniq).to include(project.id)
          end
        end
      end

      context 'for mcp request' do
        it 'returns ok response with fields param' do
          get api(api_endpoint, oauth_access_token: token), params: { scope: 'blobs', search: 'foo', fields: ['title'] }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      it 'returns bad request with fields param' do
        get api("/projects/#{project.id}/search", user), params: { scope: 'blobs', search: 'test', fields: ['title'] }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns ok response with num_context_lines param' do
        get api(api_endpoint, user), params: { scope: 'blobs', search: 'Issue', num_context_lines: 3 }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  describe 'GET /search' do
    let(:endpoint) { '/search' }

    before do
      stub_application_setting(global_search_block_anonymous_searches_enabled: true)
      stub_ee_application_setting(global_search_limited_indexing_enabled: true)
    end

    it_behaves_like 'support for elasticsearch timeouts'

    context 'when Gitlab::Search::Client::ConnectionError is raised' do
      before do
        allow_next_instance_of(SearchService) do |service|
          allow(service).to receive(:search_objects)
            .and_raise(::Gitlab::Search::Client::ConnectionError.new('connection failed'))
        end
      end

      it 'returns service unavailable error' do
        get api(endpoint, user), params: { scope: 'issues', search: 'test' }

        expect(response).to have_gitlab_http_status(:service_unavailable)
        expect(json_response['message']).to eq('Search is currently unavailable. Please try again later.')
      end
    end

    context 'with correct params' do
      context 'when elasticsearch is disabled' do
        it_behaves_like 'elasticsearch disabled'

        it 'sets global search information for logging' do
          expect(Gitlab::Instrumentation::GlobalSearchApi).to receive(:set_information).with(
            type: 'basic',
            level: 'global',
            scope: 'issues',
            search_duration_s: a_kind_of(Numeric)
          )

          get api(endpoint, user), params: { scope: 'issues', search: 'john doe' }
        end
      end

      context 'when elasticsearch is enabled', :elastic_delete_by_query, :sidekiq_inline do
        before do
          stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
        end

        context 'when elasticsearch_limit_indexing is on' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: true)
          end

          context 'and namespace is indexed' do
            before_all do
              create :elasticsearch_indexed_namespace, namespace: group
            end

            it_behaves_like 'elasticsearch enabled', level: :global
          end
        end

        context 'when elasticsearch_limit_indexing is off' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: false)
          end

          # Routing matrix is covered by `ApplicationSetting#search_using_elasticsearch?`.
          it 'routes the search through Elasticsearch' do
            expect(Gitlab::Instrumentation::GlobalSearchApi).to receive(:set_information).with(
              type: 'advanced',
              level: 'global',
              scope: 'issues',
              search_duration_s: a_kind_of(Numeric)
            )

            get api(endpoint, user), params: { scope: 'issues', search: 'john doe' }
          end
        end
      end

      context 'when zoekt is enabled', :zoekt_settings_enabled, :zoekt_cache_disabled do
        it_behaves_like 'exact code search enabled', level: :global
      end
    end

    context 'with search_type param' do
      using RSpec::Parameterized::TableSyntax

      subject(:search) do
        get api(endpoint, user), params: { scope: scope, search: 'john doe', search_type: search_type }
      end

      where(:search_type, :scope, :use_elastic, :use_zoekt, :error_expected) do
        'basic'     | 'blobs'  | false | false | true
        'advanced'  | 'blobs'  | false | false | true
        'advanced'  | 'blobs'  | true  | false | false
        'zoekt'     | 'blobs'  | false | false | true
        'zoekt'     | 'blobs'  | false | true  | false
        'zoekt'     | 'issues' | false | true  | true
      end

      with_them do
        before do
          allow_next_instance_of(SearchService) do |search_service|
            allow(search_service).to receive_messages(
              use_elasticsearch?: use_elastic, use_zoekt?: use_zoekt, scope: scope, search_objects: []
            )
          end
        end

        it 'returns correct response' do
          search

          if error_expected
            expect(response).to have_gitlab_http_status(:bad_request)
          else
            expect(response).not_to have_gitlab_http_status(:bad_request)
          end
        end
      end
    end

    context 'for work_items scope with unavailable types' do
      let_it_be(:issue) { create(:issue, project: project, title: 'test issue') }

      context 'for non-MCP request' do
        it 'returns bad request when requesting unavailable work item types' do
          get api(endpoint, user), params: { scope: 'work_items', search: 'test', type: ['nonexistent'] }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq(
            '400 Bad request - All requested work item types are unavailable or do not exist'
          )
        end
      end

      context 'for mcp request' do
        it 'returns empty array when requesting unavailable work item types' do
          get api(endpoint, oauth_access_token: token),
            params: { scope: 'work_items', search: 'test', type: ['nonexistent'] }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq([])
        end

        it 'returns results when requesting available work item types' do
          get api(endpoint, oauth_access_token: token),
            params: { scope: 'work_items', search: 'test', type: ['issue'] }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to eq(1)
          expect(json_response.first['title']).to eq('test issue')
        end
      end
    end
  end

  describe "GET /groups/:id/-/search" do
    let(:endpoint) { "/groups/#{group.id}/-/search" }

    it_behaves_like 'support for elasticsearch timeouts'

    context 'with correct params' do
      context 'when elasticsearch is disabled' do
        it_behaves_like 'elasticsearch disabled'
      end

      context 'when elasticsearch is enabled', :elastic_delete_by_query, :sidekiq_inline do
        before do
          stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
          stub_application_setting(global_search_block_anonymous_searches_enabled: true)
          stub_ee_application_setting(global_search_limited_indexing_enabled: true)
        end

        context 'when elasticsearch_limit_indexing is on' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: true)
          end

          context 'when the namespace is indexed' do
            before_all do
              create :elasticsearch_indexed_namespace, namespace: group
            end

            it_behaves_like 'elasticsearch enabled', level: :group
          end

          context 'when the namespace is not indexed' do
            it_behaves_like 'elasticsearch disabled'
          end
        end

        context 'when elasticsearch_limit_indexing is off' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: false)
          end

          # Routing matrix is covered by `ApplicationSetting#search_using_elasticsearch?`.
          it 'routes the search through Elasticsearch' do
            expect(Gitlab::Instrumentation::GlobalSearchApi).to receive(:set_information).with(
              type: 'advanced',
              level: 'group',
              scope: 'issues',
              search_duration_s: a_kind_of(Numeric)
            )

            get api(endpoint, user), params: { scope: 'issues', search: 'john doe' }
          end
        end
      end

      context 'when zoekt is enabled', :zoekt_settings_enabled, :zoekt_cache_disabled do
        it_behaves_like 'exact code search enabled', level: :group
      end

      context 'when blobs scope is requested but is not available for this search' do
        before do
          stub_ee_application_setting(
            elasticsearch_search: true,
            elasticsearch_indexing: true,
            elasticsearch_limit_indexing: true
          )
        end

        it 'returns bad request' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'awesome', search_type: 'advanced' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Advanced search is not available')
        end
      end
    end
  end

  describe "GET /projects/:id/-/search" do
    let(:endpoint) { "/projects/#{project.id}/-/search" }

    it_behaves_like 'support for elasticsearch timeouts'

    shared_examples_for 'search enabled' do
      context 'for wiki_blobs scope' do
        before do
          wiki = create(:project_wiki, project: project)
          create(:wiki_page, wiki: wiki, title: 'home', content: "Awesome page")

          get api(endpoint, user), params: { scope: 'wiki_blobs', search: 'awesome' }
        end

        it_behaves_like 'response is correct', schema: 'public_api/v4/wiki_blobs'
      end

      context 'for commits scope' do
        before do
          get api(endpoint, user), params: { scope: 'commits', search: 'folder' }
        end

        it_behaves_like 'response is correct', schema: 'public_api/v4/commits_details', size: 2
      end

      context 'for blobs scope' do
        it_behaves_like 'response is correct', schema: 'public_api/v4/blobs', size: 2 do
          before do
            get api(endpoint, user), params: { scope: 'blobs', search: 'monitors' }
          end
        end

        context 'with filters' do
          it 'by filename' do
            get api(endpoint, user), params: { scope: 'blobs', search: 'mon filename:PROCESS.md' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.size).to eq(2)
            expect(json_response.first['path']).to eq('PROCESS.md')
            expect(json_response.first['filename']).to eq('PROCESS.md')
          end

          it 'by path' do
            get api(endpoint, user), params: { scope: 'blobs', search: 'mon path:files/markdown' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.size).to eq(8)
          end

          it 'by extension' do
            get api(endpoint, user), params: { scope: 'blobs', search: 'mon extension:md' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.size).to eq(11)
          end

          it 'by ref' do
            get api(endpoint, user),
              params: { scope: 'blobs', search: 'This file is used in tests for ci_environments_status',
                        ref: 'pages-deploy' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.size).to eq(1)
          end
        end
      end
    end

    context 'with correct params' do
      context 'when elasticsearch is disabled' do
        it_behaves_like 'search enabled'
        it_behaves_like 'merge request filters are rejected'
      end

      context 'when elasticsearch is enabled', :elastic_delete_by_query do
        before do
          stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
        end

        context 'when elasticsearch_limit_indexing is on' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: true)
          end

          context 'when the project is indexed' do
            before_all do
              create :elasticsearch_indexed_project, project: project
            end

            it_behaves_like 'elasticsearch enabled', level: :project
          end

          context 'when the project is not indexed' do
            it_behaves_like 'search enabled'
          end
        end

        context 'when elasticsearch_limit_indexing is off' do
          before do
            stub_ee_application_setting(elasticsearch_limit_indexing: false)
          end

          # Routing matrix is covered by `ApplicationSetting#search_using_elasticsearch?`.
          it 'routes the search through Elasticsearch' do
            expect(Gitlab::Instrumentation::GlobalSearchApi).to receive(:set_information).with(
              type: 'advanced',
              level: 'project',
              scope: 'issues',
              search_duration_s: a_kind_of(Numeric)
            )

            get api(endpoint, user), params: { scope: 'issues', search: 'john doe' }
          end
        end
      end

      context 'when zoekt is enabled', :zoekt_settings_enabled, :zoekt_cache_disabled do
        it_behaves_like 'exact code search enabled', level: :project
      end

      context 'when search_type=advanced is requested but elasticsearch is disabled' do
        before do
          stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
        end

        it 'returns a specific bad request error' do
          get api(endpoint, user), params: { scope: 'blobs', search: 'test', search_type: 'advanced' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Advanced search is not available')
        end
      end
    end
  end
end
