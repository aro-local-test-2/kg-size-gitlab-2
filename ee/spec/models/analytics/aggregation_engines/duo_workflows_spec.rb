# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::AggregationEngines::DuoWorkflows, :click_house, time_travel_to: '2026-01-30',
  type: :aggregation_engine,
  feature_category: :duo_agent_platform do
  let(:engine) { described_class.new(context: engine_context) }
  let(:engine_context) do
    {
      scope: ClickHouse::Client::QueryBuilder.new(described_class.table_name),
      current_user: user,
      authorization_resources: [project1]
    }
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:project1) { create(:project) }
  let_it_be(:project2) { create(:project) }
  let_it_be(:namespace) { create(:group) }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :read_agent_artifacts, anything).and_return(true)

    clickhouse_fixture(:duo_workflows_workflows_enriched, flows_data.map do |flow|
      namespace = flow[:namespace] || (flow[:project] || project1).project_namespace

      {
        id: flow[:id],
        user_id: flow.fetch(:user_id, 1),
        project_id: flow[:namespace] ? nil : (flow[:project] || project1).id,
        workflow_definition: flow.fetch(:workflow_definition, 'software_development'),
        status: flow.fetch(:status, 0),
        model_used: flow.fetch(:model_used, ''),
        created_at: flow[:created_at],
        updated_at: flow.fetch(:updated_at, flow[:created_at]),
        traversal_path: namespace.traversal_path(with_organization: true).to_s,
        credits_used: flow.fetch(:credits_used, 0),
        created_merge_request_ids: Arel.sql("[#{flow.fetch(:created_merge_request_ids, []).join(', ')}]"),
        later_merged_merge_request_ids: Arel.sql("[#{flow.fetch(:later_merged_merge_request_ids, []).join(', ')}]"),
        later_closed_merge_request_ids: Arel.sql("[#{flow.fetch(:later_closed_merge_request_ids, []).join(', ')}]"),
        _siphon_deleted: flow.fetch(:_siphon_deleted, false),
        _version: flow.fetch(:_version, flow[:created_at])
      }
    end)
  end

  describe '.prepare_base_aggregation_scope' do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project_in_group) { create(:project, group: group) }
    let_it_be(:project_in_subgroup) { create(:project, group: subgroup) }
    let_it_be(:other_project) { create(:project) }

    let(:flows_data) do
      [
        { id: 1, project: project_in_group,    created_at: 10.days.ago },
        { id: 2, project: project_in_subgroup, created_at: 10.days.ago },
        { id: 3, project: other_project,       created_at: 10.days.ago },
        # A flow not scoped to a project sits directly on the group path.
        { id: 4, namespace: group,             created_at: 10.days.ago }
      ]
    end

    subject(:result) do
      scope = described_class.prepare_base_aggregation_scope(send(scope_key))
      ClickHouse::Client.select(scope, :main)
    end

    where(:scope_key, :expected_ids) do
      [
        [:project_in_group,    [1]],
        [:group,               [1, 2, 4]],
        [:subgroup,            [2]],
        [:other_project,       [3]]
      ]
    end

    with_them do
      it 'returns records scoped to the provided context object' do
        expect(result.map { |r| r['id'] }).to match_array(expected_ids)
      end
    end

    context 'with multiple scope objects' do
      it 'combines the scopes with OR' do
        scope = described_class.prepare_base_aggregation_scope([subgroup, other_project])
        result = ClickHouse::Client.select(scope, :main)

        expect(result.map { |r| r['id'] }).to match_array([2, 3])
      end
    end

    context 'with no scope objects' do
      it 'raises an ArgumentError' do
        expect { described_class.prepare_base_aggregation_scope([]) }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'versioning' do
    let(:flows_data) do
      [
        { id: 1, credits_used: 1.0, created_at: 10.days.ago, _version: 10.days.ago },
        { id: 1, credits_used: 3.0, created_at: 10.days.ago, _version: 9.days.ago },
        { id: 2, credits_used: 5.0, created_at: 10.days.ago, _version: 10.days.ago },
        { id: 2, credits_used: 5.0, created_at: 10.days.ago, _version: 9.days.ago, _siphon_deleted: true }
      ]
    end

    it 'aggregates only the latest non-deleted version per primary key' do
      request = {
        metrics: [
          { identifier: :total_count },
          { identifier: :"credits_used.sum" }
        ]
      }

      expect(engine).to execute_aggregation(request).and_return([
        { total_count: 1, credits_used__sum: 3.0 }
      ])
    end
  end

  describe 'dimensions' do
    describe 'workflow_definition' do
      let(:flows_data) do
        [
          { id: 1, workflow_definition: 'software_development', created_at: 10.days.ago },
          { id: 2, workflow_definition: 'software_development', created_at: 10.days.ago },
          { id: 3, workflow_definition: 'fix_pipeline',         created_at: 10.days.ago }
        ]
      end

      it 'groups flows by workflow_definition' do
        request = {
          dimensions: [{ identifier: :workflow_definition }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { workflow_definition: 'software_development', total_count: 2 },
          { workflow_definition: 'fix_pipeline',         total_count: 1 }
        ]))
      end
    end

    describe 'project_id' do
      let(:flows_data) do
        [
          { id: 1, project: project1, created_at: 10.days.ago, credits_used: 1.0 },
          { id: 2, project: project1, created_at: 40.days.ago, credits_used: 2.0 },
          { id: 3, project: project2, created_at: 10.days.ago, credits_used: 4.0 },
          # A flow not scoped to a project has no project_id.
          { id: 4, namespace: namespace, created_at: 10.days.ago, credits_used: 8.0 }
        ]
      end

      it 'groups flows by project_id with a null bucket for namespace-level flows' do
        request = {
          dimensions: [{ identifier: :project_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, total_count: 2 },
          { project_id: project2.id, total_count: 1 },
          { project_id: nil, total_count: 1 }
        ]))
      end

      it 'groups flows by project_id with project request' do
        request = {
          dimensions: [{ identifier: :project }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, total_count: 2 },
          { project_id: project2.id, total_count: 1 },
          { project_id: nil, total_count: 1 }
        ]))
      end

      it 'sums credits per project' do
        request = {
          dimensions: [{ identifier: :project_id }],
          metrics: [{ identifier: :"credits_used.sum" }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, credits_used__sum: 3.0 },
          { project_id: project2.id, credits_used__sum: 4.0 },
          { project_id: nil, credits_used__sum: 8.0 }
        ]))
      end

      it 'groups flows by project_id and monthly bucket' do
        request = {
          dimensions: [
            { identifier: :project_id },
            { identifier: :created_at, parameters: { granularity: 'monthly' } }
          ],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, created_at_granularity_monthly: 40.days.ago.beginning_of_month, total_count: 1 },
          { project_id: project1.id, created_at_granularity_monthly: 10.days.ago.beginning_of_month, total_count: 1 },
          { project_id: project2.id, created_at_granularity_monthly: 10.days.ago.beginning_of_month, total_count: 1 },
          { project_id: nil,         created_at_granularity_monthly: 10.days.ago.beginning_of_month, total_count: 1 }
        ]))
      end

      it 'orders projects by flow count' do
        request = {
          dimensions: [{ identifier: :project_id }],
          metrics: [{ identifier: :total_count }],
          order: [{ identifier: :total_count, direction: :desc }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { project_id: project1.id, total_count: 2 },
          a_hash_including(total_count: 1),
          a_hash_including(total_count: 1)
        ])
      end
    end

    describe 'group_id' do
      let_it_be(:top_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: top_group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }
      let_it_be(:other_group) { create(:group) }

      let(:flows_data) do
        [
          { id: 1, namespace: top_group,      created_at: 10.days.ago, credits_used: 1.0 },
          { id: 2, namespace: subgroup,       created_at: 10.days.ago, credits_used: 2.0 },
          { id: 3, project: subgroup_project, created_at: 10.days.ago, credits_used: 4.0 },
          { id: 4, project: subgroup_project, created_at: 40.days.ago, credits_used: 8.0 },
          { id: 5, namespace: other_group,    created_at: 10.days.ago, credits_used: 16.0 }
        ]
      end

      it 'groups flows by top-level group by default' do
        request = {
          dimensions: [{ identifier: :group_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id: top_group.id, total_count: 4 },
          { group_id: other_group.id, total_count: 1 }
        ]))
      end

      it 'groups flows by the group at the requested depth' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 2 } }],
          metrics: [{ identifier: :total_count }]
        }

        # Flows tracked directly in `top_group` and `other_group` have no group at depth 2.
        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id_2: subgroup.id, total_count: 3 },
          { group_id_2: nil, total_count: 2 }
        ]))
      end

      it 'yields the project namespace id for flows tracked in a project at the requested depth' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 3 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id_3: subgroup_project.project_namespace_id, total_count: 2 },
          { group_id_3: nil, total_count: 3 }
        ]))
      end

      it 'returns a single null bucket for a depth deeper than the hierarchy' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 4 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ group_id_4: nil, total_count: 5 }])
      end

      it 'sums credits per group' do
        request = {
          dimensions: [{ identifier: :group_id }],
          metrics: [{ identifier: :"credits_used.sum" }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id: top_group.id, credits_used__sum: 15.0 },
          { group_id: other_group.id, credits_used__sum: 16.0 }
        ]))
      end

      it 'groups flows by group and monthly bucket' do
        request = {
          dimensions: [
            { identifier: :group_id, parameters: { depth: 2 } },
            { identifier: :created_at, parameters: { granularity: 'monthly' } }
          ],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id_2: subgroup.id, created_at_granularity_monthly: 10.days.ago.beginning_of_month, total_count: 2 },
          { group_id_2: subgroup.id, created_at_granularity_monthly: 40.days.ago.beginning_of_month, total_count: 1 },
          { group_id_2: nil,         created_at_granularity_monthly: 10.days.ago.beginning_of_month, total_count: 2 }
        ]))
      end

      it 'groups flows by group_id with group request' do
        request = {
          dimensions: [{ identifier: :group, parameters: { depth: 2 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id_2: subgroup.id, total_count: 3 },
          { group_id_2: nil, total_count: 2 }
        ]))
      end

      it 'returns a validation error for a depth outside the allowed range' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 0 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).with_errors(
          array_including(a_string_matching(/Invalid value\(s\) for parameter `depth`: 0/))
        )
      end
    end

    describe 'status' do
      let(:statuses) { ::Ai::DuoWorkflows::Workflow.state_machines[:status].states }

      let(:flows_data) do
        [
          { id: 1, status: statuses[:finished].value, created_at: 10.days.ago },
          { id: 2, status: statuses[:finished].value, created_at: 10.days.ago },
          { id: 3, status: statuses[:failed].value,   created_at: 10.days.ago }
        ]
      end

      it 'groups flows by status and returns state names' do
        request = {
          dimensions: [{ identifier: :status }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { status: 'finished', total_count: 2 },
          { status: 'failed',   total_count: 1 }
        ]))
      end
    end

    describe 'model_used' do
      let(:flows_data) do
        [
          { id: 1, model_used: 'claude-sonnet-4-5', created_at: 10.days.ago },
          { id: 2, model_used: 'claude-sonnet-4-5', created_at: 10.days.ago },
          { id: 3, model_used: 'claude-haiku-4-5',  created_at: 10.days.ago }
        ]
      end

      it 'groups flows by model_used' do
        request = {
          dimensions: [{ identifier: :model_used }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { model_used: 'claude-sonnet-4-5', total_count: 2 },
          { model_used: 'claude-haiku-4-5',  total_count: 1 }
        ]))
      end
    end

    describe 'user_id' do
      let(:flows_data) do
        [
          { id: 1, user_id: 1, created_at: 10.days.ago },
          { id: 2, user_id: 1, created_at: 10.days.ago },
          { id: 3, user_id: 2, created_at: 10.days.ago }
        ]
      end

      it 'groups flows by user_id' do
        request = {
          dimensions: [{ identifier: :user_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { user_id: 1, total_count: 2 },
          { user_id: 2, total_count: 1 }
        ]))
      end

      it 'groups flows by user_id with user request' do
        request = {
          dimensions: [{ identifier: :user }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { user_id: 1, total_count: 2 },
          { user_id: 2, total_count: 1 }
        ]))
      end
    end

    describe 'created_at' do
      let(:flows_data) do
        [
          { id: 1, created_at: 10.days.ago },
          { id: 2, created_at: 10.days.ago },
          { id: 3, created_at: 100.days.ago }
        ]
      end

      it 'groups flows by monthly buckets by default' do
        request = {
          dimensions: [{ identifier: :created_at }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_at: 10.days.ago.beginning_of_month,  total_count: 2 },
          { created_at: 100.days.ago.beginning_of_month, total_count: 1 }
        ]))
      end

      it 'groups flows by weekly buckets' do
        request = {
          dimensions: [{ identifier: :created_at, parameters: { granularity: 'weekly' } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_at_granularity_weekly: 10.days.ago.beginning_of_week,  total_count: 2 },
          { created_at_granularity_weekly: 100.days.ago.beginning_of_week, total_count: 1 }
        ]))
      end
    end
  end

  describe 'metrics' do
    describe 'total_count' do
      let(:statuses) { ::Ai::DuoWorkflows::Workflow.state_machines[:status].states }

      let(:flows_data) do
        [
          { id: 1, status: statuses[:finished].value, created_at: 10.days.ago },
          { id: 2, status: statuses[:finished].value, created_at: 10.days.ago },
          { id: 3, status: statuses[:failed].value,   created_at: 100.days.ago },
          { id: 4, status: statuses[:running].value,  created_at: 10.days.ago }
        ]
      end

      it 'counts total flows' do
        request = { metrics: [{ identifier: :total_count }] }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 4 }])
      end

      it 'counts flows with the given status name' do
        request = { metrics: [{ identifier: :total_count, parameters: { status: 'finished' } }] }

        expect(engine).to execute_aggregation(request).and_return([{ total_count_finished: 2 }])
      end

      it 'treats multiple statuses as OR' do
        request = { metrics: [{ identifier: :total_count, parameters: { status: %w[finished failed] } }] }

        expect(engine).to execute_aggregation(request).and_return([{ total_count_finished_failed: 3 }])
      end

      it 'counts total and per-status flows in a single request' do
        request = {
          metrics: [
            { identifier: :total_count },
            { identifier: :total_count, parameters: { status: 'finished' } },
            { identifier: :total_count, parameters: { status: 'failed' } }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 4, total_count_finished: 2, total_count_failed: 1 }
        ])
      end

      it 'combines the status parameter with the status filter' do
        request = {
          metrics: [{ identifier: :total_count, parameters: { status: 'finished' } }],
          filters: [{ identifier: :status, values: 'failed' }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count_finished: 0 }])
      end

      it 'returns an error when status is not a known status name' do
        request = { metrics: [{ identifier: :total_count, parameters: { status: 'nonexistent' } }] }

        expect(engine).to execute_aggregation(request).with_errors(array_including(
          a_string_matching(/Invalid value\(s\) for parameter `status`: nonexistent/)
        ))
      end
    end

    describe 'users_count' do
      let(:flows_data) do
        [
          { id: 1, user_id: 1, created_at: 10.days.ago },
          { id: 2, user_id: 1, created_at: 10.days.ago },
          { id: 3, user_id: 2, created_at: 10.days.ago }
        ]
      end

      it 'counts unique users' do
        request = { metrics: [{ identifier: :users_count }] }

        expect(engine).to execute_aggregation(request).and_return([{ users_count: 2 }])
      end
    end

    describe 'projects_count' do
      let(:flows_data) do
        [
          { id: 1, project: project1, created_at: 10.days.ago },
          { id: 2, project: project1, created_at: 10.days.ago },
          { id: 3, project: project2, created_at: 10.days.ago },
          # Namespace-level flows have no project and must not be counted.
          { id: 4, namespace: namespace, created_at: 10.days.ago }
        ]
      end

      it 'counts unique projects, excluding namespace-level flows' do
        request = { metrics: [{ identifier: :total_count }, { identifier: :projects_count }] }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 4, projects_count: 2 }])
      end
    end

    describe 'flow_types_count' do
      let(:flows_data) do
        [
          { id: 1, workflow_definition: 'software_development', created_at: 10.days.ago },
          { id: 2, workflow_definition: 'software_development', created_at: 10.days.ago },
          { id: 3, workflow_definition: 'fix_pipeline',         created_at: 10.days.ago },
          { id: 4, workflow_definition: 'chat',                 created_at: 100.days.ago }
        ]
      end

      it 'counts unique flow types' do
        request = { metrics: [{ identifier: :flow_types_count }] }

        expect(engine).to execute_aggregation(request).and_return([{ flow_types_count: 3 }])
      end

      it 'counts only flow types used within the filtered period' do
        request = {
          metrics: [{ identifier: :flow_types_count }],
          filters: [{ identifier: :created_at, values: (30.days.ago..) }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ flow_types_count: 2 }])
      end

      it 'counts unique flow types per date bucket' do
        request = {
          dimensions: [{ identifier: :created_at }],
          metrics: [{ identifier: :flow_types_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_at: 10.days.ago.beginning_of_month,  flow_types_count: 2 },
          { created_at: 100.days.ago.beginning_of_month, flow_types_count: 1 }
        ]))
      end
    end

    describe 'retention window metrics' do
      # Week 1 users: 1, 2, 3. Week 2 users: 1, 4, 5, 6.
      # So week 2 has 1 returning, 3 joined, 2 churned, and 3 in the previous period.
      let(:flows_data) do
        [
          { id: 1, user_id: 1, created_at: 20.days.ago },
          { id: 2, user_id: 2, created_at: 20.days.ago },
          { id: 3, user_id: 3, created_at: 20.days.ago },
          { id: 4, user_id: 1, created_at: 10.days.ago },
          { id: 5, user_id: 4, created_at: 10.days.ago },
          # Second flow for user 4 in the same bucket: groupArray repeats the value, so the
          # joined and churned array operations have to dedupe before counting.
          { id: 6, user_id: 4, created_at: 10.days.ago },
          { id: 7, user_id: 5, created_at: 10.days.ago },
          { id: 8, user_id: 6, created_at: 10.days.ago }
        ]
      end

      let(:weekly_bucket) { { identifier: :created_at, parameters: { granularity: 'weekly' } } }
      let(:first_week) { 20.days.ago.beginning_of_week }
      let(:second_week) { 10.days.ago.beginning_of_week }

      describe 'returning_users_count' do
        it 'counts users present in both the current and previous weekly period' do
          request = { dimensions: [weekly_bucket], metrics: [{ identifier: :returning_users_count }] }

          expect(engine).to execute_aggregation(request).and_return(an_array_matching([
            { created_at_granularity_weekly: first_week,  returning_users_count: 0 },
            { created_at_granularity_weekly: second_week, returning_users_count: 1 }
          ]))
        end

        context 'with monthly granularity spanning two months' do
          let(:flows_data) do
            [
              { id: 1, user_id: 1, created_at: 50.days.ago },
              { id: 2, user_id: 2, created_at: 50.days.ago },
              { id: 3, user_id: 1, created_at: 10.days.ago },
              { id: 4, user_id: 3, created_at: 10.days.ago }
            ]
          end

          it 'counts users present in both the current and previous monthly period' do
            request = {
              dimensions: [{ identifier: :created_at, parameters: { granularity: 'monthly' } }],
              metrics: [{ identifier: :returning_users_count }]
            }

            expect(engine).to execute_aggregation(request).and_return(an_array_matching([
              { created_at_granularity_monthly: 50.days.ago.beginning_of_month, returning_users_count: 0 },
              { created_at_granularity_monthly: 10.days.ago.beginning_of_month, returning_users_count: 1 }
            ]))
          end
        end
      end

      describe 'joined_users_count' do
        it 'counts users absent from the previous weekly period' do
          request = { dimensions: [weekly_bucket], metrics: [{ identifier: :joined_users_count }] }

          expect(engine).to execute_aggregation(request).and_return(an_array_matching([
            { created_at_granularity_weekly: first_week,  joined_users_count: 3 },
            { created_at_granularity_weekly: second_week, joined_users_count: 3 }
          ]))
        end
      end

      describe 'churned_users_count' do
        it 'counts previous-period users absent from the current weekly period' do
          request = { dimensions: [weekly_bucket], metrics: [{ identifier: :churned_users_count }] }

          expect(engine).to execute_aggregation(request).and_return(an_array_matching([
            { created_at_granularity_weekly: first_week,  churned_users_count: 0 },
            { created_at_granularity_weekly: second_week, churned_users_count: 2 }
          ]))
        end
      end

      describe 'previous_period_users_count' do
        it 'returns the distinct user count from the previous weekly period' do
          request = { dimensions: [weekly_bucket], metrics: [{ identifier: :previous_period_users_count }] }

          expect(engine).to execute_aggregation(request).and_return(an_array_matching([
            { created_at_granularity_weekly: first_week,  previous_period_users_count: 0 },
            { created_at_granularity_weekly: second_week, previous_period_users_count: 3 }
          ]))
        end
      end

      describe 'all four metrics together' do
        let(:all_metrics) do
          [
            { identifier: :users_count },
            { identifier: :returning_users_count },
            { identifier: :joined_users_count },
            { identifier: :churned_users_count },
            { identifier: :previous_period_users_count }
          ]
        end

        it 'computes every window metric in a single request' do
          request = { dimensions: [weekly_bucket], metrics: all_metrics }

          expect(engine).to execute_aggregation(request).and_return(an_array_matching([
            { created_at_granularity_weekly: first_week, users_count: 3, returning_users_count: 0,
              joined_users_count: 3, churned_users_count: 0, previous_period_users_count: 0 },
            { created_at_granularity_weekly: second_week, users_count: 4, returning_users_count: 1,
              joined_users_count: 3, churned_users_count: 2, previous_period_users_count: 3 }
          ]))
        end

        it 'satisfies the new-user and churn identities in every bucket', :aggregate_failures do
          request = Gitlab::Database::Aggregation::Request.new(
            dimensions: [weekly_bucket], metrics: all_metrics
          )
          rows = engine.execute(request)[:data].to_a.map(&:with_indifferent_access)

          expect(rows.size).to eq(2)

          expect(rows.map { |r| r[:returning_users_count] + r[:joined_users_count] })
            .to eq(rows.map { |r| r[:users_count] })
          expect(rows.map { |r| r[:returning_users_count] + r[:churned_users_count] })
            .to eq(rows.map { |r| r[:previous_period_users_count] })
        end

        context 'with an extra workflow_definition dimension' do
          # Without PARTITION BY the lag window would spill across flow types ordered by
          # date, comparing software_development users against fix_pipeline users.
          let(:flows_data) do
            [
              { id: 1, user_id: 1, workflow_definition: 'software_development', created_at: 20.days.ago },
              { id: 2, user_id: 2, workflow_definition: 'software_development', created_at: 20.days.ago },
              { id: 3, user_id: 3, workflow_definition: 'fix_pipeline',         created_at: 20.days.ago },
              { id: 4, user_id: 1, workflow_definition: 'software_development', created_at: 10.days.ago },
              { id: 5, user_id: 4, workflow_definition: 'software_development', created_at: 10.days.ago },
              { id: 6, user_id: 3, workflow_definition: 'fix_pipeline',         created_at: 10.days.ago },
              { id: 7, user_id: 5, workflow_definition: 'fix_pipeline',         created_at: 10.days.ago }
            ]
          end

          it 'partitions the lag window so each flow type is computed independently' do
            request = {
              dimensions: [{ identifier: :workflow_definition }, weekly_bucket],
              metrics: all_metrics
            }

            expect(engine).to execute_aggregation(request).and_return(an_array_matching([
              { workflow_definition: 'software_development', created_at_granularity_weekly: first_week,
                users_count: 2, returning_users_count: 0, joined_users_count: 2,
                churned_users_count: 0, previous_period_users_count: 0 },
              { workflow_definition: 'software_development', created_at_granularity_weekly: second_week,
                users_count: 2, returning_users_count: 1, joined_users_count: 1,
                churned_users_count: 1, previous_period_users_count: 2 },
              { workflow_definition: 'fix_pipeline', created_at_granularity_weekly: first_week,
                users_count: 1, returning_users_count: 0, joined_users_count: 1,
                churned_users_count: 0, previous_period_users_count: 0 },
              { workflow_definition: 'fix_pipeline', created_at_granularity_weekly: second_week,
                users_count: 2, returning_users_count: 1, joined_users_count: 1,
                churned_users_count: 0, previous_period_users_count: 1 }
            ]))
          end
        end
      end
    end

    describe 'credits_used measurement' do
      let(:flows_data) do
        [
          { id: 1, credits_used: 1.0, created_at: 10.days.ago },
          { id: 2, credits_used: 2.0, created_at: 10.days.ago },
          { id: 3, credits_used: 6.0, created_at: 10.days.ago }
        ]
      end

      it 'calculates all measurement aggregates in one request' do
        request = {
          metrics: [
            { identifier: :"credits_used.min" },
            { identifier: :"credits_used.max" },
            { identifier: :"credits_used.mean" },
            { identifier: :"credits_used.quantile", parameters: { quantile: 0.5 } },
            { identifier: :"credits_used.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            credits_used__min: 1.0,
            credits_used__max: 6.0,
            credits_used__mean: 3.0,
            credits_used__quantile_d2cba: 2.0,
            credits_used__sum: 9.0
          }
        ])
      end

      context 'when the user lacks the read_agent_artifacts ability' do
        before do
          allow(Ability).to receive(:allowed?).with(user, :read_agent_artifacts, anything).and_return(false)
        end

        it 'drops the credits_used metrics from the request' do
          request = {
            metrics: [
              { identifier: :total_count },
              { identifier: :"credits_used.sum" }
            ]
          }

          expect(engine).to execute_aggregation(request).and_return([{ total_count: 3 }])
        end
      end
    end

    describe 'merge request count measurements' do
      let(:flows_data) do
        [
          { id: 1, workflow_definition: 'software_development', created_at: 10.days.ago,
            created_merge_request_ids: [11, 12, 13], later_merged_merge_request_ids: [11, 12],
            later_closed_merge_request_ids: [13] },
          { id: 2, workflow_definition: 'software_development', created_at: 10.days.ago,
            created_merge_request_ids: [14], later_merged_merge_request_ids: [14] },
          { id: 3, workflow_definition: 'fix_pipeline', created_at: 10.days.ago,
            created_merge_request_ids: [15, 16], later_closed_merge_request_ids: [15] },
          { id: 4, workflow_definition: 'chat', created_at: 10.days.ago }
        ]
      end

      it 'sums created, merged, closed, and open merge request counts across flows' do
        request = {
          metrics: [
            { identifier: :"created_mr_count.sum" },
            { identifier: :"merged_mr_count.sum" },
            { identifier: :"closed_mr_count.sum" },
            { identifier: :"open_mr_count.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { created_mr_count__sum: 6, merged_mr_count__sum: 3, closed_mr_count__sum: 2, open_mr_count__sum: 1 }
        ])
      end

      it 'calculates all measurement aggregates in one request' do
        request = {
          metrics: [
            { identifier: :"created_mr_count.min" },
            { identifier: :"created_mr_count.max" },
            { identifier: :"created_mr_count.mean" },
            { identifier: :"created_mr_count.quantile", parameters: { quantile: 0.5 } },
            { identifier: :"created_mr_count.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            created_mr_count__min: 0,
            created_mr_count__max: 3,
            created_mr_count__mean: 1.5,
            created_mr_count__quantile_d2cba: 1.5,
            created_mr_count__sum: 6
          }
        ])
      end

      it 'calculates all open merge request count aggregates in one request' do
        request = {
          metrics: [
            { identifier: :"open_mr_count.min" },
            { identifier: :"open_mr_count.max" },
            { identifier: :"open_mr_count.mean" },
            { identifier: :"open_mr_count.quantile", parameters: { quantile: 0.5 } },
            { identifier: :"open_mr_count.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            open_mr_count__min: 0,
            open_mr_count__max: 1,
            open_mr_count__mean: 0.25,
            open_mr_count__quantile_d2cba: 0.0,
            open_mr_count__sum: 1
          }
        ])
      end

      it 'sums merge request counts per flow type' do
        request = {
          dimensions: [{ identifier: :workflow_definition }],
          metrics: [
            { identifier: :"created_mr_count.sum" },
            { identifier: :"merged_mr_count.sum" },
            { identifier: :"closed_mr_count.sum" },
            { identifier: :"open_mr_count.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { workflow_definition: 'software_development',
            created_mr_count__sum: 4, merged_mr_count__sum: 3, closed_mr_count__sum: 1, open_mr_count__sum: 0 },
          { workflow_definition: 'fix_pipeline',
            created_mr_count__sum: 2, merged_mr_count__sum: 0, closed_mr_count__sum: 1, open_mr_count__sum: 1 },
          { workflow_definition: 'chat',
            created_mr_count__sum: 0, merged_mr_count__sum: 0, closed_mr_count__sum: 0, open_mr_count__sum: 0 }
        ]))
      end

      # The outcomes MV can lag a removed MR link, leaving an outcome id that is no longer
      # in created_merge_request_ids. Subtracting lengths would go negative here.
      context 'when an outcome id is no longer in the created list' do
        let(:flows_data) do
          [
            { id: 1, workflow_definition: 'software_development', created_at: 10.days.ago,
              created_merge_request_ids: [21], later_merged_merge_request_ids: [21, 99] },
            { id: 2, workflow_definition: 'fix_pipeline', created_at: 10.days.ago,
              created_merge_request_ids: [31, 32], later_merged_merge_request_ids: [31],
              later_closed_merge_request_ids: [99] }
          ]
        end

        it 'counts only the created merge requests that have no outcome' do
          request = {
            dimensions: [{ identifier: :workflow_definition }],
            metrics: [{ identifier: :"open_mr_count.sum" }]
          }

          expect(engine).to execute_aggregation(request).and_return(match_array([
            { workflow_definition: 'software_development', open_mr_count__sum: 0 },
            { workflow_definition: 'fix_pipeline', open_mr_count__sum: 1 }
          ]))
        end

        it 'stays non-negative when the outcome ids outnumber the created ids' do
          request = {
            metrics: [
              { identifier: :"created_mr_count.sum" },
              { identifier: :"merged_mr_count.sum" },
              { identifier: :"closed_mr_count.sum" },
              { identifier: :"open_mr_count.sum" }
            ]
          }

          # Subtracting lengths would return 3 - 3 - 1 = -1 for these flows.
          expect(engine).to execute_aggregation(request).and_return([
            { created_mr_count__sum: 3, merged_mr_count__sum: 3, closed_mr_count__sum: 1, open_mr_count__sum: 1 }
          ])
        end
      end
    end
  end

  describe 'filters' do
    describe 'workflow_definition' do
      let(:flows_data) do
        [
          { id: 1, workflow_definition: 'software_development', created_at: 10.days.ago },
          { id: 2, workflow_definition: 'fix_pipeline',         created_at: 10.days.ago },
          { id: 3, workflow_definition: 'chat',                 created_at: 10.days.ago }
        ]
      end

      it 'filters by a single flow type' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :workflow_definition, values: 'fix_pipeline' }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 1 }])
      end

      it 'filters by multiple flow types' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :workflow_definition, values: %w[software_development fix_pipeline] }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end
    end

    describe 'project_id' do
      let(:flows_data) do
        [
          { id: 1, project: project1, created_at: 10.days.ago },
          { id: 2, project: project2, created_at: 10.days.ago },
          { id: 3, namespace: namespace, created_at: 10.days.ago }
        ]
      end

      it 'filters flows by a single project Global ID' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :project_id, values: project1.to_global_id.to_s }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 1 }])
      end

      it 'filters flows by multiple project Global IDs, excluding namespace-level flows' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :project_id, values: [project1.to_global_id.to_s, project2.to_global_id.to_s] }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end

      it 'returns no rows when no flow matches the project' do
        missing_project_gid = Gitlab::GlobalId.build(model_name: 'Project', id: non_existing_record_id).to_s
        request = {
          dimensions: [{ identifier: :project_id }],
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :project_id, values: missing_project_gid }]
        }

        expect(engine).to execute_aggregation(request).and_return([])
      end
    end

    describe 'group_id' do
      let_it_be(:top_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: top_group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }
      let_it_be(:other_group) { create(:group) }

      let(:flows_data) do
        [
          { id: 1, namespace: top_group,      created_at: 10.days.ago },
          { id: 2, namespace: subgroup,       created_at: 10.days.ago },
          { id: 3, project: subgroup_project, created_at: 10.days.ago },
          { id: 4, namespace: other_group,    created_at: 10.days.ago }
        ]
      end

      let(:invalid_groups_error) { 'Values must be Global IDs of existing groups for filter `group_id`' }

      it 'filters flows by a single group Global ID, including its descendants' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: top_group.to_global_id.to_s }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 3 }])
      end

      it 'filters flows down to a subgroup subtree' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: subgroup.to_global_id.to_s }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end

      it 'filters flows by multiple group Global IDs' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [
            { identifier: :group_id, values: [subgroup.to_global_id.to_s, other_group.to_global_id.to_s] }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 3 }])
      end

      it 'combines the group filter with the group dimension' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 2 } }],
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: top_group.to_global_id.to_s }]
        }

        expect(engine).to execute_aggregation(request).and_return(an_array_matching([
          { group_id_2: subgroup.id, total_count: 2 },
          { group_id_2: nil, total_count: 1 }
        ]))
      end

      it 'rejects Global IDs of groups that do not exist' do
        missing_group_gid = Gitlab::GlobalId.build(model_name: 'Group', id: non_existing_record_id).to_s
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: missing_group_gid }]
        }

        expect(engine).to execute_aggregation(request).with_errors([invalid_groups_error])
      end

      it 'rejects Global IDs of other models rather than matching on the bare id' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: subgroup_project.to_global_id.to_s }]
        }

        expect(engine).to execute_aggregation(request).with_errors([invalid_groups_error])
      end
    end

    describe 'status' do
      let(:statuses) { ::Ai::DuoWorkflows::Workflow.state_machines[:status].states }

      let(:flows_data) do
        [
          { id: 1, status: statuses[:finished].value, created_at: 10.days.ago },
          { id: 2, status: statuses[:failed].value,   created_at: 10.days.ago },
          { id: 3, status: statuses[:running].value,  created_at: 10.days.ago }
        ]
      end

      it 'filters by a single status name' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :status, values: 'finished' }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 1 }])
      end

      it 'filters by multiple status names' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :status, values: %w[finished failed] }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end
    end

    describe 'user_id' do
      let(:flows_data) do
        [
          { id: 1, user_id: 1, created_at: 10.days.ago },
          { id: 2, user_id: 1, created_at: 10.days.ago },
          { id: 3, user_id: 2, created_at: 10.days.ago }
        ]
      end

      it 'filters by single user Global ID' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :user_id, values: 'gid://gitlab/User/1' }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end

      it 'filters by multiple user Global IDs' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :user_id, values: %w[gid://gitlab/User/1 gid://gitlab/User/2] }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 3 }])
      end
    end

    describe 'created_at' do
      let(:flows_data) do
        [
          { id: 1, created_at: 10.days.ago },
          { id: 2, created_at: 10.days.ago },
          { id: 3, created_at: 100.days.ago }
        ]
      end

      it 'filters by created_at range' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :created_at, values: (30.days.ago..) }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 2 }])
      end
    end
  end

  describe 'user activity parts' do
    # user 1: 6 flows (4 recent + 2 old), 3 flow types, 3 active days
    # user 2: 2 flows, 2 flow types, 2 active days
    # user 3: 1 flow, 1 flow type, 1 active day
    # user 4: 1 flow, 1 flow type, 1 active day, all outside the recent period
    let(:flows_data) do
      [
        { id: 1, user_id: 1, workflow_definition: 'software_development', created_at: 10.days.ago },
        { id: 2, user_id: 1, workflow_definition: 'chat', created_at: 10.days.ago },
        { id: 3, user_id: 1, workflow_definition: 'convert_to_gitlab_ci', created_at: 9.days.ago },
        { id: 4, user_id: 1, workflow_definition: 'chat', created_at: 9.days.ago },
        { id: 5, user_id: 1, workflow_definition: 'chat', created_at: 100.days.ago },
        { id: 6, user_id: 1, workflow_definition: 'chat', created_at: 100.days.ago },
        { id: 7, user_id: 2, workflow_definition: 'chat', created_at: 10.days.ago },
        { id: 8, user_id: 2, workflow_definition: 'software_development', created_at: 8.days.ago },
        { id: 9, user_id: 3, workflow_definition: 'chat', created_at: 10.days.ago },
        { id: 10, user_id: 4, workflow_definition: 'software_development', created_at: 100.days.ago }
      ]
    end

    describe 'user_tier dimension' do
      it 'splits flows and users per tier, bucketing threshold boundaries into the upper tier' do
        # user 1 sits exactly on the last threshold (6 flows => tier_2) and
        # user 2 exactly on the first (2 flows => tier_1).
        request = {
          dimensions: [{ identifier: :user_tier, parameters: { thresholds: [2, 6] } }],
          metrics: [{ identifier: :total_count }, { identifier: :users_count }],
          order: [{ identifier: :user_tier, parameters: { thresholds: [2, 6] }, direction: :asc }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { user_tier_2_6: 'tier_0', total_count: 2, users_count: 2 },
          { user_tier_2_6: 'tier_1', total_count: 2, users_count: 1 },
          { user_tier_2_6: 'tier_2', total_count: 6, users_count: 1 }
        ])
      end

      it 'computes tiers over the filtered period only' do
        # With old flows filtered out, user 1 drops from 6 flows to 4 (tier_2 -> tier_1)
        # and user 4 has no flows left in the period.
        request = {
          filters: [{ identifier: :created_at, values: (30.days.ago..) }],
          dimensions: [{ identifier: :user_tier, parameters: { thresholds: [2, 6] } }],
          metrics: [{ identifier: :total_count }, { identifier: :users_count }],
          order: [{ identifier: :user_tier, parameters: { thresholds: [2, 6] }, direction: :asc }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { user_tier_2_6: 'tier_0', total_count: 1, users_count: 1 },
          { user_tier_2_6: 'tier_1', total_count: 6, users_count: 2 }
        ])
      end

      it 'fails validation when thresholds are missing' do
        request = {
          dimensions: [{ identifier: :user_tier }],
          metrics: [{ identifier: :users_count }]
        }

        expect(engine).to execute_aggregation(request).with_errors([
          a_string_matching(/parameter `thresholds` is required/)
        ])
      end
    end

    describe 'flow_types_used filter' do
      it 'counts users who ran at least two flow types as a single number' do
        request = {
          filters: [{ identifier: :flow_types_used, values: (2..) }],
          metrics: [{ identifier: :users_count }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ users_count: 2 }])
      end
    end

    describe 'active_days filter' do
      it 'counts users active on exactly one day as a single number' do
        request = {
          filters: [{ identifier: :active_days, values: 1..1 }],
          metrics: [{ identifier: :users_count }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ users_count: 2 }])
      end

      it 'computes active days over the filtered period only' do
        # user 4's only flow is outside the period, so only user 3 remains single-day.
        request = {
          filters: [
            { identifier: :active_days, values: 1..1 },
            { identifier: :created_at, values: (30.days.ago..) }
          ],
          metrics: [{ identifier: :users_count }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ users_count: 1 }])
      end
    end
  end
end
