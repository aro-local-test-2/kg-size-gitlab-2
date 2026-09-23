# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ClickHouseMetricsService, :click_house,
  feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    insert_rows([
      { id: 1, definition: 'software_development', created_at: '2026-07-01 10:00:00', path: project_path },
      { id: 2, definition: 'software_development', created_at: '2026-07-01 12:00:00', path: project_path,
        environment: 2 },
      { id: 3, definition: 'convert_to_gitlab_ci', created_at: '2026-06-28 09:00:00', path: project_path },
      { id: 4, definition: 'software_development', created_at: '2026-06-20 09:00:00', path: project_path },
      { id: 5, definition: 'chat', created_at: '2026-07-01 09:00:00', path: project_path },
      { id: 6, definition: 'software_development', created_at: '2026-07-01 09:00:00', path: '0/999/' },
      { id: 7, definition: 'software_development', created_at: '2026-07-01 11:00:00', path: project_path,
        project_id: 12345 },
      # older than the cumulative lookback; another user, so it would mint an
      # extra agent instance if the seed read all history
      { id: 8, definition: 'software_development', created_at: '2026-05-20 09:00:00', path: project_path,
        user_id: 999_999 }
    ])
    # duplicate version of id 1 (siphon update) - must not double-count
    insert_rows([{ id: 1, definition: 'software_development', created_at: '2026-07-01 10:00:00',
                   path: project_path, replicated_at: '2026-07-02 00:00:00' }])
  end

  subject(:payload) { described_class.new(group, current_user: user, timeframe: timeframe).execute.payload }

  it 'counts deduplicated sessions of every definition, chat included', :aggregate_failures do
    expect(payload[:sessions][:count]).to eq(5)
    expect(payload[:sessions][:previous_count]).to eq(1)
  end

  it 'counts distinct agent instances', :aggregate_failures do
    # ids 1 and 3 share (user, project, environment) across two definitions =>
    # one instance; id 2 differs on environment => a second instance; id 7
    # differs only on project_id => a third instance.
    expect(payload[:agents][:count]).to eq(3)
    expect(payload[:agents][:previous_count]).to eq(1)
  end

  it 'returns a zero-filled ascending trend', :aggregate_failures do
    trend = payload[:sessions][:trend]

    # every timeframe bucket is present, in ascending order (matches bucket_starts exactly)
    expect(trend.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
    # populated bucket carries its count...
    expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 1) }[:count]).to eq(4)
    # ...and a bucket with no sessions is zero-filled rather than absent
    expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 2) }[:count]).to eq(0)
  end

  it 'omits cumulative trends unless requested', :aggregate_failures do
    expect(payload[:sessions]).not_to have_key(:cumulative_trend)
    expect(payload[:agents]).not_to have_key(:cumulative_trend)
  end

  context 'with cumulative trends requested' do
    subject(:payload) do
      described_class.new(group, current_user: user, timeframe: timeframe, cumulative_trend: true)
        .execute.payload
    end

    it 'returns running totals seeded with the lookback period before the window', :aggregate_failures do
      sessions = payload[:sessions][:cumulative_trend]
      agents = payload[:agents][:cumulative_trend]

      expect(sessions.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
      # id 4 (2026-06-20) predates the window and seeds every point; id 8
      # (2026-05-20) is older than the lookback and is not counted
      expect(sessions.first[:count]).to eq(1)
      expect(sessions.last[:count]).to eq(6)
      # ids 1/3/4 share one instance first seen before the window; ids 2 and 7
      # mint new instances on 2026-07-01; the chat row (id 5) adds none
      expect(agents.first[:count]).to eq(1)
      expect(agents.last[:count]).to eq(3)
    end
  end

  context 'with a project container' do
    subject(:payload) { described_class.new(project, current_user: user, timeframe: timeframe).execute.payload }

    it 'scopes by the project namespace traversal path' do
      expect(payload[:sessions][:count]).to eq(5)
    end
  end

  context 'with environments renamed in 18.6' do
    # ide (1) normalizes to chat (4), web (2) to ambient (5). Base row 1 is environment
    # NULL, row 2 is web (2). Adding ide, chat, and ambient rows for the same
    # (user, project) must not create one instance per spelling.
    before do
      insert_rows([
        { id: 20, definition: 'software_development', created_at: '2026-07-02 06:00:00',
          path: project_path, environment: 1 },
        { id: 21, definition: 'software_development', created_at: '2026-07-02 07:00:00',
          path: project_path, environment: 4 },
        { id: 22, definition: 'software_development', created_at: '2026-07-02 08:00:00',
          path: project_path, environment: 5 }
      ])
    end

    it 'collapses each renamed pair onto one agent instance' do
      # NULL environment (rows 1, 3), chat from ide+chat (20, 21), ambient from web+ambient
      # (2, 22), and row 7 which differs on project_id => 4 instances.
      expect(payload[:agents][:count]).to eq(4)
    end
  end

  context 'with agent-class segmentation' do
    using RSpec::Parameterized::TableSyntax

    # Base current-window rows have no agent_type (internal). Add external
    # sessions: two agent types, one of them twice, all sharing the
    # (user_id, project_id, environment) of internal rows 1 and 3.
    before do
      insert_rows([
        { id: 10, definition: 'software_development', created_at: '2026-07-02 09:00:00',
          path: project_path, agent_type: 'claude_code' },
        { id: 11, definition: 'software_development', created_at: '2026-07-02 10:00:00',
          path: project_path, agent_type: 'cursor' },
        { id: 12, definition: 'convert_to_gitlab_ci', created_at: '2026-07-02 11:00:00',
          path: project_path, agent_type: 'claude_code' }
      ])
    end

    where(:agent_class, :expected_sessions, :expected_agents) do
      :all          | 8 | 5
      :internal_dap | 5 | 3
      :external     | 3 | 2
    end

    with_them do
      it 'filters sessions and keys agent instances by class', :aggregate_failures do
        payload = described_class.new(group, current_user: user, timeframe: timeframe,
          agent_class: agent_class).execute.payload

        expect(payload[:sessions][:count]).to eq(expected_sessions)
        expect(payload[:agents][:count]).to eq(expected_agents)
      end
    end

    context 'with the same agent type registered on two machines' do
      before do
        insert_rows([
          { id: 13, definition: 'software_development', created_at: '2026-07-02 12:00:00',
            path: project_path, agent_type: 'claude-code', agent_identity_id: 501 },
          { id: 14, definition: 'software_development', created_at: '2026-07-02 13:00:00',
            path: project_path, agent_type: 'claude-code', agent_identity_id: 502 }
        ])
      end

      it 'counts one instance per identity, not one per agent type', :aggregate_failures do
        payload = described_class.new(group, current_user: user, timeframe: timeframe,
          agent_class: :external).execute.payload

        expect(payload[:sessions][:count]).to eq(5)
        expect(payload[:agents][:count]).to eq(4)
      end
    end
  end

  context 'with chat conversations from otherwise-unseen agent instance keys' do
    before do
      insert_rows([
        { id: 40, definition: 'chat', created_at: '2026-07-02 09:00:00', path: project_path,
          user_id: 77701 },
        { id: 41, definition: 'chat', created_at: '2026-07-02 10:00:00', path: project_path,
          environment: 4 },
        { id: 42, definition: 'agentic_chat/v1', created_at: '2026-07-02 11:00:00', path: project_path,
          user_id: 77702 },
        # a chat version the registry has never shipped: the reference-based
        # guard must exclude it, an exact-definition list would count it
        { id: 43, definition: 'agentic_chat/v2', created_at: '2026-07-02 12:00:00', path: project_path,
          user_id: 77703 },
        # previous window: the guard applies on both sides of the boundary
        { id: 44, definition: 'chat', created_at: '2026-06-20 09:00:00', path: project_path,
          user_id: 77704 }
      ])
    end

    it 'counts them as sessions but never as agent instances', :aggregate_failures do
      # Each row's (user, environment) combo is unique across fixtures, so a
      # broken agents guard would mint new instances here, not hide silently.
      # agentic_chat/v1 is chat's flow-registry successor; guard it the same way.
      expect(payload[:sessions][:count]).to eq(9)
      expect(payload[:sessions][:previous_count]).to eq(2)
      expect(payload[:agents][:count]).to eq(3)
      expect(payload[:agents][:previous_count]).to eq(1)
    end
  end

  context 'with top user and project activity requested' do
    before do
      insert_rows([
        { id: 50, definition: 'software_development', created_at: '2026-07-02 09:00:00',
          path: project_path, user_id: 88801, project_id: 777 },
        { id: 51, definition: 'chat', created_at: '2026-07-02 10:00:00',
          path: project_path, user_id: 88801, project_id: 777 },
        { id: 53, definition: 'software_development', created_at: '2026-07-02 11:00:00',
          path: project_path, user_id: 88802 },
        { id: 54, definition: 'software_development', created_at: '2026-07-02 12:00:00',
          path: project_path, user_id: 88802 },
        # previous window: outside the rankings
        { id: 52, definition: 'software_development', created_at: '2026-06-20 10:00:00',
          path: project_path, user_id: 88801, project_id: 777 }
      ])
    end

    subject(:payload) do
      described_class.new(group, current_user: user, timeframe: timeframe,
        top_users_limit: 5, top_projects_limit: 5).execute.payload
    end

    it 'ranks users by deduplicated session count, chat included, ties broken by id' do
      expect(payload[:top_users]).to eq([
        { user_id: user.id, session_count: 5 },
        { user_id: 88801, session_count: 2 },
        { user_id: 88802, session_count: 2 }
      ])
    end

    it 'ranks projects, not counting rows without a project' do
      expect(payload[:top_projects]).to eq([
        { project_id: 777, session_count: 2 },
        { project_id: 12345, session_count: 1 }
      ])
    end

    it 'applies the agent class filter to the rankings' do
      payload = described_class.new(group, current_user: user, timeframe: timeframe,
        agent_class: :external, top_users_limit: 5).execute.payload

      expect(payload[:top_users]).to eq([])
    end

    it 'caps the rankings at the limit' do
      payload = described_class.new(group, current_user: user, timeframe: timeframe,
        top_users_limit: 1).execute.payload

      expect(payload[:top_users]).to match_array([{ user_id: user.id, session_count: 5 }])
    end
  end

  it 'omits the rankings unless requested', :aggregate_failures do
    expect(payload).not_to have_key(:top_users)
    expect(payload).not_to have_key(:top_projects)
  end

  context 'with namespace-attached sessions in two namespaces' do
    # num_nonnulls(namespace_id, project_id) = 1, so these carry a NULL project_id.
    # Without namespace_id in the key they collapse onto one agent instance.
    before do
      insert_rows([
        { id: 30, definition: 'software_development', created_at: '2026-07-02 06:00:00',
          path: project_path, project_id: 'NULL', namespace_id: 8001 },
        { id: 31, definition: 'software_development', created_at: '2026-07-02 07:00:00',
          path: project_path, project_id: 'NULL', namespace_id: 8002 }
      ])
    end

    it 'keeps the two namespaces as separate agent instances', :aggregate_failures do
      expect(payload[:sessions][:count]).to eq(7)
      # the three baseline instances plus one per namespace
      expect(payload[:agents][:count]).to eq(5)
    end
  end

  def insert_rows(rows)
    rows.each do |row|
      agent_type = row.key?(:agent_type) ? "'#{row[:agent_type]}'" : 'NULL'
      agent_identity_id = row.fetch(:agent_identity_id, 'NULL')
      namespace_id = row.fetch(:namespace_id, 'NULL')

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_duo_workflows_workflows
          (id, user_id, project_id, namespace_id, environment, agent_type, agent_identity_id, created_at, workflow_definition, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{row.fetch(:user_id, user.id)}, #{row.fetch(:project_id, 'NULL')}, #{namespace_id}, #{row.fetch(:environment, 'NULL')}, #{agent_type}, #{agent_identity_id}, '#{row[:created_at]}', '#{row[:definition]}',
           '#{row[:path]}', '#{row.fetch(:replicated_at, row[:created_at])}', false)
      SQL
    end
  end
end
