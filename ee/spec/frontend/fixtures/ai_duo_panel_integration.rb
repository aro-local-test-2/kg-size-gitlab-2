# frozen_string_literal: true

require 'spec_helper'

# Generates every GraphQL fixture the Duo chat frontend integration tests consume,
# for the panel surface and the agentic chat surface alike.
#
# The two surfaces need setup that cannot be shared: the agentic examples
# travel the clock to their checkpoint, which would reorder the conversation
# threads the panel examples assert on. So each owns a describe block with its
# own records and its own `before`, and only the output path is common.
RSpec.describe 'Duo chat (GraphQL fixtures)', type: :request, feature_category: :duo_chat do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers
  include Ai::Catalog::TestHelpers

  base_output_path = 'graphql/ai_duo_panel/integration/'

  describe 'panel' do
    let_it_be(:user, freeze: false) { create(:user) }
    let_it_be(:group, freeze: false) { create(:group) }
    let_it_be(:project, freeze: false) { create(:project, group: group) }

    let_it_be(:thread_with_messages, freeze: false) do
      create(:ai_conversation_thread, user: user, conversation_type: :duo_chat,
        last_updated_at: 2.hours.ago)
    end

    let_it_be(:empty_thread, freeze: false) do
      create(:ai_conversation_thread, user: user, conversation_type: :duo_chat,
        last_updated_at: 1.day.ago)
    end

    let_it_be(:user_message, freeze: false) do
      create(:ai_conversation_message, thread: thread_with_messages, role: :user,
        content: 'How do I refactor this function?')
    end

    let_it_be(:assistant_message, freeze: false) do
      create(:ai_conversation_message, :assistant, thread: thread_with_messages,
        content: 'You can extract the inner loop into a helper.')
    end

    let_it_be(:agent_a, freeze: false) { create(:ai_catalog_agent, :public, project: project) }
    # Referenced by nothing directly, but `get_configured_agents` and
    # `get_foundational_chat_agents` only list an agent that has a released version.
    let_it_be(:agent_a_version, freeze: false) do
      create(:ai_catalog_agent_version, :released, item: agent_a, version: '1.0.0',
        definition: { 'system_prompt' => 'Security agent', 'tools' => [], 'user_prompt' => '' })
    end

    let_it_be(:agent_a_consumer, freeze: false) do
      create(:ai_catalog_item_consumer, :for_agent,
        item: agent_a, project: project, pinned_version_prefix: '1.0.0')
    end

    let_it_be(:agent_b, freeze: false) { create(:ai_catalog_agent, :public, project: project) }
    let_it_be(:agent_b_version, freeze: false) do
      create(:ai_catalog_agent_version, :released, item: agent_b, version: '1.0.0',
        definition: { 'system_prompt' => 'Planning agent', 'tools' => [], 'user_prompt' => '' })
    end

    let_it_be(:agent_b_consumer, freeze: false) do
      create(:ai_catalog_item_consumer, :for_agent,
        item: agent_b, project: project, pinned_version_prefix: '1.0.0')
    end

    let_it_be(:work_item, freeze: false) { create(:work_item, project: project) }

    before_all do
      project.add_maintainer(user)
    end

    before do
      enable_ai_catalog
      stub_licensed_features(ai_catalog: true, ai_features: true)
      # The foundational-agents resolver branches on SaaS detection. Force the
      # namespace branch so the project's root namespace governs the agent list,
      # rather than relying on a default-organization global that isn't seeded here.
      stub_saas_features(gitlab_com_subscriptions: true)
      # User-level Duo chat access is gated by ChatAuthorizer; stub to keep fixtures
      # deterministic regardless of license/cloud-connector state in test env.
      allow(::Gitlab::Llm::Chain::Utils::ChatAuthorizer)
        .to receive(:user)
        .and_return(::Gitlab::Llm::Utils::Authorizer::Response.new(allowed: true))
      sign_in(user)
    end

    describe GraphQL::Query, 'duo_chat_available' do
      it "#{base_output_path}duo_chat_available.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/duo_chat_available.query.graphql', ee: true)
        post_graphql(query, current_user: user)
        expect_graphql_errors_to_be_empty
      end
    end

    describe GraphQL::Query, 'conversation threads and messages' do
      it "#{base_output_path}get_ai_conversation_threads.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_ai_conversation_threads.query.graphql', ee: true)
        post_graphql(query, current_user: user)
        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_ai_messages_with_thread.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_ai_messages_with_thread.query.graphql', ee: true)
        post_graphql(query, current_user: user, variables: { threadId: thread_with_messages.to_global_id.to_s })
        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_ai_messages_with_thread_empty.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_ai_messages_with_thread.query.graphql', ee: true)
        post_graphql(query, current_user: user, variables: { threadId: empty_thread.to_global_id.to_s })
        expect_graphql_errors_to_be_empty
      end
    end

    describe GraphQL::Query, 'agents' do
      it "#{base_output_path}get_configured_agents.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_configured_agents.query.graphql', ee: true)
        post_graphql(query, current_user: user, variables: {
          projectId: project.to_global_id.to_s,
          groupId: group.to_global_id.to_s,
          includeFoundationalConsumers: false,
          first: 25
        })
        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_foundational_chat_agents.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_foundational_chat_agents.graphql', ee: true)
        post_graphql(query, current_user: user, variables: { projectId: project.to_global_id.to_s })
        expect_graphql_errors_to_be_empty
      end
    end

    describe GraphQL::Query, 'mutations' do
      # `chat` is intentionally not generated: no integration spec sends a classic-surface
      # prompt, so a fixture would only be a file to keep current. Add one alongside
      # the spec that needs it rather than up front.

      # Fired by `ai_panel.vue` when the panel auto-expands. Nothing asserts on the
      # response, but it has to resolve: an unhandled operation trips the suite-wide
      # "missing graphql handlers" warning, which fails the whole file.
      it "#{base_output_path}dismiss_user_callout.mutation.graphql.json" do
        mutation = get_graphql_query_as_string(
          'graphql_shared/mutations/dismiss_user_callout.mutation.graphql'
        )
        post_graphql(mutation, current_user: user, variables: {
          input: { featureName: 'duo_panel_auto_expanded' }
        })
        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('userCalloutCreate', 'errors')).to be_empty
      end

      it "#{base_output_path}delete_conversation_thread.mutation.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/delete_conversation_thread.mutation.graphql', ee: true)
        post_graphql(query, current_user: user, variables: {
          input: { threadId: empty_thread.to_global_id.to_s }
        })
        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}update_duo_default_namespace.mutation.graphql.json" do
        mutation = get_graphql_query_as_string(
          'ai/graphql/update_duo_default_namespace.mutation.graphql', ee: true
        )

        # `group` is already a candidate: the maintainer role on `project` puts its root
        # namespace in `authorized_groups.top_level`. Writing the preference here rather
        # than in `before_all` keeps it rolled back after this example -- a user who ends
        # up with a default namespace resolves a different foundational-agents list.
        #
        # Which namespace this records is incidental. The component reads only `errors`
        # off the response, and the spec asserts on the id it *sent*, so the echoed
        # namespace need not match the group a test clicks.
        post_graphql(mutation, current_user: user, variables: {
          input: { duoDefaultNamespaceId: group.id }
        })
        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('userPreferencesUpdate', 'errors')).to be_empty
      end
    end

    # The following queries fire automatically when the real DuoAgenticChatStateManager
    # is mounted in the panel. We generate empty/default fixtures so MSW has a handler
    # to return; the test doesn't assert on their values, it just needs them to resolve.
    #
    # Operations that ai/duo_agentic_chat.rb also generates are deliberately absent:
    # the MSW handler merges both fixture directories and the agentic copy wins, so
    # generating them twice only produced a file that was written and then shadowed.
    describe GraphQL::Query, 'state manager bootstrap queries' do
      it "#{base_output_path}get_ai_slash_commands.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_ai_slash_commands.query.graphql', ee: true)
        post_graphql(query, current_user: user, variables: { url: 'http://localhost/' })
        expect_graphql_errors_to_be_empty
      end

      # Filename matches the GraphQL operation name (`getUserAgentFlows`, plural)
      # rather than the source path (`get_user_agent_flow.query.graphql`, singular).
      # `loadFixturesMap` keys fixtures by camelCased filename, so that drift has to
      # be reconciled here.
      it "#{base_output_path}get_user_agent_flows.query.graphql.json" do
        query = get_graphql_query_as_string(
          'ai/duo_agents_platform/graphql/queries/get_user_agent_flow.query.graphql', ee: true
        )
        post_graphql(query, current_user: user, variables: { first: 20 })
        expect_graphql_errors_to_be_empty
      end

      # The session inbox reads two aliases of `duoWorkflowWorkflows` out of one
      # query, so a single fixture has to satisfy both. Records live in a nested
      # `let_it_be` rather than the outer block: 20+ sessions here would otherwise
      # rewrite `get_user_agent_flows` and the specs that count its rows.
      describe 'session inbox' do
        # One past `needsDecisionFirst: 20`, so `needsDecision.pageInfo.hasNextPage`
        # is true and the decision tab's pager renders.
        awaiting_count = 21

        # `read_duo_workflow` resolves the Duo entitlement through an add-on purchase
        # under the outer block's SaaS stub, and unauthorized nodes leave a connection
        # silently, so without this both aliases come back empty.
        before do
          stub_licensed_features(ai_catalog: true, ai_features: true, ai_workflows: true)
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        let_it_be(:awaiting_sessions, freeze: false) do
          # Set through the state machine rather than a factory trait: only two of the
          # three awaiting statuses have one, and the inbox has to show all three.
          states = ::Ai::DuoWorkflows::Workflow.state_machines[:status].states
          statuses = ::Ai::DuoWorkflows::Workflow::GROUPED_STATUSES.fetch(:awaiting_input)

          Array.new(awaiting_count) do |index|
            create(:duo_workflows_workflow,
              project: project, user: user, goal: "Awaiting session #{index + 1}",
              status: states[statuses[index % statuses.size]].value,
              updated_at: (awaiting_count - index).minutes.ago)
          end
        end

        # `all` is not a superset page of `needsDecision`: these sort ahead of every
        # awaiting session, so the two connections' first 20 rows differ and a test
        # cannot pass by reading the wrong alias.
        let_it_be(:running_sessions, freeze: false) do
          Array.new(3) do |index|
            create(:duo_workflows_workflow, :running,
              project: project, user: user, goal: "Running session #{index + 1}",
              updated_at: index.seconds.ago)
          end
        end

        it "#{base_output_path}get_user_agent_flow_inbox.query.graphql.json" do
          query = get_graphql_query_as_string(
            'ai/duo_agents_platform/graphql/queries/get_user_agent_flow_inbox.query.graphql', ee: true
          )

          post_graphql(query, current_user: user, variables: {
            type: 'non_foundational_chat_agents',
            sort: 'UPDATED_DESC',
            needsDecisionFirst: 20,
            allFirst: 20
          })

          expect_graphql_errors_to_be_empty

          # A mismatched fragment type condition makes Apollo drop the aliased fields
          # silently, so the fixture is worthless unless both connections came back
          # populated and paginating.
          %w[needsDecision all].each do |alias_name|
            expect(graphql_data.dig(alias_name, 'edges').size).to eq(20)
            expect(graphql_data.dig(alias_name, 'pageInfo', 'hasNextPage')).to be(true)
          end
        end
      end

      it "#{base_output_path}get_flow_types.query.graphql.json" do
        query = get_graphql_query_as_string(
          'ai/duo_agents_platform/graphql/queries/get_flow_types.query.graphql', ee: true
        )
        post_graphql(query, current_user: user)
        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_duo_agent_sessions_on_work_item.query.graphql.json" do
        # The `ai_session` widget is gated on the `ai_workflows` licence. Without it
        # the field resolves to null and the fixture stops describing a work item
        # that actually has agent sessions.
        stub_licensed_features(ai_catalog: true, ai_features: true, ai_workflows: true)

        query = get_graphql_query_as_string(
          'ai/shared/widgets/graphql/get_duo_agent_sessions_on_work_item.query.graphql', ee: true
        )
        post_graphql(query, current_user: user, variables: { id: work_item.to_global_id.to_s })
        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('workItem', 'features', 'aiSession')).not_to be_nil
      end
    end

    describe GraphQL::Query, 'default namespace candidates' do
      it "#{base_output_path}get_duo_default_namespace_candidates.query.graphql.json" do
        # Created here rather than with `let_it_be` so it is rolled back after this
        # example. Candidates are `authorized_groups.top_level`, and `duo_default_namespace`
        # only auto-resolves when exactly ONE candidate exists (see
        # EE::UserPreference#duo_default_namespace_candidates). A second group that
        # outlived this example would leave the user with no default namespace, and
        # the foundational-agents fixture silently loses 8 of its 10 agents.
        create(:group, name: 'Duo Candidate Group').add_developer(user)

        query = get_graphql_query_as_string(
          'ai/graphql/get_duo_default_namespace_candidates.query.graphql', ee: true
        )
        post_graphql(query, current_user: user)
        expect_graphql_errors_to_be_empty

        # The selector is only meaningful with something to choose between; the empty
        # list is the separate EMPTY variant, built by transforming this fixture.
        expect(graphql_data.dig('duoDefaultNamespaceCandidates', 'nodes').size).to eq(2)
      end
    end
  end

  # Fixtures for the agentic chat surface.
  #
  # The conversation in `getWorkflowLatestCheckpoint` is shaped to reproduce two
  # latent regressions deterministically:
  #
  #   1. `toolInfo` is stored as a Ruby hash in the checkpoint JSON but the
  #      `DuoMessageType` resolver serialises it via `.to_json`, so the GraphQL
  #      response contains a JSON *string*. The frontend's
  #      `WorkflowUtils.normalizeDuoMessages` must parse it back into an object.
  #
  #   2. `AiAdditionalContext` objects share `id` values across messages (the id
  #      is a discriminator constant, not a row id). Apollo's default `__typename:id`
  #      normalisation would collapse them into one shared cache entry. The two
  #      user messages in the fixture carry the same three `additional_context` ids
  #      but deliberately different `metadata` to make a cache collision observable.
  describe 'agentic chat', feature_category: :duo_agent_platform do
    let_it_be(:user, freeze: false) { create(:user) }
    let_it_be(:group, freeze: false) { create(:group, path: 'group') }
    let_it_be(:project, freeze: false) { create(:project, path: 'project-1', namespace: group) }

    # A project with a real repository holding the two rule files that
    # `RuleContextProvider` looks for. Used by the `getRuleContent` fixture so the
    # response comes from the real `blobs(paths:)` resolver -- the frontend
    # switches on `blob.name`, so the basename returned by the resolver is part of
    # the contract under test.
    let_it_be(:rules_project, freeze: false) do
      create(:project, :repository, path: 'project-with-rules', namespace: group).tap do |rules_project|
        %w[AGENTS.md .gitlab/duo/chat-rules.md].each do |path|
          rules_project.repository.create_file(
            user,
            path,
            "content of #{path}",
            message: "Add #{path}",
            branch_name: rules_project.default_branch
          )
        end
      end
    end

    # Feature setting for the `getAiChatAvailableModels` fixture.
    # `offered_model_ref` pins the model so the response includes a non-null
    # `pinnedModel` field, making the fixture more representative.
    let_it_be(:agentic_chat_feature_setting, freeze: false) do
      create(:ai_namespace_feature_setting,
        namespace: group,
        feature: :duo_agent_platform_agentic_chat,
        offered_model_ref: 'claude_sonnet_3_7_20250219')
    end

    # Workflow used by `getWorkflowLatestCheckpoint`, `getUserWorkflows`, and
    # `getFlowStatus` fixtures.
    # The `:agentic_chat` trait sets `workflow_definition: "chat"` so the
    # workflow matches the `foundational_chat_agents` type filter and is
    # returned by the `getUserWorkflows` query. The state manager now gates
    # thread hydration on the workflow appearing in that list.
    let_it_be(:workflow, freeze: false) do
      create(:duo_workflows_workflow, :input_required, :agentic_chat,
        user: user,
        project: project,
        goal: 'Hi from project one')
    end

    # Checkpoint whose `ui_chat_log` encodes the two regression scenarios:
    #   - user-A / user-B share additional_context ids with different metadata
    #   - agent-A carries a tool_info hash (serialised to JSON string by the API)
    let_it_be(:checkpoint, freeze: false) do
      create(:duo_workflows_checkpoint,
        workflow: workflow,
        project: project,
        checkpoint: {
          'channel_values' => {
            'ui_chat_log' => [
              {
                'content' => 'Hi from project one',
                'message_type' => 'user',
                'message_sub_type' => nil,
                'status' => 'success',
                'tool_info' => nil,
                'timestamp' => '2026-05-19T10:00:00Z',
                'correlation_id' => nil,
                'message_id' => 'user-A',
                'role' => 'user',
                'component_name' => nil,
                'subsession_id' => nil,
                'additional_context' => [
                  {
                    'id' => 'page-context',
                    'category' => 'repository',
                    'content' => '<current_gitlab_page_url>/group/project-1</current_gitlab_page_url>',
                    'metadata' => {
                      'title' => 'Current page',
                      'icon' => 'link',
                      'enabled' => true,
                      'subType' => 'open_tab',
                      'subTypeLabel' => 'Current page',
                      'secondaryText' => 'Page context /group/project-1',
                      'projectPath' => 'group/project-1',
                      'pagePath' => '/group/project-1'
                    }
                  },
                  {
                    'id' => 'agents-md-user-instructions',
                    'category' => 'repository',
                    'content' => 'AGENTS.md content',
                    'metadata' => {
                      'title' => 'AGENTS.md',
                      'icon' => 'document',
                      'enabled' => true,
                      'subType' => 'user_rule',
                      'subTypeLabel' => 'group/project-1 AGENTS.md',
                      'secondaryText' => 'AGENTS.md included',
                      'oid' => 'oid-agents-md-real'
                    }
                  },
                  {
                    'id' => 'chat-rules-user-instructions',
                    'category' => 'repository',
                    'content' => 'chat-rules.md content',
                    'metadata' => {
                      'title' => 'chat-rules.md',
                      'icon' => 'document',
                      'enabled' => true,
                      'subType' => 'user_rule',
                      'subTypeLabel' => 'group/project-1 chat-rules.md',
                      'secondaryText' => 'chat-rules.md included',
                      'oid' => 'oid-chat-rules-real'
                    }
                  }
                ]
              },
              {
                'content' => 'hi',
                'message_type' => 'agent',
                'message_sub_type' => nil,
                'status' => 'success',
                # Stored as a Ruby hash; DuoMessageType#tool_info calls .to_json on it,
                # so the GraphQL response contains a JSON string -- the regression under test.
                'tool_info' => { 'name' => 'list_repository_tree', 'args' => { 'ref' => 'main' } },
                'timestamp' => '2026-05-19T10:00:01Z',
                'correlation_id' => nil,
                'message_id' => 'agent-A',
                'role' => 'assistant',
                'component_name' => nil,
                'subsession_id' => nil,
                'additional_context' => nil
              },
              {
                'content' => 'Making GitLab API request: /api/v4/projects/1',
                'message_type' => 'tool',
                'message_sub_type' => 'gitlab_api_get',
                'status' => 'success',
                'tool_info' => {
                  'name' => 'gitlab_api_get',
                  'args' => { 'endpoint' => '/api/v4/projects/1' },
                  'tool_response' => {
                    'name' => 'gitlab_api_get',
                    'type' => 'ToolMessage',
                    'status' => 'success',
                    'content' => '{"status":"success","data":{"id":1,"path_with_namespace":"group/project-1"}}',
                    'tool_call_id' => 'tool-C'
                  }
                },
                'timestamp' => '2026-05-19T10:00:02Z',
                'correlation_id' => nil,
                'message_id' => 'tool-C',
                'role' => nil,
                'component_name' => nil,
                'subsession_id' => nil,
                'additional_context' => nil
              },
              {
                'content' => 'Making GitLab API request: /api/v4/projects/1/repository/files/README.md',
                'message_type' => 'tool',
                'message_sub_type' => 'gitlab_api_get',
                'status' => 'success',
                'tool_info' => {
                  'name' => 'gitlab_api_get',
                  'args' => {
                    'endpoint' => '/api/v4/projects/1/repository/files/README.md',
                    'params' => { 'ref' => 'HEAD' }
                  },
                  'tool_response' => {
                    'name' => 'gitlab_api_get',
                    'type' => 'ToolMessage',
                    'status' => 'success',
                    'content' => '{"status":"success","data":{"file_name":"README.md","ref":"HEAD"}}',
                    'tool_call_id' => 'tool-D'
                  }
                },
                'timestamp' => '2026-05-19T10:00:03Z',
                'correlation_id' => nil,
                'message_id' => 'tool-D',
                'role' => nil,
                'component_name' => nil,
                'subsession_id' => nil,
                'additional_context' => nil
              },
              {
                'content' => 'Hi from project two',
                'message_type' => 'user',
                'message_sub_type' => nil,
                'status' => 'success',
                'tool_info' => nil,
                'timestamp' => '2026-05-19T10:01:00Z',
                'correlation_id' => nil,
                'message_id' => 'user-B',
                'role' => 'user',
                'component_name' => nil,
                'subsession_id' => nil,
                # Same id values as user-A but different metadata.  Without the
                # `AiAdditionalContext: { keyFields: false }` Apollo type policy,
                # the two `page-context` entries (and the others) would be merged
                # into a single cache slot.
                'additional_context' => [
                  {
                    'id' => 'page-context',
                    'category' => 'repository',
                    'content' => '<current_gitlab_page_url>/group/project-2</current_gitlab_page_url>',
                    'metadata' => {
                      'title' => 'Current page',
                      'icon' => 'link',
                      'enabled' => true,
                      'subType' => 'open_tab',
                      'subTypeLabel' => 'Current page',
                      'secondaryText' => 'Page context /group/project-2',
                      'projectPath' => 'group/project-2',
                      'pagePath' => '/group/project-2'
                    }
                  },
                  {
                    'id' => 'agents-md-user-instructions',
                    'category' => 'repository',
                    'content' => 'AGENTS.md content',
                    'metadata' => {
                      'title' => 'AGENTS.md',
                      'icon' => 'document',
                      'enabled' => true,
                      'subType' => 'user_rule',
                      'subTypeLabel' => 'group/project-2 AGENTS.md',
                      'secondaryText' => 'AGENTS.md included',
                      'oid' => 'oid-agents-md-real'
                    }
                  },
                  {
                    'id' => 'chat-rules-user-instructions',
                    'category' => 'repository',
                    'content' => 'Ignore previous chat-rules.md',
                    'metadata' => {
                      'title' => 'Ignore previous chat-rules.md',
                      'icon' => 'document',
                      'enabled' => true,
                      'subType' => 'user_rule',
                      'subTypeLabel' => 'chat-rules.md was not found in this page',
                      'secondaryText' => 'Prompted to ignore it',
                      'oid' => ''
                    }
                  }
                ]
              },
              {
                'content' => 'hi',
                'message_type' => 'agent',
                'message_sub_type' => nil,
                'status' => 'success',
                'tool_info' => nil,
                'timestamp' => '2026-05-19T10:01:01Z',
                'correlation_id' => nil,
                'message_id' => 'agent-B',
                'role' => 'assistant',
                'component_name' => nil,
                'subsession_id' => nil,
                'additional_context' => nil
              }
            ]
          }
        })
    end

    before_all do
      project.add_developer(user)
      group.add_owner(user)
    end

    before do
      # Travel to the checkpoint's own created_at so the new
      # `created_on_or_before(Time.current + 1.hour)` bound in Checkpoint.latest includes it.
      travel_to(checkpoint.created_at + 1.second)
      sign_in(user)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      # The workflow is an agentic-chat (`chat`) flow, so its policy authorises
      # via `access_duo_agentic_chat`, which calls StageCheck for `:agentic_chat`.
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(true)
      # rubocop:disable RSpec/AnyInstanceOf -- same pattern as existing duo_workflow specs
      allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
      # rubocop:enable RSpec/AnyInstanceOf
    end

    describe GraphQL::Query, type: :request do
      # The archived list and the archived conversation are separate examples, and
      # rolling an example back does not roll back the id sequence. Pin the id so
      # both fixtures describe the same workflow, which is what lets the MSW handler
      # pair a list entry with its recorded conversation.
      let(:archived_workflow_id) { 9_000_001 }
      let(:first_thread_workflow_id) { 9_000_002 }
      let(:second_thread_workflow_id) { 9_000_003 }
      let(:contextual_workflow_id) { 9_000_004 }

      def rule_blob_oid(path)
        rules_project.repository.blob_at(rules_project.default_branch, path).id
      end

      # `Workflow#archived?` is derived from `created_at`, not a column, so the
      # workflow is aged past the retention window rather than flagged.
      def create_archived_workflow
        create(:duo_workflows_workflow, :input_required, :agentic_chat,
          id: archived_workflow_id,
          user: user,
          project: project,
          goal: 'Refactor this very old conversation',
          created_at: (Ai::DuoWorkflows::CHECKPOINT_RETENTION_DAYS + 1).days.ago)
      end

      def simple_exchange(question, answer)
        [
          {
            'content' => question,
            'message_type' => 'user',
            'message_sub_type' => nil,
            'status' => 'success',
            'tool_info' => nil,
            'timestamp' => '2026-05-19T10:00:00Z',
            'correlation_id' => nil,
            'message_id' => 'exchange-user',
            'role' => 'user',
            'component_name' => nil,
            'subsession_id' => nil,
            'additional_context' => nil
          },
          {
            'content' => answer,
            'message_type' => 'agent',
            'message_sub_type' => nil,
            'status' => 'success',
            'tool_info' => nil,
            'timestamp' => '2026-05-19T10:00:05Z',
            'correlation_id' => nil,
            'message_id' => 'exchange-agent',
            'role' => 'assistant',
            'component_name' => nil,
            'subsession_id' => nil,
            'additional_context' => nil
          }
        ]
      end

      it "#{base_output_path}get_workflow_latest_checkpoint.query.graphql.json" do
        query = get_graphql_query_as_string(
          'ai/graphql/get_workflow_latest_checkpoint.query.graphql', ee: true
        )

        post_graphql(query, current_user: user, variables: { workflowId: workflow.to_global_id.to_s })

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_user_workflows.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_user_workflow.query.graphql', ee: true)

        post_graphql(query, current_user: user, variables: { type: 'foundational_chat_agents', first: 20 })

        expect_graphql_errors_to_be_empty
      end

      # A second `getUserWorkflows` fixture containing an archived workflow alongside
      # the active one, so `archived_thread_spec` can drive both states from a real
      # response. `Workflow#archived?` is derived from `created_at`, not a column, so
      # the workflow is aged past the retention window rather than flagged.
      # Created inside the example (rolled back afterwards) to keep the plain
      # `get_user_workflows` fixture a single-workflow list.
      it "#{base_output_path}get_user_workflows_with_archived.query.graphql.json" do
        create_archived_workflow

        query = get_graphql_query_as_string('ai/graphql/get_user_workflow.query.graphql', ee: true)

        post_graphql(query, current_user: user, variables: { type: 'foundational_chat_agents', first: 20 })

        expect_graphql_errors_to_be_empty

        # Without both states the spec this fixture exists for silently stops
        # testing anything.
        archived_flags = graphql_data.dig('duoWorkflowWorkflows', 'edges').pluck('node').pluck('archived')
        expect(archived_flags).to contain_exactly(true, false)
      end

      # The archived thread's own conversation, paired with the list entry above by
      # `archived_workflow_id`. `archived_thread_spec` hydrates from this instead of
      # building a chat log by hand, which is what retires the `ui_chat_log` ->
      # `duoMessages` mapping the MSW handler used to do.
      it "#{base_output_path}get_workflow_latest_checkpoint_archived.query.graphql.json" do
        archived = create_archived_workflow
        create(:duo_workflows_checkpoint,
          workflow: archived,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => simple_exchange(
                'Refactor this very old conversation', 'Here is what I found.'
              )
            }
          })

        query = get_graphql_query_as_string(
          'ai/graphql/get_workflow_latest_checkpoint.query.graphql', ee: true
        )
        post_graphql(query, current_user: user, variables: { workflowId: archived.to_global_id.to_s })
        expect_graphql_errors_to_be_empty

        # The whole point of this fixture: without the flag the spec stops testing
        # the inactive-thread behaviour and silently passes.
        node = graphql_data.dig('duoWorkflowWorkflows', 'nodes').first
        expect(node['archived']).to be(true)
        expect(node.dig('latestCheckpoint', 'duoMessages').size).to eq(2)
      end

      # Two plain active conversations for `conversation_lifecycle_spec`, which proves
      # it hydrates the thread the user picked and not the other one. Purpose-built
      # rather than reusing `get_workflow_latest_checkpoint`: that capture answers 'hi',
      # and asserting a thread rendered "hi" passes against almost any text. Both
      # sides need distinctive wording for the comparison to mean anything.
      it "#{base_output_path}get_workflow_latest_checkpoint_first_thread.query.graphql.json" do
        first_thread = create(:duo_workflows_workflow, :input_required, :agentic_chat,
          id: first_thread_workflow_id,
          user: user,
          project: project,
          goal: 'First thread question')
        create(:duo_workflows_checkpoint,
          workflow: first_thread,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => simple_exchange('First thread question', 'First thread answer')
            }
          })

        query = get_graphql_query_as_string(
          'ai/graphql/get_workflow_latest_checkpoint.query.graphql', ee: true
        )
        post_graphql(query, current_user: user,
          variables: { workflowId: first_thread.to_global_id.to_s })
        expect_graphql_errors_to_be_empty

        node = graphql_data.dig('duoWorkflowWorkflows', 'nodes').first
        expect(node['archived']).to be(false)
        expect(node.dig('latestCheckpoint', 'duoMessages').pluck('content'))
          .to eq(['First thread question', 'First thread answer'])
      end

      it "#{base_output_path}get_user_workflows_two_threads.query.graphql.json" do
        [
          [first_thread_workflow_id, 'First thread question', 'First thread answer'],
          [second_thread_workflow_id, 'Second thread question', 'Second thread answer']
        ].each do |id, goal, answer|
          thread = create(:duo_workflows_workflow, :input_required, :agentic_chat,
            id: id, user: user, project: project, goal: goal)
          # `stalled` is "created but has no checkpoints", and the UI disables a
          # stalled thread. Without a checkpoint this list would contradict the
          # per-thread captures pinned to the same ids, which record stalled: false.
          create(:duo_workflows_checkpoint, workflow: thread, project: project,
            checkpoint: { 'channel_values' => { 'ui_chat_log' => simple_exchange(goal, answer) } })
        end

        query = get_graphql_query_as_string('ai/graphql/get_user_workflow.query.graphql', ee: true)
        post_graphql(query, current_user: user,
          variables: { type: 'foundational_chat_agents', first: 20 })
        expect_graphql_errors_to_be_empty

        # Named for the two threads it adds, but the list is every agentic-chat
        # workflow this user has, so `workflow` is in it too. Pinned exactly here so
        # the third entry is visible to whoever reads the capture.
        titles = graphql_data.dig('duoWorkflowWorkflows', 'edges').pluck('node').pluck('title')
        expect(titles).to contain_exactly('First thread question', 'Second thread question',
          workflow.goal)
      end

      it "#{base_output_path}get_workflow_latest_checkpoint_second_thread.query.graphql.json" do
        second = create(:duo_workflows_workflow, :input_required, :agentic_chat,
          id: second_thread_workflow_id,
          user: user,
          project: project,
          goal: 'Second thread question')
        create(:duo_workflows_checkpoint,
          workflow: second,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => simple_exchange('Second thread question', 'Second thread answer')
            }
          })

        query = get_graphql_query_as_string(
          'ai/graphql/get_workflow_latest_checkpoint.query.graphql', ee: true
        )
        post_graphql(query, current_user: user, variables: { workflowId: second.to_global_id.to_s })
        expect_graphql_errors_to_be_empty

        node = graphql_data.dig('duoWorkflowWorkflows', 'nodes').first
        expect(node['archived']).to be(false)
        expect(node.dig('latestCheckpoint', 'duoMessages').pluck('content'))
          .to eq(['Second thread question', 'Second thread answer'])
      end

      # A conversation whose first turn already carries injected context, for
      # `additional_context_spec`'s de-duplication assertions. Those only hold if the
      # recorded context matches what the providers would produce at run time, so the
      # rule oids are the real blob oids and the page/project paths are the rules
      # project the spec mounts against. The spec pins `window.location` to match.
      it "#{base_output_path}get_workflow_latest_checkpoint_with_context.query.graphql.json" do
        contextual = create(:duo_workflows_workflow, :input_required, :agentic_chat,
          id: contextual_workflow_id,
          user: user,
          project: project,
          goal: 'Earlier question')
        create(:duo_workflows_checkpoint,
          workflow: contextual,
          project: project,
          checkpoint: {
            'channel_values' => {
              'ui_chat_log' => [
                {
                  'content' => 'Earlier question',
                  'message_type' => 'user',
                  'message_sub_type' => nil,
                  'status' => 'success',
                  'tool_info' => nil,
                  'timestamp' => '2026-05-19T10:00:00Z',
                  'correlation_id' => nil,
                  'message_id' => 'earlier-user',
                  'role' => 'user',
                  'component_name' => nil,
                  'subsession_id' => nil,
                  'additional_context' => [
                    {
                      'id' => 'page-context',
                      'category' => 'repository',
                      'content' =>
                        '<current_gitlab_page_url>http://test.host/group/project-with-rules' \
                        '</current_gitlab_page_url>',
                      'metadata' => {
                        'title' => 'Current page',
                        'enabled' => true,
                        'pagePath' => '/group/project-with-rules',
                        'projectPath' => 'group/project-with-rules'
                      }
                    },
                    {
                      'id' => 'agents-md-user-instructions',
                      'category' => 'user_rule',
                      'content' => "Apply the following project-specific AGENTS.md rules:\n" \
                        'content of AGENTS.md',
                      'metadata' => {
                        'title' => 'AGENTS.md',
                        'enabled' => true,
                        'oid' => rule_blob_oid('AGENTS.md')
                      }
                    },
                    {
                      'id' => 'chat-rules-user-instructions',
                      'category' => 'user_rule',
                      'content' => "Apply the following project-specific chat rules:\n" \
                        'content of .gitlab/duo/chat-rules.md',
                      'metadata' => {
                        'title' => 'chat-rules.md',
                        'enabled' => true,
                        'oid' => rule_blob_oid('.gitlab/duo/chat-rules.md')
                      }
                    }
                  ]
                },
                {
                  'content' => 'Earlier answer',
                  'message_type' => 'agent',
                  'message_sub_type' => nil,
                  'status' => 'success',
                  'tool_info' => nil,
                  'timestamp' => '2026-05-19T10:00:05Z',
                  'correlation_id' => nil,
                  'message_id' => 'earlier-agent',
                  'role' => 'assistant',
                  'component_name' => nil,
                  'subsession_id' => nil,
                  'additional_context' => nil
                }
              ]
            }
          })

        query = get_graphql_query_as_string(
          'ai/graphql/get_workflow_latest_checkpoint.query.graphql', ee: true
        )
        post_graphql(query, current_user: user,
          variables: { workflowId: contextual.to_global_id.to_s })
        expect_graphql_errors_to_be_empty

        # The oids are what a later turn de-duplicates against, so they have to be the
        # ones `getRuleContent` reports.
        context = graphql_data.dig('duoWorkflowWorkflows', 'nodes', 0, 'latestCheckpoint',
          'duoMessages', 0, 'additionalContext')
        expect(context.pluck('id')).to eq(
          %w[page-context agents-md-user-instructions chat-rules-user-instructions]
        )
      end

      it "#{base_output_path}get_ai_chat_context_presets.query.graphql.json" do
        query = get_graphql_query_as_string(
          'ai/graphql/get_ai_chat_context_presets.query.graphql', ee: true
        )

        post_graphql(query, current_user: user, variables: {
          projectId: project.to_global_id.to_s,
          url: '',
          questionCount: 4
        })

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_flow_status.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/get_flow_status.query.graphql', ee: true)

        post_graphql(query, current_user: user, variables: { id: workflow.to_global_id.to_s })

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_gitlab_credits_status.query.graphql.json" do
        # rubocop:disable RSpec/AnyInstanceOf -- required to stub this service
        allow_any_instance_of(::Gitlab::Llm::DuoChat).to receive(:credits_available?).and_return(true)
        allow_any_instance_of(::Gitlab::Llm::DuoChat).to receive(:usage_billing_forbidden?).and_return(false)
        # rubocop:enable RSpec/AnyInstanceOf

        query = get_graphql_query_as_string(
          'ai/graphql/get_gitlab_credits_status.query.graphql', ee: true
        )

        post_graphql(query, current_user: user, variables: { namespaceId: group.to_global_id.to_s })

        expect_graphql_errors_to_be_empty
      end

      # Shared by both `getAiChatAvailableModels` fixtures, which differ only in
      # whether the resolved feature setting pins a model.
      #
      # FetchModelDefinitionsService makes an HTTP call to the AI gateway, so it
      # returns the definitions baked into the factory instead; and
      # FeatureSettingSelectionService branches on SaaS vs self-managed, so it
      # returns the record outright rather than resolving it per environment.
      def stub_available_models(feature_setting)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, anything).and_return(true)

        allow_next_instance_of(::Ai::ModelSelection::FetchModelDefinitionsService) do |svc|
          allow(svc).to receive(:execute)
            .and_return(ServiceResponse.success(payload: agentic_chat_feature_setting.model_definitions))
        end

        allow_next_instance_of(::Ai::FeatureSettingSelectionService) do |svc|
          allow(svc).to receive(:execute).and_return(ServiceResponse.success(payload: feature_setting))
        end
      end

      def post_available_models_query
        query = get_graphql_query_as_string(
          'ai/graphql/get_ai_chat_available_models.query.graphql', ee: true
        )

        post_graphql(query, current_user: user, variables: { rootNamespaceId: group.to_global_id.to_s })
      end

      it "#{base_output_path}get_ai_chat_available_models.query.graphql.json" do
        stub_available_models(agentic_chat_feature_setting)

        post_available_models_query

        expect_graphql_errors_to_be_empty
      end

      # A second `getAiChatAvailableModels` fixture without a pinned model.
      # `isModelSelectionDisabled` returns `Boolean(pinnedModel)`, so the fixture
      # above (which pins a model on purpose) renders the dropdown disabled and
      # cannot drive a model-selection test.
      it "#{base_output_path}get_ai_chat_available_models_unpinned.query.graphql.json" do
        # Built rather than created: the namespace/feature pair is unique and
        # `agentic_chat_feature_setting` already owns it. The selection service is
        # stubbed, so the record never needs to be persisted.
        stub_available_models(
          build(:ai_namespace_feature_setting,
            namespace: group,
            feature: :duo_agent_platform_agentic_chat,
            offered_model_ref: nil,
            offered_model_name: nil)
        )

        post_available_models_query

        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('aiChatAvailableModels', 'pinnedModel')).to be_nil
      end

      it "#{base_output_path}get_rule_content.query.graphql.json" do
        query = get_graphql_query_as_string('ai/graphql/rule_content.query.graphql', ee: true)

        post_graphql(query, current_user: user, variables: {
          projectPath: rules_project.full_path,
          paths: ['AGENTS.md', '.gitlab/duo/chat-rules.md']
        })

        expect_graphql_errors_to_be_empty

        # `RuleContextProvider.fetchProjectRules` matches on the basename, so the
        # fixture is only useful if the resolver returns one too.
        blob_names = graphql_data.dig('project', 'repository', 'blobs', 'nodes').pluck('name')
        expect(blob_names).to contain_exactly('AGENTS.md', 'chat-rules.md')
      end

      # Sending a prompt creates a workflow before it opens the socket. The MSW
      # handler has to mint ids per test, but the *shape* of the payload comes from
      # here so it cannot drift from the schema.
      it "#{base_output_path}create_ai_duo_workflow.mutation.graphql.json" do
        # Creating a workflow probes CustomersDot for an entitlement. The fixture
        # only cares about the response shape, so let the probe succeed.
        stub_request(:head, %r{/api/v1/consumers/resolve}).to_return(status: 200, body: '')

        # CreateWorkflowService resolves the settings container from the user's
        # default namespace, which is unset here; without it the foundational-agent
        # check short-circuits to "disabled for namespace".
        # rubocop:disable RSpec/AnyInstanceOf -- same reason as the User stubs above
        allow_any_instance_of(User).to receive(:duo_foundational_agents_container).and_return(group)
        # rubocop:enable RSpec/AnyInstanceOf

        mutation = get_graphql_query_as_string('ai/graphql/duo_workflow.mutation.graphql', ee: true)

        post_graphql(mutation, current_user: user, variables: {
          projectId: project.to_global_id.to_s,
          goal: 'Hi from project one',
          workflowDefinition: 'chat',
          agentPrivileges: [2, 3, 7],
          preApprovedAgentPrivileges: [2]
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('aiDuoWorkflowCreate', 'workflow', 'id')).to be_present
        expect(graphql_data.dig('aiDuoWorkflowCreate', 'errors')).to be_empty
      end

      # Deleting targets a throwaway workflow: `workflow` backs the checkpoint and
      # user-list fixtures above and must survive.
      it "#{base_output_path}delete_duo_workflows_workflow.mutation.graphql.json" do
        deletable = create(:duo_workflows_workflow, :agentic_chat, user: user, project: project,
          goal: 'Conversation to delete')

        mutation = get_graphql_query_as_string('ai/graphql/delete_agentic_workflow.mutation.graphql', ee: true)

        post_graphql(mutation, current_user: user, variables: {
          input: { workflowId: deletable.to_global_id.to_s }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data.dig('deleteDuoWorkflowsWorkflow', 'success')).to be(true)
      end

      it "#{base_output_path}get_agent_flow_config.query.graphql.json" do
        # The component only queries this when `aiCatalogItemVersionId` is set.
        # Passing a non-existent ID causes the resolver to return null --
        # the same shape as the previous hardcoded mock.
        query = get_graphql_query_as_string(
          'ai/graphql/get_agent_flow_config.query.graphql', ee: true
        )

        post_graphql(query, current_user: user,
          variables: { agentVersionId: 'gid://gitlab/Ai::Catalog::ItemVersion/0' })

        expect_graphql_errors_to_be_empty
      end
    end
  end
end
