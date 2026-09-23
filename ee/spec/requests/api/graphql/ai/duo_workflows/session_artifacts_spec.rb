# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying session artifacts for a group', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:project2) { create(:project, group: group) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_member) { create(:user) }

  # The duoWorkflowSessionArtifacts field requires :read_agent_artifacts, a
  # custom ability granted via member roles (requires the custom_roles license).
  let_it_be(:owner_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:owner_membership) do
    create(:group_member, :guest, member_role: owner_role, user: owner, group: group)
  end

  let_it_be(:workflow1) { create(:duo_workflows_workflow, project: project, user: owner) }
  let_it_be(:workflow2) { create(:duo_workflows_workflow, project: project2, user: owner, agent_type: 'claude-code') }

  # Fixed reference point so that relative timestamps used in artifact creation
  # and in filter parameters are consistent across `let_it_be` (before(:all))
  # and per-example evaluation, avoiding boundary-condition flakiness.
  let_it_be(:reference_time) { Time.current }

  # artifact1: created 2 hours before reference_time
  # artifact2: created 90 minutes before reference_time
  # A workflowCreatedAfter bound of 100 minutes before reference_time sits
  # between the two, so only artifact2 survives.
  let_it_be(:artifact1) do
    create(:duo_workflow_session_artifact,
      workflow: workflow1,
      workflow_definition: 'software_development',
      workflow_updated_at: reference_time - 2.hours,
      workflow_created_at: reference_time - 2.hours)
  end

  let_it_be(:artifact2) do
    create(:duo_workflow_session_artifact,
      workflow: workflow2,
      workflow_definition: 'chat',
      workflow_updated_at: reference_time - 1.hour,
      workflow_created_at: reference_time - 90.minutes)
  end

  let(:current_user) { owner }
  let(:query) do
    <<~GRAPHQL
      query {
        group(fullPath: "#{group.full_path}") {
          duoWorkflowSessionArtifacts(first: 10) {
            count
            nodes {
              id
              workflowDefinition
              agentType
              webPath
              downloadPath
              auditEventsCount
              workflowCreatedAt
              project {
                id
                fullPath
              }
              triggeredBy {
                id
                username
              }
            }
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
          }
        }
      }
    GRAPHQL
  end

  subject(:session_artifacts) do
    graphql_data.dig('group', 'duoWorkflowSessionArtifacts')
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
    stub_feature_flags(agent_artifacts_page: true)
  end

  it 'returns session artifacts for the group', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_nil
    expect(session_artifacts['count']).to eq(2)
  end

  it 'returns artifacts ordered most recently updated first' do
    post_graphql(query, current_user: current_user)

    ids = session_artifacts['nodes'].pluck('id')
    expect(ids).to eq([workflow2.to_global_id.to_s, workflow1.to_global_id.to_s])
  end

  it 'returns the correct field values for each node', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    node = session_artifacts['nodes'].first
    expect(node['id']).to eq(workflow2.to_global_id.to_s)
    expect(node['workflowDefinition']).to eq('chat')
    expect(node['agentType']).to eq('claude-code')
    expect(session_artifacts['nodes'].last['agentType']).to be_nil
    expect(node['webPath']).to include(workflow2.id.to_s)
    expect(node['downloadPath']).to eq(
      download_project_security_agent_artifact_path(project2, workflow2.id)
    )
    expect(node['auditEventsCount']).to eq(0)
    expect(node['project']['fullPath']).to eq(project2.full_path)
    expect(node['triggeredBy']['username']).to eq(owner.username)
  end

  it 'avoids N+1 queries when loading users' do
    post_graphql(query, current_user: current_user)
    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

    extra_user = create(:user)
    extra_workflow = create(:duo_workflows_workflow, project: project, user: extra_user)
    create(:duo_workflow_session_artifact, workflow: extra_workflow,
      workflow_definition: 'chat', workflow_updated_at: 30.minutes.ago)

    expect { post_graphql(query, current_user: current_user) }
      .not_to exceed_query_limit(control)
  end

  context 'when ClickHouse is disabled (PostgreSQL path)' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    context 'with triggeredByUserId filter' do
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, triggeredByUserId: "#{owner.to_global_id}") {
                count
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'returns only artifacts triggered by the given user', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        ids = session_artifacts['nodes'].pluck('id')
        expect(ids).to contain_exactly(workflow1.to_global_id.to_s, workflow2.to_global_id.to_s)
      end
    end

    context 'with not: { triggeredByUserId } filter' do
      let_it_be(:other_user) { create(:user) }
      let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: other_user) }
      let_it_be(:other_artifact) do
        create(:duo_workflow_session_artifact, workflow: other_workflow, workflow_updated_at: 30.minutes.ago)
      end

      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, not: { triggeredByUserId: "#{owner.to_global_id}" }) {
                count
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'excludes artifacts triggered by the given user', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        ids = session_artifacts['nodes'].pluck('id')
        expect(ids).to contain_exactly(other_workflow.to_global_id.to_s)
      end
    end

    context 'with workflowDefinition filter' do
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, workflowDefinition: "chat") {
                count
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'returns only artifacts with the matching definition', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        ids = session_artifacts['nodes'].pluck('id')
        expect(ids).to contain_exactly(workflow2.to_global_id.to_s)
      end
    end

    context 'with workflowCreatedAfter filter' do
      # Bound sits between artifact1 (created 2h before reference_time) and
      # artifact2 (created 90min before reference_time), so only artifact2 survives.
      let(:after_bound) { (reference_time - 100.minutes).iso8601 }

      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, workflowCreatedAfter: "#{after_bound}") {
                count
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'returns only artifacts created on or after the bound', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        ids = session_artifacts['nodes'].pluck('id')
        expect(ids).to contain_exactly(workflow2.to_global_id.to_s)
      end
    end

    context 'with projectPath filter' do
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, projectPath: "#{project.full_path}") {
                count
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'returns only artifacts belonging to the given project', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        ids = session_artifacts['nodes'].pluck('id')
        expect(ids).to contain_exactly(workflow1.to_global_id.to_s)
      end
    end
  end

  # `workflow1` runs on the Duo Agent Platform (NULL agent_type) and `workflow2`
  # is an externally connected agent (`claude-code`), so the shared fixtures
  # already cover both classes.
  context 'when filtering by agentClass on the PostgreSQL path' do
    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            duoWorkflowSessionArtifacts(first: 10, agentClass: #{agent_class}) {
              nodes { id }
            }
          }
        }
      GRAPHQL
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    context 'with EXTERNAL' do
      let(:agent_class) { 'EXTERNAL' }

      it 'returns only externally-connected agent sessions', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(session_artifacts['nodes'].pluck('id')).to contain_exactly(workflow2.to_global_id.to_s)
      end
    end

    context 'with INTERNAL_DAP' do
      let(:agent_class) { 'INTERNAL_DAP' }

      it 'returns only DAP sessions', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(session_artifacts['nodes'].pluck('id')).to contain_exactly(workflow1.to_global_id.to_s)
      end
    end

    context 'with ALL' do
      let(:agent_class) { 'ALL' }

      it 'returns every session in the group', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(session_artifacts['nodes'].pluck('id'))
          .to contain_exactly(workflow1.to_global_id.to_s, workflow2.to_global_id.to_s)
      end
    end

    context 'when combined with workflowDefinition' do
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(first: 10, agentClass: EXTERNAL, workflowDefinition: "chat") {
                nodes { id }
              }
            }
          }
        GRAPHQL
      end

      it 'returns only sessions matching both filters', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(session_artifacts['nodes'].pluck('id')).to contain_exactly(workflow2.to_global_id.to_s)
      end
    end
  end

  context 'when the user is not a member of the group' do
    let(:current_user) { non_member }

    it 'returns an empty list' do
      post_graphql(query, current_user: current_user)

      expect(session_artifacts).to be_nil
    end
  end

  context 'when the agent_artifacts_page feature flag is disabled' do
    before do
      stub_feature_flags(agent_artifacts_page: false)
    end

    it 'returns no artifacts', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to be_nil
      expect(session_artifacts['nodes']).to be_empty
      expect(session_artifacts['count']).to eq(0)
    end
  end

  context 'with pagination' do
    def paginated_query(after: nil)
      after_arg = after ? %(, after: "#{after}") : ''

      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            duoWorkflowSessionArtifacts(first: 1#{after_arg}) {
              count
              nodes { id }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
      GRAPHQL
    end

    let(:query) { paginated_query }

    # Reads the current response fresh; the `session_artifacts` subject memoizes
    # the first response and cannot be reused across paginated requests.
    def fetch_page(after: nil)
      post_graphql(paginated_query(after: after), current_user: current_user)
      graphql_data_at(:group, :duo_workflow_session_artifacts)
    end

    it 'returns the first page with correct pagination info', :aggregate_failures do
      page = fetch_page

      expect(page['count']).to eq(2)
      expect(page['nodes'].pluck('id')).to eq([workflow2.to_global_id.to_s])
      expect(page['pageInfo']['hasNextPage']).to be(true)
      expect(page['pageInfo']['endCursor']).to be_present
    end

    it 'paginates through every artifact in order using the end cursor', :aggregate_failures do
      page1 = fetch_page
      expect(page1['nodes'].pluck('id')).to eq([workflow2.to_global_id.to_s])

      page2 = fetch_page(after: page1.dig('pageInfo', 'endCursor'))
      expect(page2['nodes'].pluck('id')).to eq([workflow1.to_global_id.to_s])
      expect(page2['pageInfo']['hasNextPage']).to be(false)
    end
  end

  context 'with auditEventsCount' do
    let_it_be(:audit_events) do
      create_list(:audit_events_ai_audit_event, 3,
        target_project: project, user: owner, workflow_id: workflow1.id)
    end

    it 'returns the correct audit event count per artifact', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      node1 = session_artifacts['nodes'].find { |n| n['id'] == workflow1.to_global_id.to_s }
      node2 = session_artifacts['nodes'].find { |n| n['id'] == workflow2.to_global_id.to_s }

      expect(node1['auditEventsCount']).to eq(3)
      expect(node2['auditEventsCount']).to eq(0)
    end

    it 'avoids N+1 queries when loading audit event counts' do
      post_graphql(query, current_user: current_user)
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      extra_workflow = create(:duo_workflows_workflow, project: project, user: owner)
      create(:duo_workflow_session_artifact, workflow: extra_workflow,
        workflow_definition: 'chat', workflow_updated_at: 30.minutes.ago)

      expect { post_graphql(query, current_user: current_user) }
        .not_to exceed_query_limit(control)
    end
  end

  describe 'creditsUsed', :click_house do
    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            duoWorkflowSessionArtifacts(first: 10) {
              nodes {
                id
                creditsUsed
              }
            }
          }
        }
      GRAPHQL
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

      # `creditsUsed` only reads ClickHouse when analytics is globally enabled, which also
      # switches the session list onto the ClickHouse-backed finder. Return both artifacts
      # directly to avoid depending on a seeded `siphon_duo_workflows_workflows` table.
      session_ch_finder = instance_double(
        ::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder,
        execute: ::Ai::DuoWorkflows::SessionArtifact.id_in([artifact1.id, artifact2.id])
      )
      allow(::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder)
        .to receive(:new).and_return(session_ch_finder)
    end

    def insert_credits(workflow_id, credits, updated_at)
      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO duo_workflow_session_enrichments (workflow_id, credits_used, updated_at)
        VALUES (#{workflow_id}, #{credits}, '#{updated_at.utc.strftime('%Y-%m-%d %H:%M:%S.%6N')}')
      SQL
    end

    def credits_for(workflow)
      session_artifacts['nodes']
        .find { |node| node['id'] == workflow.to_global_id.to_s }
        &.fetch('creditsUsed')
    end

    it 'returns the stored total' do
      insert_credits(workflow1.id, 12.5, 1.hour.ago)

      post_graphql(query, current_user: current_user)

      expect(credits_for(workflow1)).to eq(12.5)
    end

    it 'returns null for a session with no row rather than zero' do
      insert_credits(workflow1.id, 12.5, 1.hour.ago)

      post_graphql(query, current_user: current_user)

      expect(credits_for(workflow2)).to be_nil
    end

    it 'takes the newest row when duplicates have not merged yet' do
      insert_credits(workflow1.id, 5.0, 2.hours.ago)
      insert_credits(workflow1.id, 9.0, 1.minute.ago)

      post_graphql(query, current_user: current_user)

      expect(credits_for(workflow1)).to eq(9.0)
    end

    it 'issues one ClickHouse query for the whole page', :aggregate_failures do
      insert_credits(workflow1.id, 1.0, 1.hour.ago)
      insert_credits(workflow2.id, 2.0, 1.hour.ago)

      expect(ClickHouse::Client).to receive(:select).once.and_call_original

      post_graphql(query, current_user: current_user)

      expect(credits_for(workflow1)).to eq(1.0)
      expect(credits_for(workflow2)).to eq(2.0)
    end

    context 'when ClickHouse analytics is disabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it 'returns null without querying ClickHouse', :aggregate_failures do
        expect(ClickHouse::Client).not_to receive(:select)

        post_graphql(query, current_user: current_user)

        expect(credits_for(workflow1)).to be_nil
        expect(credits_for(workflow2)).to be_nil
      end
    end

    # The field mount on GroupType carries `authorize: :read_agent_artifacts`, so
    # an unauthorized member gets the whole field nulled rather than an empty list.
    context 'when the user lacks read_agent_artifacts' do
      let_it_be(:plain_guest) { create(:user, guest_of: group) }

      let(:current_user) { plain_guest }

      it 'returns no artifacts even when credit rows exist' do
        insert_credits(workflow1.id, 12.5, 1.hour.ago)

        post_graphql(query, current_user: current_user)

        expect(session_artifacts).to be_nil
      end
    end
  end

  describe 'workflowId filter and auditEvents field' do
    let_it_be(:chat_author) { create(:user) }
    let_it_be(:chat_workflow) do
      create(:duo_workflows_workflow, :agentic_chat, project: project, user: chat_author)
    end

    let_it_be(:chat_artifact) do
      create(:duo_workflow_session_artifact,
        workflow: chat_workflow,
        workflow_definition: 'chat',
        workflow_updated_at: 10.minutes.ago)
    end

    let_it_be(:chat_event) do
      create(:audit_events_ai_audit_event,
        target_project: project, user: chat_author, workflow_id: chat_workflow.id,
        event_name: 'ai_agent_session_started')
    end

    let_it_be(:auditor) { create(:user, :auditor) }
    let_it_be(:level_maintainer) { create(:user, maintainer_of: group) }
    let_it_be(:level_guest) { create(:user, guest_of: group) }

    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            duoWorkflowSessionArtifacts(workflowId: "#{chat_workflow.to_global_id}") {
              nodes {
                id
                auditEvents {
                  nodes { eventName }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'returns only the single filtered session', :aggregate_failures do
      post_graphql(query, current_user: owner)

      nodes = session_artifacts['nodes']
      expect(nodes.length).to eq(1)
      expect(nodes.first['id']).to eq(chat_workflow.to_global_id.to_s)
    end

    context 'when the reviewer is a group Owner but not the chat author' do
      let_it_be(:reviewer) { create(:user) }

      before_all { group.add_owner(reviewer) }

      it 'returns the chat session audit events without a workflow error', :aggregate_failures do
        post_graphql(query, current_user: reviewer)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil

        event_names = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes').pluck('eventName')
        expect(event_names).to contain_exactly('ai_agent_session_started')
      end
    end

    context 'when ClickHouse is globally enabled' do
      let(:ch_event_rows) do
        [
          {
            'id' => '00000000-0000-0000-0000-000000000001',
            'cloud_event_id' => '00000000-0000-0000-0000-000000000001',
            'event_name' => 'ai_agent_session_started',
            'created_at' => 1.minute.ago.utc.strftime('%Y-%m-%d %H:%M:%S'),
            'workflow_id' => chat_workflow.id.to_s,
            'ip_address' => '203.0.113.7',
            'details' => '{}',
            'author_id' => chat_author.id
          }
        ]
      end

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

        # The session list is served from the ClickHouse-backed finder when CH is
        # globally enabled. Return the single chat artifact directly to avoid
        # depending on a seeded `siphon_duo_workflows_workflows` table.
        session_ch_finder = instance_double(
          ::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder,
          execute: ::Ai::DuoWorkflows::SessionArtifact.id_in(chat_artifact.id)
        )
        allow(::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder)
          .to receive(:new).and_return(session_ch_finder)

        events_ch_finder = instance_double(
          ::AuditEvents::AiAuditEvents::ClickHouseFinder, execute: ch_event_rows
        )
        allow(::AuditEvents::AiAuditEvents::ClickHouseFinder)
          .to receive(:new).and_return(events_ch_finder)
      end

      it 'loads chat audit events through the ClickHouse path', :aggregate_failures do
        post_graphql(query, current_user: owner)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil

        event_names = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes').pluck('eventName')
        expect(event_names).to eq(%w[ai_agent_session_started])
      end
    end

    context 'when the user lacks read_compliance_dashboard' do
      let_it_be(:developer) { create(:user, developer_of: group) }

      it 'returns no session and no events', :aggregate_failures do
        post_graphql(query, current_user: developer)

        expect(response).to have_gitlab_http_status(:success)
        expect(session_artifacts).to be_nil
      end
    end

    context 'for roles that can read agent artifacts' do
      using RSpec::Parameterized::TableSyntax

      where(:level, :viewer) do
        'group Owner'      | ref(:owner)
        'instance Auditor' | ref(:auditor)
      end

      with_them do
        it 'returns the session audit events' do
          post_graphql(query, current_user: viewer)

          expect(response).to have_gitlab_http_status(:success)
          event_names = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes').pluck('eventName')
          expect(event_names).to contain_exactly('ai_agent_session_started')
        end
      end
    end

    context 'for roles that cannot read agent artifacts' do
      using RSpec::Parameterized::TableSyntax

      where(:level, :viewer) do
        'Maintainer' | ref(:level_maintainer)
        'Guest'      | ref(:level_guest)
        'non-member' | ref(:non_member)
      end

      with_them do
        it 'does not return session artifacts' do
          post_graphql(query, current_user: viewer)

          expect(response).to have_gitlab_http_status(:success)
          expect(session_artifacts).to be_nil
        end
      end
    end

    describe 'humanAuthor field on audit events' do
      let_it_be(:human_user) { create(:user) }

      let(:human_author_query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              duoWorkflowSessionArtifacts(workflowId: "#{chat_workflow.to_global_id}") {
                nodes {
                  id
                  auditEvents {
                    nodes {
                      humanAuthor { id username }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL
      end

      context 'on the Postgres path' do
        before do
          allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        context 'when details contains human_author_id' do
          let_it_be(:event_with_human) do
            create(:audit_events_ai_audit_event,
              target_project: project, user: chat_author, workflow_id: chat_workflow.id,
              details: { 'human_author_id' => human_user.id })
          end

          it 'returns the persisted human user', :aggregate_failures do
            post_graphql(human_author_query, current_user: owner)

            expect(response).to have_gitlab_http_status(:success)
            expect(graphql_errors).to be_nil

            event_nodes = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes')
            human_author_node = event_nodes.find { |n| n['humanAuthor'].present? }&.dig('humanAuthor')
            expect(human_author_node).to include(
              'id' => human_user.to_global_id.to_s,
              'username' => human_user.username
            )
          end
        end

        context 'when details does not contain human_author_id' do
          it 'returns null for humanAuthor', :aggregate_failures do
            post_graphql(human_author_query, current_user: owner)

            expect(response).to have_gitlab_http_status(:success)
            expect(graphql_errors).to be_nil

            event_nodes = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes')
            expect(event_nodes.map { |n| n['humanAuthor'] }).to all(be_nil)
          end
        end
      end

      context 'on the ClickHouse path' do
        before do
          allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

          session_ch_finder = instance_double(
            ::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder,
            execute: ::Ai::DuoWorkflows::SessionArtifact.id_in(chat_artifact.id)
          )
          allow(::Ai::DuoWorkflows::SessionArtifacts::ClickHouseFinder)
            .to receive(:new).and_return(session_ch_finder)

          allow(::AuditEvents::AiAuditEvents::ClickHouseFinder)
            .to receive(:new).and_return(events_ch_finder)
        end

        context 'when details JSON contains human_author_id' do
          let(:events_ch_finder) do
            instance_double(
              ::AuditEvents::AiAuditEvents::ClickHouseFinder,
              execute: [
                {
                  'id' => '00000000-0000-0000-0000-000000000002',
                  'cloud_event_id' => '00000000-0000-0000-0000-000000000002',
                  'event_name' => 'ai_agent_session_started',
                  'created_at' => 1.minute.ago.utc.strftime('%Y-%m-%d %H:%M:%S'),
                  'workflow_id' => chat_workflow.id.to_s,
                  'ip_address' => '203.0.113.7',
                  'details' => %({"human_author_id":#{human_user.id}}),
                  'author_id' => chat_author.id
                }
              ]
            )
          end

          it 'returns the persisted human user', :aggregate_failures do
            post_graphql(human_author_query, current_user: owner)

            expect(response).to have_gitlab_http_status(:success)
            expect(graphql_errors).to be_nil

            event_nodes = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes')
            expect(event_nodes.first['humanAuthor']).to include(
              'id' => human_user.to_global_id.to_s,
              'username' => human_user.username
            )
          end
        end

        context 'when details JSON does not contain human_author_id' do
          let(:events_ch_finder) do
            instance_double(
              ::AuditEvents::AiAuditEvents::ClickHouseFinder,
              execute: [
                {
                  'id' => '00000000-0000-0000-0000-000000000003',
                  'cloud_event_id' => '00000000-0000-0000-0000-000000000003',
                  'event_name' => 'ai_agent_session_started',
                  'created_at' => 1.minute.ago.utc.strftime('%Y-%m-%d %H:%M:%S'),
                  'workflow_id' => chat_workflow.id.to_s,
                  'ip_address' => '203.0.113.7',
                  'details' => '{}',
                  'author_id' => chat_author.id
                }
              ]
            )
          end

          it 'returns null for humanAuthor', :aggregate_failures do
            post_graphql(human_author_query, current_user: owner)

            expect(response).to have_gitlab_http_status(:success)
            expect(graphql_errors).to be_nil

            event_nodes = session_artifacts.dig('nodes', 0, 'auditEvents', 'nodes')
            expect(event_nodes.first['humanAuthor']).to be_nil
          end
        end
      end
    end
  end
end
