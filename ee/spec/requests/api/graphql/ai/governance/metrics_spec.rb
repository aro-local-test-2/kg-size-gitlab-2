# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying aiGovernanceMetrics', feature_category: :compliance_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  # :read_agent_artifacts is a custom ability granted via member roles (requires
  # the custom_roles license), mirroring the duoWorkflowSessionArtifacts field on
  # the same dashboard. A group-level role cascades to the group's projects.
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:authorized_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :guest, member_role: member_role, user: authorized_user, group: group)
  end

  let_it_be(:unauthorized_user) { create(:user) }

  # 2 current-window sessions (same definition, so agents < sessions), 1
  # previous-window session, and 1 chat session counted in sessions but
  # guarded out of the agents KPI.
  let_it_be(:current_session_1) do
    create(:duo_workflows_workflow, project: project, user: authorized_user,
      workflow_definition: 'software_development', created_at: Time.utc(2026, 7, 1, 10))
  end

  let_it_be(:current_session_2) do
    create(:duo_workflows_workflow, project: project, user: authorized_user,
      workflow_definition: 'software_development', created_at: Time.utc(2026, 7, 1, 12))
  end

  let_it_be(:previous_session) do
    create(:duo_workflows_workflow, project: project, user: authorized_user,
      workflow_definition: 'software_development', created_at: Time.utc(2026, 6, 20))
  end

  let_it_be(:chat_session) do
    create(:duo_workflows_workflow, project: project, user: authorized_user,
      workflow_definition: 'chat', created_at: Time.utc(2026, 7, 1))
  end

  # older than the cumulative lookback and from another user: would seed a second
  # agent instance if the cumulative series read all history
  let_it_be(:pre_lookback_session) do
    create(:duo_workflows_workflow, project: project, user: create(:user),
      workflow_definition: 'software_development', created_at: Time.utc(2026, 5, 20))
  end

  let(:timeframe) { :LAST_7_DAYS }

  let(:metrics_fields) do
    <<~FIELDS
      sessions { count previousCount trend { bucketStart count } }
      agents { count previousCount trend { bucketStart count } }
    FIELDS
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  shared_examples 'an aiGovernanceMetrics field' do
    let(:query_args) { { timeframe: timeframe } }

    let(:query) do
      graphql_query_for(parent_type, { full_path: container.full_path },
        query_graphql_field(:ai_governance_metrics, query_args, metrics_fields))
    end

    let(:metrics) { graphql_data_at(parent_type, :ai_governance_metrics) }

    context 'when the user is authorized and the feature flag is enabled' do
      it 'returns session and agent KPIs from the PostgreSQL path', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(metrics['sessions']).to include('count' => 3, 'previousCount' => 1)
        expect(metrics['agents']).to include('count' => 1, 'previousCount' => 1)
      end

      context 'with an explicit INTERNAL_DAP agentClass' do
        let(:query_args) { { timeframe: timeframe, agent_class: :INTERNAL_DAP } }

        it 'returns the same KPIs as the default (ALL) today', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          expect(metrics['sessions']).to include('count' => 3, 'previousCount' => 1)
          expect(metrics['agents']).to include('count' => 1, 'previousCount' => 1)
        end
      end

      context 'with an EXTERNAL agentClass' do
        let(:query_args) { { timeframe: timeframe, agent_class: :EXTERNAL } }

        it 'returns zero counts with a full bucket-shaped trend', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          expect(metrics['sessions']).to include('count' => 0, 'previousCount' => 0)
          expect(metrics['agents']).to include('count' => 0, 'previousCount' => 0)

          trend = metrics.dig('sessions', 'trend')
          # 8 day-aligned buckets, every one present and zero-filled.
          expect(trend.length).to eq(8)
          expect(trend).to all(include('count' => 0))
        end
      end

      context 'with external sessions present' do
        # Three agent types in one environment, plus a repeat of the first type
        # in a different environment. Keyed on agent_type that is 3 instances;
        # keyed on environment it would be 2, so the counts discriminate.
        let_it_be(:external_sessions) do
          [
            ['claude_code', :ide],
            ['opencode', :ide],
            ['cursor', :ide],
            ['claude_code', :ambient]
          ].each_with_index.map do |(agent_type, environment), index|
            create(:duo_workflows_workflow, project: project, user: authorized_user,
              agent_type: agent_type, environment: environment,
              workflow_definition: 'software_development',
              created_at: Time.utc(2026, 7, 1, 13 + index))
          end
        end

        context 'with an EXTERNAL agentClass' do
          let(:query_args) { { timeframe: timeframe, agent_class: :EXTERNAL } }

          it 'counts external sessions and keys their agents on agent_type', :aggregate_failures do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors).to be_nil
            expect(metrics['sessions']).to include('count' => 4, 'previousCount' => 0)
            # claude_code, opencode and cursor. The second claude_code session is
            # the same agent instance even though its environment differs.
            expect(metrics['agents']).to include('count' => 3, 'previousCount' => 0)
          end
        end

        context 'with an INTERNAL_DAP agentClass' do
          let(:query_args) { { timeframe: timeframe, agent_class: :INTERNAL_DAP } }

          it 'excludes external sessions', :aggregate_failures do
            post_graphql(query, current_user: authorized_user)

            expect(metrics['sessions']).to include('count' => 3, 'previousCount' => 1)
            expect(metrics['agents']).to include('count' => 1, 'previousCount' => 1)
          end
        end

        it 'partitions agents so that ALL equals INTERNAL_DAP plus EXTERNAL', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(metrics['sessions']).to include('count' => 7)
          expect(metrics['agents']).to include('count' => 4)
        end
      end

      context 'with top user and project activity requested' do
        let_it_be(:second_user) { create(:user) }
        let_it_be(:second_user_session) do
          create(:duo_workflows_workflow, project: project, user: second_user,
            workflow_definition: 'software_development', created_at: Time.utc(2026, 7, 1, 14))
        end

        let(:metrics_fields) do
          <<~FIELDS
            sessions { count }
            topUsers { user { id username } sessionCount }
            topProjects { project { id fullPath } sessionCount }
          FIELDS
        end

        it 'ranks users and projects by session count', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(parent_type, :ai_governance_metrics, :top_users)).to eq([
            { 'user' => { 'id' => authorized_user.to_global_id.to_s, 'username' => authorized_user.username },
              'sessionCount' => 3 },
            { 'user' => { 'id' => second_user.to_global_id.to_s, 'username' => second_user.username },
              'sessionCount' => 1 }
          ])
          expect(graphql_data_at(parent_type, :ai_governance_metrics, :top_projects)).to eq([
            { 'project' => { 'id' => project.to_global_id.to_s, 'fullPath' => project.full_path },
              'sessionCount' => 4 }
          ])
        end

        it 'resolves the rankings in a fixed number of queries' do
          post_graphql(query, current_user: authorized_user)

          control = ActiveRecord::QueryRecorder.new do
            post_graphql(query, current_user: authorized_user)
          end

          create(:duo_workflows_workflow, project: create(:project, group: group), user: create(:user),
            workflow_definition: 'software_development', created_at: Time.utc(2026, 7, 1, 16))

          # Policy evaluation costs two queries (max access level, project
          # namespace) for the one project entering the ranking. Route lookups
          # are batch-loaded, so anything above the threshold is a regression.
          expect do
            post_graphql(query, current_user: authorized_user)
          end.not_to exceed_query_limit(control).with_threshold(2)
        end

        context 'with a limit argument' do
          let(:metrics_fields) { 'topUsers(limit: 1) { user { username } sessionCount }' }

          it 'caps the ranking' do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors).to be_nil
            expect(graphql_data_at(parent_type, :ai_governance_metrics, :top_users)).to eq([
              { 'user' => { 'username' => authorized_user.username }, 'sessionCount' => 3 }
            ])
          end
        end

        context 'with a limit above the maximum' do
          # 300 also exceeds the UInt8 ClickHouse placeholder, so it must
          # never size the ranking query. It cannot today: a limit that fails
          # its validator never reaches the resolver's lookahead (graphql-ruby
          # yields {} on argument coercion errors), so the ranking falls back
          # to the default size. This pins that behavior across gem upgrades.
          let(:metrics_fields) { 'topUsers(limit: 300) { sessionCount }' }

          it 'runs the ranking at the default size and returns a validation error',
            :aggregate_failures do
            expect(::Ai::Governance::MetricsService).to receive(:new)
              .with(anything, hash_including(
                top_users_limit: ::Ai::Governance::MetricsService::TOP_ACTIVITY_LIMIT))
              .and_call_original

            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors.first['message']).to include('less than or equal to 20')
          end
        end

        context 'with the same field aliased under different limits' do
          let(:metrics_fields) do
            <<~FIELDS
              topOne: topUsers(limit: 1) { sessionCount }
              topFive: topUsers(limit: 5) { sessionCount }
            FIELDS
          end

          it 'honors each alias limit', :aggregate_failures do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors).to be_nil
            expect(graphql_data_at(parent_type, :ai_governance_metrics, :top_one).size).to eq(1)
            expect(graphql_data_at(parent_type, :ai_governance_metrics, :top_five).size).to eq(2)
          end
        end
      end

      it 'does not compute the rankings when their fields are not selected' do
        expect(::Ai::Governance::MetricsService).to receive(:new)
          .with(anything, hash_including(top_users_limit: nil, top_projects_limit: nil, connected_agents_limit: nil))
          .and_call_original

        post_graphql(query, current_user: authorized_user)
      end

      context 'with cumulativeTrend selected' do
        let(:metrics_fields) do
          <<~FIELDS
            sessions { count cumulativeTrend { bucketStart count } }
            agents { cumulativeTrend { bucketStart count } }
          FIELDS
        end

        it 'returns running totals seeded with the lookback period before the window', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          sessions = metrics.dig('sessions', 'cumulativeTrend')
          agents = metrics.dig('agents', 'cumulativeTrend')

          # previous_session (2026-06-20) is inside the lookback and seeds the series;
          # pre_lookback_session (2026-05-20) is older than the lookback and is not counted
          expect(sessions.first['count']).to eq(1)
          expect(sessions.last['count']).to eq(4)
          # the only counted agent instance dates from previous_session; chat adds
          # none and the pre-lookback user's instance is not counted
          expect(agents.map { |point| point['count'] }).to all(eq(1))
        end
      end

      it 'does not compute cumulative trends when not selected' do
        expect(::Ai::Governance::MetricsService).to receive(:new)
          .with(anything, hash_including(cumulative_trend: false))
          .and_call_original

        post_graphql(query, current_user: authorized_user)
      end

      context 'with connected agents requested' do
        let_it_be(:laptop) { create(:ai_agent_identity, user: authorized_user, project: project) }
        let_it_be(:revoked_laptop) do
          create(:ai_agent_identity, user: authorized_user, project: project, revoked_at: Time.utc(2026, 7, 2))
        end

        let_it_be(:external_session) do
          create(:duo_workflows_workflow, :external, project: project, user: authorized_user,
            agent_identity_id: laptop.id, created_at: Time.utc(2026, 7, 2, 9))
        end

        let(:metrics_fields) do
          <<~FIELDS
            connectedAgents { agentType identityCount activeCount revokedCount userCount sessionCount lastSessionAt }
          FIELDS
        end

        it 'lists registered external agents by type', :aggregate_failures do
          expect(::Ai::Governance::MetricsService).to receive(:new)
            .with(anything, hash_including(connected_agents_limit: ::Ai::Governance::MetricsService::TOP_ACTIVITY_LIMIT))
            .and_call_original

          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(parent_type, :ai_governance_metrics, :connected_agents)).to eq([
            {
              'agentType' => 'claude-code', 'identityCount' => 2, 'activeCount' => 1, 'revokedCount' => 1,
              'userCount' => 1, 'sessionCount' => 1, 'lastSessionAt' => '2026-07-02T09:00:00Z'
            }
          ])
        end

        context 'with an INTERNAL_DAP agentClass' do
          let(:query_args) { { timeframe: timeframe, agent_class: :INTERNAL_DAP } }

          it 'returns an empty list' do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors).to be_nil
            expect(graphql_data_at(parent_type, :ai_governance_metrics, :connected_agents)).to eq([])
          end
        end

        context 'with an EXTERNAL agentClass' do
          let(:query_args) { { timeframe: timeframe, agent_class: :EXTERNAL } }

          it 'returns the same rows as ALL, since every registered agent is external', :aggregate_failures do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors).to be_nil
            rows = graphql_data_at(parent_type, :ai_governance_metrics, :connected_agents)
            expect(rows.map { |row| row['agentType'] }).to eq(%w[claude-code])
            expect(rows.first).to include('identityCount' => 2, 'sessionCount' => 1)
          end
        end

        context 'with a LAST_24_HOURS timeframe' do
          let(:timeframe) { :LAST_24_HOURS }

          it 'counts sessions inside the shorter window only, keeping the all-time last session' do
            post_graphql(query, current_user: authorized_user)

            row = graphql_data_at(parent_type, :ai_governance_metrics, :connected_agents).first
            # the only external session is on Jul 2 09:00, outside the 24h window ending Jul 3 15:30
            expect(row).to include('sessionCount' => 0, 'lastSessionAt' => '2026-07-02T09:00:00Z')
          end
        end

        context 'with a limit above the maximum' do
          let(:metrics_fields) { 'connectedAgents(limit: 300) { agentType }' }

          it 'returns a validation error' do
            post_graphql(query, current_user: authorized_user)

            expect(graphql_errors.first['message']).to include('less than or equal to 20')
          end
        end
      end

      it 'returns a full-length zero-filled trend for the timeframe', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        trend = metrics.dig('sessions', 'trend')

        # 8 day-aligned buckets from 2026-06-26 through 2026-07-03 (inclusive endpoints).
        expect(trend.length).to eq(8)
        expect(trend.sum { |point| point['count'] }).to eq(3)
      end

      context 'with a LAST_24_HOURS timeframe' do
        let(:timeframe) { :LAST_24_HOURS }

        it 'accepts the argument and returns hourly buckets' do
          post_graphql(query, current_user: authorized_user)

          # 25 hour-aligned buckets from 2026-07-02 15:00 through 2026-07-03 15:00 (inclusive).
          expect(metrics.dig('sessions', 'trend').length).to eq(25)
        end
      end
    end

    context 'when the metrics service fails' do
      before do
        allow_next_instance_of(::Ai::Governance::MetricsService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'backend unavailable'))
        end
      end

      it 'returns null rather than an empty-looking payload', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(metrics).to be_nil
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_dashboard: false)
      end

      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(metrics).to be_nil
      end
    end

    context 'when the user is not authorized' do
      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: unauthorized_user)

        expect(graphql_errors).to be_nil
        expect(metrics).to be_nil
      end
    end

    context 'when the user is anonymous' do
      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: nil)

        expect(graphql_errors).to be_nil
        expect(metrics).to be_nil
      end
    end
  end

  context 'for a group' do
    let(:parent_type) { :group }
    let(:container) { group }

    it_behaves_like 'an aiGovernanceMetrics field'
  end

  context 'for a project' do
    let(:parent_type) { :project }
    let(:container) { project }

    it_behaves_like 'an aiGovernanceMetrics field'
  end
end
