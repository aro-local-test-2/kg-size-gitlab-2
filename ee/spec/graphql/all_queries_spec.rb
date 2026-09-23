# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'graphql queries', feature_category: :api do
  include GraphqlQueryComplexityHelper

  complexity_overrides = {
    # Project management: https://gitlab.com/gitlab-org/gitlab/-/issues/584292
    'app/assets/javascripts/boards/graphql/lists_issues.query.graphql' => 590,
    # Selecting duoCreatedSession in the shared note fragment raised this by 5.
    # The EE fragment also gained duoCreatedSession { id }, raising it by a further 21.
    # See https://gitlab.com/gitlab-org/gitlab/-/merge_requests/250722
    # See https://gitlab.com/gitlab-org/gitlab/-/merge_requests/250297
    'app/assets/javascripts/work_items/graphql/notes/work_item_notes_by_iid.query.graphql' => 478,
    'ee/app/assets/javascripts/boards/graphql/lists_epics_with_color.query.graphql' => 370,
    'ee/app/assets/javascripts/iterations/queries/iteration_issues_with_label_filter.query.graphql' => 310,

    # Scored here for the first time. `@persist` sits on the `workItems` connection, so
    # `ClientFieldRedactor` used to drop the whole query body and the query was skipped.
    # See https://gitlab.com/gitlab-org/gitlab/-/merge_requests/250181
    'ee/app/assets/javascripts/issues/dashboard/queries/get_issues.query.graphql' => 265,

    # Code review: https://gitlab.com/gitlab-org/gitlab/-/issues/584293
    'app/assets/javascripts/ci/merge_requests/graphql/queries/get_merge_request_pipelines.query.graphql' => 628,
    'app/assets/javascripts/analytics/merge_request_analytics/graphql/queries/throughput_table.query.graphql' => 320,

    # False positive: the analyzer scores every @include facet at once, but only one is ever on.
    # MCP server: https://gitlab.com/gitlab-org/gitlab/-/issues/605878
    'app/graphql/queries/mcp/merge_requests/get_merge_request.query.graphql' => 413,
    # The EE copy adds the approvalState rule breakdown on top of the same facets.
    # See https://gitlab.com/gitlab-org/gitlab/-/issues/596590
    'ee/app/graphql/queries/mcp/merge_requests/get_merge_request.query.graphql' => 444,

    # Package registry: https://gitlab.com/gitlab-org/gitlab/-/issues/584294
    'app/assets/javascripts/packages_and_registries/package_registry/graphql/queries/get_packages.query.graphql' => 277,

    # Adding `duoSastVrWorkflowEnabled` to the shared `VulnerabilityBaseFields`
    # fragment raised each of these limits by 10.
    # See: https://gitlab.com/gitlab-org/gitlab/-/merge_requests/235353
    'ee/app/assets/javascripts/security_dashboard/graphql/queries/group_vulnerabilities.query.graphql' => 320,
    'ee/app/assets/javascripts/security_dashboard/graphql/queries/instance_vulnerabilities.query.graphql' => 310,
    'ee/app/assets/javascripts/security_dashboard/graphql/queries/project_vulnerabilities.query.graphql' => 350,

    # Security Platform Management: https://gitlab.com/gitlab-org/gitlab/-/issues/584297
    'ee/app/assets/javascripts/security_inventory/graphql/subgroups_and_projects.query.graphql' => 340,

    # Security Policies: PolicyScopeList fans out per-category attribute connections
    # (BusinessImpact, Application, BusinessUnit, Exposure for both including/excluding),
    # each selecting `count` so the UI can render a "+ N more" total while loading only
    # the first few nodes. Will collapse to a single field once
    # https://gitlab.com/gitlab-org/gitlab/-/issues/596686 ships.
    'ee/app/assets/javascripts/security_orchestration/graphql/queries/' \
      'group_security_policies.query.graphql' => 320,
    'ee/app/assets/javascripts/security_orchestration/graphql/queries/' \
      'project_security_policies.query.graphql' => 320,

    # Organizations: https://gitlab.com/gitlab-org/gitlab/-/issues/584299
    # This is a false-positive as the two large fields (contributedProjects and starredProjects) are
    # activated conditionally. This has a much lower complexity score in practice.
    'app/assets/javascripts/projects/your_work/graphql/queries/user_projects.query.graphql' => 263,

    # Pipeline execution: https://gitlab.com/gitlab-org/gitlab/-/issues/584301
    'app/assets/javascripts/ci/pipelines_page/graphql/queries/get_pipelines.query.graphql' => 315,
    'app/assets/javascripts/ci/commit/graphql/queries/get_commit_pipelines.query.graphql' => 271
  }

  describe 'complexity' do
    Gitlab::Graphql::Queries.all.each do |definition| # rubocop:disable Rails/FindEach -- Not an ActiveRecord relation
      relative_path = definition.file.delete_prefix("#{Rails.root}/") # rubocop:disable Rails/FilePath -- Can't be used to append '/'

      describe relative_path do
        it 'does not exceed complexity limit' do
          limit = complexity_overrides.fetch(relative_path, GitlabSchema::AUTHENTICATED_MAX_COMPLEXITY)

          expect(definition.complexity(GitlabSchema)).to be < limit
        end
      end
    end
  end

  # The work items list queries include a features field behind @include(if: $useWorkItemFeatures).
  # When the work_item_features_field feature flag is enabled globally, unauthenticated users
  # will also have the features field included, so we need to ensure the query complexity stays
  # within the unauthenticated limit i.e. <= DEFAULT_MAX_COMPLEXITY (200), at every page size the
  # list offers. The query only selects the fields the slim list query does not, so the two together
  # stay under the cap without dropping data.
  describe 'work items list query complexity with workItem.features field enabled' do
    # Every page size the list offers, mirroring `PAGE_SIZES` in
    # `app/assets/javascripts/vue_shared/components/page_size_selector.vue`.
    list_page_sizes = [20, 50, 100].freeze

    %w[
      app/assets/javascripts/work_items/list/graphql/get_work_items_full.query.graphql
      ee/app/assets/javascripts/work_items/list/graphql/get_work_items_full.query.graphql
    ].each do |query_path|
      describe query_path do
        let(:definition) { Gitlab::Graphql::Queries.find(Rails.root.join(query_path)).first }

        it 'does not exceed unauthenticated max complexity without features' do
          complexity = query_complexity_with_typename(definition.text, { "useWorkItemFeatures" => false })

          expect(complexity).to be <= GitlabSchema::DEFAULT_MAX_COMPLEXITY
        end

        list_page_sizes.each do |page_size|
          it "does not exceed unauthenticated max complexity with features at page size #{page_size}" do
            complexity = query_complexity_with_typename(definition.text, {
              "useWorkItemFeatures" => true,
              "firstPageSize" => page_size
            })

            expect(complexity).to be <= GitlabSchema::DEFAULT_MAX_COMPLEXITY
          end
        end
      end
    end
  end

  # The work item detail queries include a features field behind @include(if: $useWorkItemFeatures).
  # When the work_item_features_field feature flag is enabled, the query complexity must stay within
  # the cap for both authenticated regular users and admins. This guards against regressions where
  # adding fields to the WorkItemFeatures fragment pushes complexity past the cap.
  #
  # Note: the detail query still exceeds the unauthenticated cap (DEFAULT_MAX_COMPLEXITY), so a
  # logged-out visitor cannot load a work item while the flag is on. Bringing it under that cap
  # needs the remaining expensive features split into their own queries, which is tracked in
  # https://gitlab.com/gitlab-org/gitlab/-/issues/587972
  describe 'work item detail/mutation query complexity with workItem.features field enabled' do
    # `query_complexity_with_typename` injects `__typename` (as Apollo Client does at
    # runtime) so these guards reflect the real complexity the server evaluates. The raw
    # query text under-counts and hid real breaches (the detail query measured 240 here
    # but was 255 in production). We assert `<=` the limit since the server only rejects
    # queries that *exceed* it.
    #
    # Every document that returns a full work item payload is listed, since they all pull
    # in the same widgets/features fragments and therefore all sit close to the limit.
    %w[
      app/assets/javascripts/work_items/graphql/work_item_by_iid.query.graphql
      app/assets/javascripts/work_items/graphql/work_item_by_id.query.graphql
      app/assets/javascripts/work_items/graphql/create_work_item.mutation.graphql
      app/assets/javascripts/work_items/graphql/update_work_item.mutation.graphql
      app/assets/javascripts/work_items/graphql/work_item_convert.mutation.graphql
      app/assets/javascripts/work_items/graphql/move_work_item.mutation.graphql
      app/assets/javascripts/work_items/graphql/add_linked_items.mutation.graphql
      app/assets/javascripts/work_items/graphql/work_item_updated.subscription.graphql
    ].each do |query_path|
      describe query_path do
        let(:definition) { Gitlab::Graphql::Queries.find(Rails.root.join(query_path)).first }

        it 'does not exceed authenticated max complexity with features enabled' do
          complexity = query_complexity_with_typename(definition.text, { "useWorkItemFeatures" => true })

          expect(complexity).to be <= GitlabSchema::AUTHENTICATED_MAX_COMPLEXITY
        end

        it 'does not exceed admin max complexity with features enabled' do
          complexity = query_complexity_with_typename(definition.text, { "useWorkItemFeatures" => true })

          expect(complexity).to be <= GitlabSchema::ADMIN_MAX_COMPLEXITY
        end
      end
    end
  end

  # Anonymous visitors load the work item detail queries, so those are bound by the
  # unauthenticated limit too, not just the authenticated one asserted above. Mutations and
  # subscriptions need a session, so they are deliberately not listed here.
  # See https://gitlab.com/gitlab-org/gitlab/-/issues/587972
  describe 'work item detail query complexity for unauthenticated users' do
    %w[
      app/assets/javascripts/work_items/graphql/work_item_by_iid.query.graphql
      app/assets/javascripts/work_items/graphql/work_item_by_id.query.graphql
    ].each do |query_path|
      describe query_path do
        let(:definition) { Gitlab::Graphql::Queries.find(Rails.root.join(query_path)).first }

        it 'does not exceed unauthenticated max complexity with features enabled' do
          complexity = query_complexity_with_typename(definition.text, { "useWorkItemFeatures" => true })

          expect(complexity).to be <= GitlabSchema::DEFAULT_MAX_COMPLEXITY
        end
      end
    end
  end

  complexity_overrides.each_key do |file|
    describe "complexity override for #{file}" do
      it 'references an existing file' do
        # Remove the file from the override list to pass this test.
        expect(File.exist?(Rails.root.join(file))).to be(true)
      end
    end
  end
end
