# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers -- a fixture generator's seed is inherently many records
RSpec.describe 'Work Items Integration (GraphQL fixtures)', type: :request, feature_category: :team_planning do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:project, freeze: false) { create(:project, :repository, group: group) }
  let_it_be(:label1, freeze: false) { create(:label, project: project, title: 'To Do', color: '#F0AD4E') }
  let_it_be(:label2, freeze: false) { create(:label, project: project, title: 'Doing', color: '#5CB85C') }
  let_it_be(:assignable_user, freeze: false) { create(:user, username: 'assignable_user', name: 'Assignable User') }
  # A public project readable without authentication. The metadata query run with no
  # current_user against it returns every namespace permission false and
  # showNewWorkItem false, backing the NO_PERMISSIONS variant used by the
  # anonymous-user list spec.
  let_it_be(:public_project, freeze: false) { create(:project, :public, :repository, group: group) }

  let_it_be(:second_assignable_user, freeze: false) do
    create(:user, username: 'second_assignable_user', name: 'Second Assignable User')
  end

  let_it_be(:milestone, freeze: false) do
    create(:milestone, project: project, title: 'v1.0', start_date: 30.days.ago, due_date: 30.days.from_now)
  end

  let_it_be(:second_milestone, freeze: false) do
    create(:milestone, project: project, title: 'v2.0', start_date: 30.days.from_now,
      due_date: 60.days.from_now)
  end

  let_it_be(:releases, freeze: false) do
    [
      create(:release, project: project, tag: 'v1.0.0', milestones: [milestone]),
      create(:release, project: project, tag: 'v2.0.0', milestones: [second_milestone])
    ]
  end

  let_it_be(:iteration_cadence, freeze: false) { create(:iterations_cadence, group: group) }
  let_it_be(:iteration, freeze: false) { create(:iteration, iterations_cadence: iteration_cadence, group: group) }

  let_it_be(:second_iteration, freeze: false) do
    create(:iteration, iterations_cadence: iteration_cadence, group: group)
  end

  let_it_be(:closed_iteration, freeze: false) do
    create(:iteration, iterations_cadence: iteration_cadence, group: group,
      start_date: 2.days.ago, due_date: 1.day.ago, skip_future_date_validation: true)
  end

  let_it_be(:plan_cadence, freeze: false) do
    create(:iterations_cadence, title: 'plan cadence', group: group)
  end

  let_it_be(:plan_iteration, freeze: false) do
    create(:iteration, :with_due_date, iterations_cadence: plan_cadence, group: group,
      start_date: 1.week.from_now)
  end

  let_it_be(:work_item, freeze: false) do
    create(:work_item, :issue, project: project, title: 'Dependent test issue',
      author: user, assignees: [user], milestone: milestone,
      iteration: iteration, start_date: 5.days.ago, due_date: 10.days.from_now, weight: 3,
      health_status: :on_track)
  end

  let_it_be(:second_work_item, freeze: false) do
    create(:work_item, :issue, project: project, title: 'Second test issue', author: user,
      labels: [label1], assignees: [assignable_user])
  end

  let_it_be(:closed_work_item, freeze: false) do
    create(:work_item, :issue, :closed, project: project, title: 'Closed test issue', author: user)
  end

  # Labelled differently from second_work_item so the label filters return distinct
  # sets rather than collapsing into each other.
  let_it_be(:child_task, freeze: false) do
    create(:work_item, :task, project: project, title: 'Child task', author: second_assignable_user,
      labels: [label2], assignees: [second_assignable_user], milestone: second_milestone)
  end

  let_it_be(:child_task_parent_link, freeze: false) do
    create(:parent_link, work_item: child_task, work_item_parent: second_work_item)
  end

  let_it_be(:second_work_item_note, freeze: false) do
    create(:note, noteable: second_work_item, project: project, author: user, note: 'Test comment')
  end

  let_it_be(:second_work_item_upvote, freeze: false) do
    create(:award_emoji, :upvote, awardable: second_work_item, user: user)
  end

  # Carries the confidential flag and a description so the confidential and
  # search-within filters have something to match on.
  let_it_be(:blocking_work_item, freeze: false) do
    create(:work_item, :issue, project: project, title: 'Blocking issue', author: user,
      confidential: true, description: 'A searchable description')
  end

  let_it_be(:blocking_link, freeze: false) do
    create(:work_item_link, source: blocking_work_item, target: second_work_item, link_type: :blocks)
  end

  let_it_be(:work_item_body_reaction, freeze: false) do
    create(:award_emoji, awardable: work_item, name: '100', user: assignable_user)
  end

  let_it_be(:work_item_reaction_note, freeze: false) do
    create(:note, noteable: work_item, project: project, author: user, note: 'Reaction note')
  end

  let_it_be(:work_item_note_reaction, freeze: false) do
    create(:award_emoji, awardable: work_item_reaction_note, name: 'grinning', user: assignable_user)
  end

  # Created last so it does not renumber the DB ids of the work items above, which
  # the drawer/list fixtures and the hard-coded `workItemId` test helper depend on.
  let_it_be(:linkable_work_item, freeze: false) do
    create(:work_item, :issue, project: project, title: 'Linkable test issue', author: assignable_user)
  end

  let_it_be(:agent_plan_work_item, freeze: false) do
    create(:work_item, :issue, project: project, title: 'Agent plan test issue', author: user)
  end

  let_it_be(:agent_plan, freeze: false) do
    create(:work_item_agent_plan, work_item: agent_plan_work_item, content: 'Existing workplan content')
  end

  let_it_be(:crm, freeze: false) do
    organizations = [
      create(:crm_organization, group: group, name: 'GitLab Inc'),
      create(:crm_organization, group: group, name: 'Acme Corp')
    ]
    contacts = [
      create(:contact, group: group, organization: organizations.first),
      create(:contact, group: group, organization: organizations.first),
      create(:contact, group: group, organization: organizations.second)
    ]

    [second_work_item, blocking_work_item, linkable_work_item].each_with_index do |issue, index|
      create(:issue_customer_relations_contact, issue: issue, contact: contacts[index])
    end

    { organizations: organizations, contacts: contacts }
  end

  let(:licensed_features) do
    {
      epics: true,
      subepics: true,
      issuable_health_status: true,
      issue_weights: true,
      iterations: true,
      blocked_work_items: true,
      work_item_status: true,
      scoped_labels: true,
      custom_fields: true
    }
  end

  base_output_path = 'graphql/work_items/integration/'

  before_all do
    project.add_maintainer(user)
    project.add_developer(assignable_user)

    # Links the drawer work item so its linked-items query returns a row on mount,
    # which the remove-path integration spec relies on. Targets second_work_item so
    # the seeded row's title does not collide with the add-path token selector, which
    # searches for "Linkable test issue". Created in the hook (not a let_it_be) to
    # avoid adding another memoized helper, and because no example references it.
    create(:work_item_link, source: work_item, target: second_work_item, link_type: :relates_to)

    # Gives the drawer work item a pending to-do for the signed-in user so its
    # currentUserTodos widget records a node, which the to-do toggle spec relies on to
    # render in "mark as done" state on mount. Created in the hook for the same reasons
    # as the link above.
    create(:todo, :pending, user: user, project: project, target: work_item)
  end

  before do
    stub_licensed_features(licensed_features)
    sign_in(user)
  end

  describe GraphQL::Query do
    it "#{base_output_path}work_item_metadata.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_metadata.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_metadata_anonymous.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_metadata.query.graphql', ee: true
      )
      post_graphql(query, current_user: nil, variables: { fullPath: public_project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_items_full.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_full.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'opened',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_items_full_closed.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_full.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'closed',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}create_work_item_features.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/create_work_item_features.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_items_slim.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_slim.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'opened',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_items_slim_closed.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_slim.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'closed',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}search_labels.query.graphql.json" do
      query = get_graphql_query_as_string('work_items/list/graphql/search_labels.query.graphql')
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        isProject: true,
        searchIn: %w[TITLE DESCRIPTION]
      })
      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :labels, :nodes)).to be_present
    end

    it "#{base_output_path}get_work_items_count_only.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_count_only.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'opened',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    # One entry per filter the list can apply, generated for both list queries.
    # The suffix becomes the fixture name, which the MSW handler maps back to.
    assignee = 'assignable_user'
    second_assignee = 'second_assignable_user'
    author = 'assignable_user'
    second_author = 'second_assignable_user'
    milestone_title = 'v1.0'

    list_filters = {
      'with_label' => { labelName: ['To Do'] },
      'without_specific_label' => { not: { labelName: ['To Do'] } },
      'with_no_label' => { labelName: ['None'] },
      'with_any_label' => { labelName: ['Any'] },
      'with_any_of_labels' => { or: { labelNames: ['To Do', 'Doing'] } },
      'with_my_reaction' => { myReactionEmoji: AwardEmoji::THUMBS_UP },
      'without_my_reaction' => { not: { myReactionEmoji: AwardEmoji::THUMBS_UP } },
      'with_no_reaction' => { myReactionEmoji: 'None' },
      'with_any_reaction' => { myReactionEmoji: 'Any' },
      'confidential' => { confidential: true },
      'not_confidential' => { confidential: false },
      'matching_title' => { search: 'Dependent', in: ['TITLE'] },
      'matching_description' => { search: 'searchable', in: ['DESCRIPTION'] },
      'with_assignee' => { assigneeUsernames: [assignee] },
      'without_specific_assignee' => { not: { assigneeUsernames: [assignee] } },
      'with_no_assignee' => { assigneeWildcardId: 'NONE' },
      'with_any_assignee' => { assigneeWildcardId: 'ANY' },
      'with_any_of_assignees' => {
        or: { assigneeUsernames: [assignee, second_assignee] }
      },
      'with_author' => { authorUsername: author },
      'without_author' => { not: { authorUsername: [author] } },
      'with_any_of_authors' => {
        or: { authorUsernames: [author, second_author] }
      },
      'with_milestone' => { milestoneTitle: [milestone_title] },
      'without_specific_milestone' => { not: { milestoneTitle: [milestone_title] } },
      'with_no_milestone' => { milestoneWildcardId: 'NONE' },
      'with_any_milestone' => { milestoneWildcardId: 'ANY' },
      'with_upcoming_milestone' => { milestoneWildcardId: 'UPCOMING' },
      'with_started_milestone' => { milestoneWildcardId: 'STARTED' },
      'with_release' => { releaseTag: ['v1.0.0'] },
      'without_specific_release' => { not: { releaseTag: ['v1.0.0'] } },
      'with_no_release' => { releaseTagWildcardId: 'NONE' },
      'with_any_release' => { releaseTagWildcardId: 'ANY' }
    }
    list_query_kinds = %w[slim full].freeze

    list_query_kinds.each do |query_kind|
      it "#{base_output_path}get_work_items_#{query_kind}_group.query.graphql.json" do
        query = get_graphql_query_as_string(
          "work_items/list/graphql/get_work_items_#{query_kind}.query.graphql", ee: true
        )
        post_graphql(query, current_user: user, variables: {
          fullPath: group.full_path,
          sort: 'CREATED_DESC',
          state: 'opened',
          firstPageSize: 20,
          includeDescendants: true
        })
        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:namespace, :work_items, :nodes)).to be_present
      end
    end

    crm_filters = %w[
      with_crm_organization with_second_crm_organization
      with_crm_contact with_second_crm_contact
    ].freeze

    group_crm_filters = %w[with_crm_organization with_crm_contact].freeze

    def crm_filter_variables(suffix)
      case suffix
      when 'with_crm_organization' then { crmOrganizationId: crm[:organizations].first.id.to_s }
      when 'with_second_crm_organization' then { crmOrganizationId: crm[:organizations].second.id.to_s }
      when 'with_crm_contact' then { crmContactId: crm[:contacts].first.id.to_s }
      when 'with_second_crm_contact' then { crmContactId: crm[:contacts].second.id.to_s }
      end
    end

    crm_namespaces = { '' => :project, 'group_' => :group }.freeze

    context 'with CRM filters' do
      # rubocop:disable RSpec/BeforeAllRoleAssignment -- before_all leaks into other specs
      before do
        group.add_developer(user)
      end
      # rubocop:enable RSpec/BeforeAllRoleAssignment

      crm_namespaces.each do |prefix, namespace|
        (namespace == :group ? group_crm_filters : crm_filters).each do |suffix|
          list_query_kinds.each do |query_kind|
            it "#{base_output_path}get_work_items_#{query_kind}_#{prefix}#{suffix}.query.graphql.json" do
              query = get_graphql_query_as_string(
                "work_items/list/graphql/get_work_items_#{query_kind}.query.graphql", ee: true
              )
              path = namespace == :group ? group.full_path : project.full_path
              post_graphql(query, current_user: user, variables: {
                fullPath: path,
                sort: 'CREATED_DESC',
                state: 'opened',
                firstPageSize: 20,
                **crm_filter_variables(suffix)
              })
              expect_graphql_errors_to_be_empty
              expect(graphql_data_at(:namespace, :work_items, :nodes)).to be_present
            end
          end
        end
      end
    end

    list_filters.each do |suffix, filter_variables|
      list_query_kinds.each do |query_kind|
        it "#{base_output_path}get_work_items_#{query_kind}_#{suffix}.query.graphql.json" do
          query = get_graphql_query_as_string(
            "work_items/list/graphql/get_work_items_#{query_kind}.query.graphql", ee: true
          )
          post_graphql(query, current_user: user, variables: {
            fullPath: project.full_path,
            sort: 'CREATED_DESC',
            state: 'opened',
            firstPageSize: 20,
            **filter_variables
          })
          expect_graphql_errors_to_be_empty

          # Every filter here returns rows. One that matches nothing still writes a valid
          # fixture with no nodes, which only surfaces later as an unrelated DOM error in
          # the Jest spec. A fixture that should legitimately be empty belongs in its own
          # table and loop, rather than weakening this.
          expect(graphql_data_at(:namespace, :work_items, :nodes)).to be_present
        end
      end
    end

    it "#{base_output_path}namespace_work_item.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_work_item_features.query.graphql.json" do
      allow_unlimited_graphql_complexity

      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    # The status widget is licence gated, so an unlicensed namespace leaves it out of the
    # payload altogether. Captured in both shapes because the frontend reads whichever one
    # the useWorkItemFeatures flag asks for.
    it "#{base_output_path}namespace_work_item_status_unlicensed.query.graphql.json" do
      stub_licensed_features(licensed_features.merge(work_item_status: false))

      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_work_item_features_status_unlicensed.query.graphql.json" do
      allow_unlimited_graphql_complexity
      stub_licensed_features(licensed_features.merge(work_item_status: false))

      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_work_item_agent_plan.query.graphql.json" do
      stub_licensed_features(ai_workflows: true)
      stub_feature_flags(workplan: true)

      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: agent_plan_work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}current_user.query.graphql.json" do
      query = get_graphql_query_as_string(
        'graphql_shared/queries/current_user.query.graphql'
      )
      post_graphql(query, current_user: user)
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_user.query.graphql.json" do
      query = get_graphql_query_as_string(
        'graphql_shared/queries/get_user_callouts.query.graphql'
      )
      post_graphql(query, current_user: user)
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}workspace_permissions.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/workspace_permissions.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_work_item_types.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/namespace_work_item_types.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_ancestors_query.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_ancestors.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_notes_by_iid.query.graphql.json" do
      allow_unlimited_graphql_complexity

      query = get_graphql_query_as_string(
        'work_items/graphql/notes/work_item_notes_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_linked_items.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_linked_items.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_linked_items_features.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_linked_items.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_current_user_todos.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_current_user_todos.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_crm_contacts.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_crm_contacts.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_linked_resources.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_linked_resources.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_current_user_todos_features.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_current_user_todos.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_crm_contacts_features.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_crm_contacts.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_linked_resources_features.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_linked_resources.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s,
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_allowed_work_item_child_types.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_allowed_children.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_allowed_work_item_parent_types.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_allowed_parent_types.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_item_notifications_by_id.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/get_work_item_notifications_by_id.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_tree_query.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_tree.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_generate_description_permissions.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/ai_permissions_for_project.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_work_item_award_emojis.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/award_emoji.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_participants.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_participants.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_item_design_list.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/components/design_management/graphql/design_collection.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_paths.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/namespace_paths.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_vulnerabilities.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_vulnerabilities.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_merge_requests_enabled.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/namespace_merge_requests_enabled.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_project_root_ref.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/get_project_root_ref.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { projectFullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_development.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_development.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        id: work_item.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}group_workspace_permissions.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/group_workspace_permissions.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: group.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}has_work_items.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/has_work_items.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_description_templates_list.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_description_templates_list.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_labels.query.graphql.json" do
      query = get_graphql_query_as_string(
        'sidebar/components/labels/labels_select_widget/graphql/project_labels.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        searchTerm: ''
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}workspace_autocomplete_users_search.query.graphql.json" do
      query = get_graphql_query_as_string(
        'graphql_shared/queries/workspace_autocomplete_users.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        search: '',
        isProject: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_user_work_items_preferences.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/get_user_preferences.query.graphql'
      )
      issue_type = ::WorkItems::TypesFramework::Provider.new.find_by_base_type(:issue)
      post_graphql(query, current_user: user, variables: {
        namespace: project.full_path,
        workItemTypeId: issue_type.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}namespace_custom_field_names.query.graphql.json" do
      query = get_graphql_query_as_string(
        'vue_shared/components/filtered_search_bar/queries/custom_field_names.query.graphql',
        ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        active: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_types_configuration.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_types_configuration.query.graphql'
      )
      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_milestones.query.graphql.json" do
      query = get_graphql_query_as_string(
        'sidebar/queries/project_milestones.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        title: '',
        state: 'active',
        first: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_iterations.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/project_iterations.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        title: '',
        state: 'opened'
      })
      expect_graphql_errors_to_be_empty

      # The dropdown renders whatever this returns, so `state: opened` is the only thing
      # keeping the closed iteration out of it.
      ids = graphql_data_at(:namespace, :attributes, :nodes).pluck('id')
      expect(ids).to contain_exactly(
        iteration.to_global_id.to_s,
        second_iteration.to_global_id.to_s,
        plan_iteration.to_global_id.to_s
      )
    end

    it "#{base_output_path}project_iterations_search.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/project_iterations.query.graphql', ee: true
      )
      # The widget wraps the typed search term in quotes before sending it.
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        title: '"plan"',
        state: 'opened'
      })
      expect_graphql_errors_to_be_empty

      ids = graphql_data_at(:namespace, :attributes, :nodes).pluck('id')
      expect(ids).to contain_exactly(plan_iteration.to_global_id.to_s)
    end

    it "#{base_output_path}get_duo_workflow_status_check.query.graphql.json" do
      query = get_graphql_query_as_string(
        'ai/graphql/get_duo_workflow_status_check.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_email_participants_by_iid.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/notes/work_item_email_participants_by_iid.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_configured_flows.query.graphql.json" do
      query = get_graphql_query_as_string(
        'ai/graphql/get_configured_flows.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        projectId: project.to_global_id.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}open_child_item_count.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/open_child_count.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: second_work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}work_item_time_tracking.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/work_item_time_tracking.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: work_item.iid.to_s
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_work_items_rest.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/list/graphql/get_work_items_rest.query.graphql', ee: true
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        sort: 'CREATED_DESC',
        state: 'opened',
        firstPageSize: 20
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}project_work_items.query.graphql.json" do
      query = get_graphql_query_as_string(
        'work_items/graphql/project_work_items.query.graphql'
      )
      # Scope the search to the single linkable item so the token selector in the
      # linked-items spec returns one predictable result to click.
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        searchTerm: 'Linkable test issue'
      })
      expect_graphql_errors_to_be_empty
    end
  end

  describe 'REST endpoints' do
    it "#{base_output_path}can_create_branch.json" do
      get "/#{project.full_path}/-/issues/#{work_item.iid}/can_create_branch.json"

      expect(response).to be_successful
    end
  end

  describe 'Mutations' do
    let(:create_work_item_variables) do
      issue_type = ::WorkItems::TypesFramework::Provider.new.find_by_base_type(:issue)

      {
        input: {
          namespacePath: project.full_path,
          title: 'New test issue',
          workItemTypeId: issue_type.to_global_id.to_s
        }
      }
    end

    let(:create_work_item_mutation) do
      get_graphql_query_as_string('work_items/graphql/create_work_item.mutation.graphql')
    end

    it "#{base_output_path}update_work_item.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/update_work_item.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          title: work_item.title
        }
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}update_work_item_labels.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/update_work_item.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          labelsWidget: {
            addLabelIds: [label2.to_global_id.to_s]
          }
        }
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}update_work_item_milestone.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/update_work_item.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          milestoneWidget: {
            milestoneId: milestone.to_global_id.to_s
          }
        }
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}create_work_item_note.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/notes/create_work_item_note.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          noteableId: work_item.to_global_id.to_s,
          body: 'Test comment from drawer'
        }
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}create_work_item.mutation.graphql.json" do
      post_graphql(create_work_item_mutation, current_user: user, variables: create_work_item_variables)

      expect_graphql_errors_to_be_empty
    end

    # The app redirects to the new work item after creating it, so this captures the detail
    # query against the item the create mutation above makes, keeping the two iids in sync.
    it "#{base_output_path}namespace_work_item_created.query.graphql.json" do
      post_graphql(create_work_item_mutation, current_user: user, variables: create_work_item_variables)
      created_iid = graphql_data.dig('workItemCreate', 'workItem', 'iid')

      query = get_graphql_query_as_string('work_items/graphql/work_item_by_iid.query.graphql')
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: created_iid
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}update_work_item_assignees.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/update_work_item.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          assigneesWidget: {
            assigneeIds: [assignable_user.to_global_id.to_s]
          }
        }
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}add_linked_items.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/add_linked_items.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          linkType: 'RELATED',
          workItemsIds: [blocking_work_item.to_global_id.to_s]
        },
        useWorkItemFeatures: false
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}add_linked_items_features.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/add_linked_items.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: work_item.to_global_id.to_s,
          linkType: 'RELATED',
          workItemsIds: [closed_work_item.to_global_id.to_s]
        },
        useWorkItemFeatures: true
      })
      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}remove_linked_items.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'work_items/graphql/remove_linked_items.mutation.graphql'
      )
      post_graphql(mutation, current_user: user, variables: {
        input: {
          id: second_work_item.to_global_id.to_s,
          workItemsIds: [blocking_work_item.to_global_id.to_s]
        }
      })
      expect_graphql_errors_to_be_empty
    end
  end

  describe API::WorkItems::List do
    let(:list_params) do
      {
        fields: 'id,iid,global_id,title,title_html,state,created_at,updated_at,closed_at,reference,web_path,
        web_url,author,work_item_type,namespace',
        features: 'labels,assignees,milestone,start_and_due_date,status,
        health_status,weight,iteration,hierarchy,linked_items,award_emoji,development'
      }
    end

    it "#{base_output_path}rest_work_items_list.json" do
      get api("/namespaces/#{project.full_path}/-/work_items", user), params: list_params

      expect(response).to have_gitlab_http_status(:ok)
    end

    # The list rows carry a status of their own, and they land on the same cached work item
    # as the detail query's, so an unlicensed namespace has to be captured here too.
    it "#{base_output_path}rest_work_items_list_status_unlicensed.json" do
      stub_licensed_features(licensed_features.merge(work_item_status: false))

      get api("/namespaces/#{project.full_path}/-/work_items", user), params: list_params

      expect(response).to have_gitlab_http_status(:ok)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
