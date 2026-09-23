# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Commits Integration (GraphQL fixtures)', type: :request, feature_category: :source_code_management do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:user) { create(:user, developer_of: project) }

  # 'feature' is a branch in the seeded test repository. The open MR from it
  # gives getBranchMergeRequest its "View open merge request" base fixture.
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
  end

  # The seeded commits' author email gets a GitLab account, so the fixtures'
  # commit author fields resolve to a user and author links render.
  let_it_be(:commit_author) { create(:user, email: 'dmitriy.zaporozhets@gmail.com') }

  # A pipeline on the branch head so the commit list renders a CI status icon.
  let_it_be(:pipeline) do
    create(:ci_pipeline, :success, project: project, sha: project.commit('feature').sha, ref: 'feature')
  end

  base_output_path = 'graphql/commits/integration/'

  before do
    sign_in(user)
  end

  describe GraphQL::Query do
    let(:commit_list_query) do
      get_graphql_query_as_string('projects/commits/graphql/queries/commits.query.graphql')
    end

    def commit_list_variables(overrides = {})
      {
        projectPath: project.full_path,
        ref: 'refs/heads/feature',
        pipelineRef: 'feature',
        # The 'feature' branch has 9 commits, so a page size of 5 gives the
        # base fixture a second page (hasNextPage: true) for pagination coverage.
        first: 5
      }.merge(overrides)
    end

    def has_next_page
      graphql_data.dig('project', 'repository', 'commits', 'pageInfo', 'hasNextPage')
    end

    it "#{base_output_path}get_commit_list.query.graphql.json" do
      post_graphql(commit_list_query, current_user: user, variables: commit_list_variables)

      expect_graphql_errors_to_be_empty
      expect(has_next_page).to be(true)
    end

    it "#{base_output_path}get_commit_list_next_page.query.graphql.json" do
      post_graphql(commit_list_query, current_user: user, variables: commit_list_variables)
      end_cursor = graphql_data.dig('project', 'repository', 'commits', 'pageInfo', 'endCursor')

      post_graphql(commit_list_query, current_user: user, variables: commit_list_variables(after: end_cursor))

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_commit_list_all.query.graphql.json" do
      post_graphql(commit_list_query, current_user: user, variables: commit_list_variables(first: 50))

      expect_graphql_errors_to_be_empty
      # The Jest pagination specs expect this page size to fit every commit.
      expect(has_next_page).to be(false)
    end

    it "#{base_output_path}get_commit_list_search.query.graphql.json" do
      post_graphql(commit_list_query, current_user: user, variables: commit_list_variables(query: 'submodule'))

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_open_mr_count_for_blob_path.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/open_mr_count.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectPath: project.full_path,
        targetBranch: ['feature'],
        blobPath: 'files/ruby',
        createdAfter: 29.days.ago.iso8601
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_commit_details.query.graphql.json" do
      query = get_graphql_query_as_string('projects/commits/graphql/queries/commit_details.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectPath: project.full_path,
        ref: project.commit('feature').sha
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_branch_merge_request.query.graphql.json" do
      query = get_graphql_query_as_string('projects/commits/graphql/queries/branch_merge_request.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectPath: project.full_path,
        sourceBranch: 'feature',
        targetBranch: 'master'
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_commit_list_branch_names.query.graphql.json" do
      query = get_graphql_query_as_string('projects/commits/graphql/queries/branch_names.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectPath: project.full_path,
        ref: 'feature'
      })

      expect_graphql_errors_to_be_empty
    end
  end
end
