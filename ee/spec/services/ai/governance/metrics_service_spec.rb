# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::MetricsService, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:response) { ServiceResponse.success(payload: {}) }

  context 'when the container is a group' do
    subject(:execute) { described_class.new(group, current_user: user, timeframe: :last_7_days).execute }

    context 'when ClickHouse is enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(true)
      end

      it 'dispatches to the ClickHouse service and returns its response' do
        expect_next_instance_of(Ai::Governance::ClickHouseMetricsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute).to eq(response)
      end
    end

    context 'when ClickHouse is not enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(false)
      end

      it 'dispatches to the Postgres service and returns its response' do
        expect_next_instance_of(Ai::Governance::PostgresqlMetricsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute).to eq(response)
      end
    end
  end

  context 'when the container is a project' do
    subject(:execute) { described_class.new(project, current_user: user, timeframe: :last_7_days).execute }

    context 'when ClickHouse is enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?)
          .with(project.project_namespace).and_return(true)
      end

      it 'dispatches to the ClickHouse service and returns its response' do
        expect_next_instance_of(Ai::Governance::ClickHouseMetricsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute).to eq(response)
      end
    end

    context 'when ClickHouse is not enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?)
          .with(project.project_namespace).and_return(false)
      end

      it 'dispatches to the Postgres service and returns its response' do
        expect_next_instance_of(Ai::Governance::PostgresqlMetricsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute).to eq(response)
      end
    end
  end

  context 'with connected_agents_limit' do
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:sub_project) { create(:project, group: subgroup) }
    let_it_be(:outside_project) { create(:project) }
    let_it_be(:alice) { create(:user) }
    let_it_be(:bob) { create(:user) }

    # claude-code: two machines for alice on one project, one revoked machine for bob elsewhere
    let_it_be(:alice_laptop) do
      create(:ai_agent_identity, user: alice, project: sub_project, agent_type: 'claude-code')
    end

    let_it_be(:alice_ci) { create(:ai_agent_identity, user: alice, project: sub_project, agent_type: 'claude-code') }
    let_it_be(:bob_laptop) do
      create(:ai_agent_identity, user: bob, project: project, agent_type: 'claude-code',
        revoked_at: Time.utc(2026, 7, 1))
    end

    # opencode: one machine, its only session is before the window
    let_it_be(:bob_opencode) { create(:ai_agent_identity, user: bob, project: sub_project, agent_type: 'opencode') }
    # outside the hierarchy: must never be counted
    let_it_be(:outside_identity) do
      create(:ai_agent_identity, user: bob, project: outside_project, agent_type: 'opencode')
    end

    let(:backend_response) { ServiceResponse.success(payload: { sessions: {} }) }

    before_all do
      create(:duo_workflows_workflow, :external, project: sub_project, user: alice,
        agent_identity_id: alice_laptop.id, created_at: Time.utc(2026, 7, 1, 10))
      create(:duo_workflows_workflow, :external, project: sub_project, user: alice,
        agent_identity_id: alice_ci.id, created_at: Time.utc(2026, 7, 2, 10))
      # before the window: counts for last_session_at, not for session_count
      create(:duo_workflows_workflow, :external, project: project, user: bob,
        agent_identity_id: bob_laptop.id, created_at: Time.utc(2026, 6, 10, 10))
      create(:duo_workflows_workflow, :external, project: sub_project, user: bob, agent_type: 'opencode',
        agent_identity_id: bob_opencode.id, created_at: Time.utc(2026, 6, 20, 9))
      create(:duo_workflows_workflow, :external, project: outside_project, user: bob, agent_type: 'opencode',
        agent_identity_id: outside_identity.id, created_at: Time.utc(2026, 7, 2, 12))
    end

    around do |example|
      travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(false)
      allow_next_instance_of(Ai::Governance::PostgresqlMetricsService) do |service|
        allow(service).to receive(:execute).and_return(backend_response)
      end
    end

    def connected_agents(container, **options)
      described_class.new(container, current_user: user, timeframe: :last_7_days, connected_agents_limit: 5, **options)
        .execute.payload[:connected_agents]
    end

    it 'adds one row per agent type in the hierarchy, most registered machines first', :aggregate_failures do
      expect(connected_agents(group)).to eq([
        {
          agent_type: 'claude-code', identity_count: 3, active_count: 2, revoked_count: 1, user_count: 2,
          session_count: 2, last_session_at: Time.utc(2026, 7, 2, 10)
        },
        {
          agent_type: 'opencode', identity_count: 1, active_count: 1, revoked_count: 0, user_count: 1,
          session_count: 0, last_session_at: Time.utc(2026, 6, 20, 9)
        }
      ])
    end

    it 'keeps the rest of the backend payload' do
      payload = described_class.new(group, current_user: user, timeframe: :last_7_days,
        connected_agents_limit: 5).execute.payload

      expect(payload.keys).to eq(%i[sessions connected_agents])
    end

    it 'caps the rows at the limit' do
      rows = described_class.new(group, current_user: user, timeframe: :last_7_days, connected_agents_limit: 1)
        .execute.payload[:connected_agents]

      expect(rows.map { |row| row[:agent_type] }).to eq(%w[claude-code])
    end

    it 'resolves in two queries regardless of how many agent types exist' do
      recorder = ActiveRecord::QueryRecorder.new { connected_agents(group) }

      expect(recorder.count).to eq(2)
    end

    it 'scopes a project container to that project', :aggregate_failures do
      rows = connected_agents(sub_project).map { |row| row.slice(:agent_type, :identity_count, :revoked_count) }

      expect(rows).to eq([
        { agent_type: 'claude-code', identity_count: 2, revoked_count: 0 },
        { agent_type: 'opencode', identity_count: 1, revoked_count: 0 }
      ])
    end

    it 'returns an empty list for a container without registered agents' do
      expect(connected_agents(create(:group))).to eq([])
    end

    it 'returns an empty list for INTERNAL_DAP without querying identities' do
      expect(Ai::ExternalAgents::AgentIdentity).not_to receive(:in_namespace_hierarchy)

      expect(connected_agents(group, agent_class: :internal_dap)).to eq([])
    end

    it 'leaves the payload untouched when no limit is given' do
      payload = described_class.new(group, current_user: user, timeframe: :last_7_days).execute.payload

      expect(payload).not_to have_key(:connected_agents)
    end
  end

  context 'when an agent class is given' do
    subject(:execute) do
      described_class.new(group, current_user: user, timeframe: :last_7_days, agent_class: :external).execute
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(false)
    end

    it 'forwards the agent class to the backend service' do
      backend = instance_double(Ai::Governance::PostgresqlMetricsService, execute: response)

      expect(Ai::Governance::PostgresqlMetricsService).to receive(:new)
        .with(group, hash_including(agent_class: :external)).and_return(backend)

      expect(execute).to eq(response)
    end
  end
end
