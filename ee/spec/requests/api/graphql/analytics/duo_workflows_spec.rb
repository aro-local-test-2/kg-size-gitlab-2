# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '(Group|Project|Organization).analytics.duoWorkflows', :click_house, time_travel_to: '2026-01-30',
  feature_category: :duo_agent_platform do
  include GraphqlHelpers
  include ClickHouseHelpers

  let_it_be(:organization) { create(:organization, :public) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:group2) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:project2) { create(:project, group: group2) }

  # General engine access requires :read_pro_ai_analytics (reporter access with the
  # ai_analytics license). The creditsUsed measurement additionally requires the
  # :read_agent_artifacts custom ability granted via member roles (requires the
  # custom_roles license). A group-level role cascades to the group's projects.
  let_it_be(:member_role) { create(:member_role, :reporter, :read_agent_artifacts, namespace: group) }
  let_it_be(:member_role2) { create(:member_role, :reporter, :read_agent_artifacts, namespace: group2) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :reporter, member_role: member_role, user: current_user, group: group)
  end

  let_it_be(:group2_membership) do
    create(:group_member, :reporter, member_role: member_role2, user: current_user, group: group2)
  end

  let_it_be(:reporter) { create(:user, reporter_of: group) }
  let_it_be(:guest) { create(:user, guest_of: [group, group2]) }

  let_it_be(:user1) { create(:user) }
  let_it_be(:user2) { create(:user) }

  let(:statuses) { ::Ai::DuoWorkflows::Workflow.state_machines[:status].states }

  # Within group scope, user1: 2 flows, 2 flow types, 2 active days; user2: 1 flow, 1 flow type, 1 active day.
  let(:flows_data) do
    [
      { id: 1, user_id: user1.id, workflow_definition: 'chat', status: statuses[:finished].value,
        model_used: 'claude-sonnet-4-5', created_at: 10.days.ago, credits_used: 1.5, project: project,
        created_merge_request_ids: [101, 102], later_merged_merge_request_ids: [101] },
      { id: 2, user_id: user1.id, workflow_definition: 'software_development', status: statuses[:finished].value,
        model_used: 'claude-sonnet-4-5', created_at: 50.days.ago, credits_used: 2.5, project: project,
        created_merge_request_ids: [103], later_merged_merge_request_ids: [103] },
      { id: 3, user_id: user2.id, workflow_definition: 'fix_pipeline', status: statuses[:failed].value,
        model_used: 'claude-haiku-4-5', created_at: 12.days.ago, credits_used: 4.0, project: project,
        created_merge_request_ids: [104], later_closed_merge_request_ids: [104] },
      # group2 scope
      { id: 4, user_id: user2.id, workflow_definition: 'software_development', status: statuses[:running].value,
        model_used: 'claude-haiku-4-5', created_at: 9.days.ago, credits_used: 3.0, project: project2 }
    ]
  end

  let(:minimal_query) do
    <<~QUERY
      query {
        #{resource_query} {
          analytics {
            duoWorkflows#{field_arguments} { aggregated { nodes { totalCount } } }
          }
        }
      }
    QUERY
  end

  before do
    stub_licensed_features(
      ai_analytics: true,
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )
    allow(Gitlab::ClickHouse).to receive_messages(globally_enabled_for_analytics?: true, siphon_enabled?: true)

    clickhouse_fixture(:duo_workflows_workflows_enriched, flows_data.map do |flow|
      namespace = flow[:namespace] || (flow[:project] || project).project_namespace

      {
        id: flow[:id],
        user_id: flow[:user_id],
        project_id: flow[:namespace] ? nil : (flow[:project] || project).id,
        workflow_definition: flow.fetch(:workflow_definition, 'software_development'),
        status: flow.fetch(:status, 0),
        model_used: flow.fetch(:model_used, ''),
        created_at: flow[:created_at],
        updated_at: flow[:created_at],
        traversal_path: namespace.traversal_path(with_organization: true).to_s,
        credits_used: flow[:credits_used],
        created_merge_request_ids: Arel.sql("[#{flow.fetch(:created_merge_request_ids, []).join(', ')}]"),
        later_merged_merge_request_ids: Arel.sql("[#{flow.fetch(:later_merged_merge_request_ids, []).join(', ')}]"),
        later_closed_merge_request_ids: Arel.sql("[#{flow.fetch(:later_closed_merge_request_ids, []).join(', ')}]"),
        _siphon_deleted: false,
        _version: flow[:created_at]
      }
    end)
  end

  def full_paths_argument(*records)
    "[#{records.map { |record| "\"#{record.full_path}\"" }.join(', ')}]"
  end

  def field_arguments(filters = nil)
    args = [scope_arguments, filters].compact_blank.join("\n")

    args.blank? ? '' : "(#{args})"
  end

  shared_examples 'reports inaccessible sources' do
    it 'reports the requested sources as inaccessible for a guest' do
      post_graphql(minimal_query, current_user: guest)

      expect(graphql_errors).to match(
        [hash_including('message' => "The following sources are not accessible: #{inaccessible_source.full_path}")]
      )
    end

    it 'reports the requested sources as inaccessible when ai_analytics is not licensed' do
      stub_licensed_features(
        custom_roles: true,
        group_level_compliance_dashboard: true,
        project_level_compliance_dashboard: true
      )

      post_graphql(minimal_query, current_user: current_user)

      expect(graphql_errors).to match(
        [hash_including('message' => "The following sources are not accessible: #{inaccessible_source.full_path}")]
      )
    end
  end

  shared_examples 'reports resource not available when dap_impact_v1 is disabled' do
    before do
      stub_feature_flags(dap_impact_v1: false)
    end

    it 'returns a resource not available error' do
      post_graphql(minimal_query, current_user: current_user)

      expect(graphql_errors).to match(
        [hash_including('message' => '`dap_impact_v1` feature flag is disabled.')]
      )
    end
  end

  shared_examples 'duoWorkflows query' do
    context 'when querying all metrics, dimensions, and the measurement group' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments} {
                  aggregated {
                    nodes {
                      dimensions {
                        createdAt(granularity: "monthly")
                      }
                      totalCount
                      usersCount
                      flowTypesCount
                      creditsUsed {
                        min
                        max
                        mean
                        quantile
                        sum
                      }
                      createdMrCount { sum }
                      mergedMrCount { sum }
                      closedMrCount { sum }
                      openMrCount { sum }
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns aggregated flow data grouped by monthly buckets', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to match_array([
          {
            'dimensions' => { 'createdAt' => '2026-01-01' },
            'totalCount' => 2,
            'usersCount' => 2,
            'flowTypesCount' => 2,
            'creditsUsed' => {
              'min' => 1.5,
              'max' => 4.0,
              'mean' => 2.75,
              'quantile' => 2.75,
              'sum' => 5.5
            },
            'createdMrCount' => { 'sum' => 3 },
            'mergedMrCount' => { 'sum' => 1 },
            'closedMrCount' => { 'sum' => 1 },
            'openMrCount' => { 'sum' => 1 }
          },
          {
            'dimensions' => { 'createdAt' => '2025-12-01' },
            'totalCount' => 1,
            'usersCount' => 1,
            'flowTypesCount' => 1,
            'creditsUsed' => {
              'min' => 2.5,
              'max' => 2.5,
              'mean' => 2.5,
              'quantile' => 2.5,
              'sum' => 2.5
            },
            'createdMrCount' => { 'sum' => 1 },
            'mergedMrCount' => { 'sum' => 1 },
            'closedMrCount' => { 'sum' => 0 },
            'openMrCount' => { 'sum' => 0 }
          }
        ])
      end

      context 'when the user lacks the read_agent_artifacts custom ability' do
        let(:null_credits_used) do
          { 'min' => nil, 'max' => nil, 'mean' => nil, 'quantile' => nil, 'sum' => nil }
        end

        it 'returns null creditsUsed values but aggregates the other metrics',
          :aggregate_failures do
          post_graphql(query, current_user: reporter)

          expect(graphql_errors).to be_nil

          nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

          expect(nodes).to match_array([
            {
              'dimensions' => { 'createdAt' => '2026-01-01' },
              'totalCount' => 2,
              'usersCount' => 2,
              'flowTypesCount' => 2,
              'creditsUsed' => null_credits_used,
              'createdMrCount' => { 'sum' => 3 },
              'mergedMrCount' => { 'sum' => 1 },
              'closedMrCount' => { 'sum' => 1 },
              'openMrCount' => { 'sum' => 1 }
            },
            {
              'dimensions' => { 'createdAt' => '2025-12-01' },
              'totalCount' => 1,
              'usersCount' => 1,
              'flowTypesCount' => 1,
              'creditsUsed' => null_credits_used,
              'createdMrCount' => { 'sum' => 1 },
              'mergedMrCount' => { 'sum' => 1 },
              'closedMrCount' => { 'sum' => 0 },
              'openMrCount' => { 'sum' => 0 }
            }
          ])
        end

        context 'when creditsUsed is the only requested metric' do
          let(:query) do
            <<~QUERY
              query {
                #{resource_query} {
                  analytics {
                    duoWorkflows#{field_arguments} {
                      aggregated {
                        nodes {
                          creditsUsed { sum }
                        }
                      }
                    }
                  }
                }
              }
            QUERY
          end

          # Pruning the metric would leave the request empty, so this raises a typed
          # authorization error the frontend can map to an access state.
          it 'returns an authorization error with a stable extension code' do
            post_graphql(query, current_user: reporter)

            expect(graphql_errors).to match([hash_including(
              'message' => include("access to metric 'credits_used.sum' is not authorized"),
              'extensions' => hash_including('code' => 'AGGREGATION_NOT_AUTHORIZED')
            )])
          end
        end
      end
    end

    context 'when querying the retention window metrics' do
      # December users: user1, user2, reporter. January users: user1, guest.
      # January therefore has 1 returning, 1 joined and 2 churned users against a
      # previous period of 3, so joined and churned cannot be confused with each other.
      let(:flows_data) do
        [
          { id: 1, user_id: user1.id,       created_at: 50.days.ago, credits_used: 1.0, project: project },
          { id: 2, user_id: user2.id,       created_at: 50.days.ago, credits_used: 1.0, project: project },
          { id: 3, user_id: reporter.id,    created_at: 50.days.ago, credits_used: 1.0, project: project },
          { id: 4, user_id: user1.id,       created_at: 10.days.ago, credits_used: 1.0, project: project },
          { id: 5, user_id: guest.id,       created_at: 10.days.ago, credits_used: 1.0, project: project }
        ]
      end

      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments} {
                  aggregated {
                    nodes {
                      dimensions {
                        createdAt(granularity: "monthly")
                      }
                      usersCount
                      returningUsersCount
                      joinedUsersCount
                      churnedUsersCount
                      previousPeriodUsersCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns all four retention metrics per monthly bucket' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to match_array([
          {
            'dimensions' => { 'createdAt' => '2026-01-01' },
            'usersCount' => 2,
            'returningUsersCount' => 1,
            'joinedUsersCount' => 1,
            'churnedUsersCount' => 2,
            'previousPeriodUsersCount' => 3
          },
          {
            'dimensions' => { 'createdAt' => '2025-12-01' },
            'usersCount' => 3,
            'returningUsersCount' => 0,
            'joinedUsersCount' => 3,
            'churnedUsersCount' => 0,
            'previousPeriodUsersCount' => 0
          }
        ])
      end
    end

    context 'when filtering by flow type' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(%(workflowDefinition: ["fix_pipeline"]))} {
                  aggregated {
                    nodes {
                      dimensions {
                        workflowDefinition
                      }
                      totalCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'aggregates only flows with the given flow type' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{
          'dimensions' => { 'workflowDefinition' => 'fix_pipeline' },
          'totalCount' => 1
        }])
      end
    end

    context 'when filtering by status and grouping by status and model' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(%(status: ["finished"]))} {
                  aggregated {
                    nodes {
                      dimensions {
                        status
                        modelUsed
                      }
                      totalCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'aggregates only flows with the given status and returns state names' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{
          'dimensions' => { 'status' => 'finished', 'modelUsed' => 'claude-sonnet-4-5' },
          'totalCount' => 2
        }])
      end
    end

    context 'when counting by status within a single query' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments} {
                  aggregated {
                    nodes {
                      totalCount
                      finishedCount: totalCount(status: "finished")
                      failedOrRunningCount: totalCount(status: ["failed", "running"])
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns total and per-status counts from a single field', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{
          'totalCount' => 3,
          'finishedCount' => 2,
          'failedOrRunningCount' => 1
        }])
      end

      context 'when the status is not a known status name' do
        let(:query) do
          <<~QUERY
            query {
              #{resource_query} {
                analytics {
                  duoWorkflows#{field_arguments} {
                    aggregated {
                      nodes {
                        totalCount(status: "nonexistent")
                      }
                    }
                  }
                }
              }
            }
          QUERY
        end

        it 'returns an error' do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to match(
            [hash_including('message' => a_string_matching(/Invalid value\(s\) for parameter `status`: nonexistent/))]
          )
        end
      end
    end

    context 'when filtering by user and grouping by the user dimension' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(%(userId: ["#{user1.to_global_id}"]))} {
                  aggregated {
                    nodes {
                      dimensions {
                        user {
                          id
                        }
                      }
                      totalCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'aggregates only flows of the given user and resolves the user association' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{
          'dimensions' => { 'user' => { 'id' => user1.to_global_id.to_s } },
          'totalCount' => 2
        }])
      end
    end

    context 'when filtering by creation timestamp' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(%(
                  createdAtFrom: "#{30.days.ago.iso8601}"
                  createdAtTo: "#{5.days.ago.iso8601}"
                ))} {
                  aggregated {
                    nodes {
                      totalCount
                      usersCount
                      flowTypesCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'aggregates only flows created within the range' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{ 'totalCount' => 2, 'usersCount' => 2, 'flowTypesCount' => 2 }])
      end
    end

    context 'when filtering by project' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(%(projectId: ["#{filtered_project.to_global_id}"]))} {
                  aggregated {
                    nodes {
                      dimensions {
                        project { id }
                      }
                      totalCount
                      projectsCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      context 'when the project has flows' do
        let(:filtered_project) { project }

        it 'aggregates only that project and resolves the project association', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil

          nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

          expect(nodes).to eq([
            {
              'dimensions' => { 'project' => { 'id' => project.to_global_id.to_s } },
              'totalCount' => 3,
              'projectsCount' => 1
            }
          ])
        end
      end

      context 'when the project has no flows in the requested scope' do
        let(:filtered_project) { project2 }

        it 'returns no nodes', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil

          nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

          expect(nodes).to be_empty
        end
      end
    end

    context 'when bucketing users by activity tier' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments} {
                  aggregated {
                    nodes {
                      dimensions {
                        userTier(thresholds: [2])
                      }
                      totalCount
                      usersCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns flow and user counts per tier' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to match_array([
          { 'dimensions' => { 'userTier' => 'tier_0' }, 'totalCount' => 1, 'usersCount' => 1 },
          { 'dimensions' => { 'userTier' => 'tier_1' }, 'totalCount' => 2, 'usersCount' => 1 }
        ])
      end

      context 'without the thresholds argument' do
        let(:query) do
          <<~QUERY
            query {
              #{resource_query} {
                analytics {
                  duoWorkflows#{field_arguments} {
                    aggregated {
                      nodes {
                        dimensions {
                          userTier
                        }
                        usersCount
                      }
                    }
                  }
                }
              }
            }
          QUERY
        end

        it 'returns a validation error' do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to match(
            [hash_including('message' => a_string_matching(/parameter `thresholds` is required/))]
          )
        end
      end
    end

    context 'when filtering by per-user activity' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(filter_arguments)} {
                  aggregated {
                    nodes {
                      usersCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      subject(:users_count) do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes', 0, 'usersCount')
      end

      context 'with flowTypesUsed' do
        let(:filter_arguments) { 'flowTypesUsedFrom: 2' }

        it 'counts users who ran at least two flow types' do
          expect(users_count).to eq(1)
        end
      end

      context 'with activeDays' do
        let(:filter_arguments) { 'activeDaysFrom: 1, activeDaysTo: 1' }

        it 'counts users active on exactly one day' do
          expect(users_count).to eq(1)
        end
      end
    end
  end

  context 'for group' do
    let(:query_type) { 'group' }
    let(:resource_query) { %(group(fullPath: "#{group.full_path}")) }
    let(:scope_arguments) { '' }
    let(:inaccessible_source) { group }

    it_behaves_like 'duoWorkflows query'
    it_behaves_like 'reports inaccessible sources'
    it_behaves_like 'reports resource not available when dap_impact_v1 is disabled'
    it_behaves_like 'a Siphon-dependent aggregation engine' do
      let(:siphon_query) { minimal_query }
    end

    context 'when bucketing by a fixed number of days anchored at an origin' do
      let(:origin) { '2026-01-01T00:00:00Z' }
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows {
                  aggregated(
                    orderBy: [
                      { identifier: "createdAt", direction: ASC, parameters: { granularity: "30d", origin: "#{origin}" } }
                    ]
                  ) {
                    nodes {
                      dimensions {
                        period: createdAt(granularity: "30d", origin: "#{origin}")
                      }
                      totalCount
                      usersCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns the previous and current 30-day periods in one response', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig('group', 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        # Flows created 2025-12-11 fall in the previous period [2025-12-02, 2026-01-01);
        # flows created 2026-01-18 and 2026-01-20 fall in the current one [2026-01-01, 2026-01-31).
        expect(nodes).to eq([
          { 'dimensions' => { 'period' => '2025-12-02' }, 'totalCount' => 1, 'usersCount' => 1 },
          { 'dimensions' => { 'period' => '2026-01-01' }, 'totalCount' => 2, 'usersCount' => 2 }
        ])
      end

      it 'rejects an origin combined with a calendar granularity' do
        query = <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows {
                  aggregated {
                    nodes { dimensions { createdAt(granularity: "monthly", origin: "#{origin}") } }
                  }
                }
              }
            }
          }
        QUERY

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to match(
          [hash_including('message' => a_string_matching(/Parameter `origin` requires a dynamic day granularity/))]
        )
      end
    end

    context 'when flows span several projects and a namespace-level flow' do
      let_it_be(:sibling_project) { create(:project, group: group) }

      let(:flows_data) do
        [
          { id: 1, user_id: user1.id, project: project,         created_at: 10.days.ago, credits_used: 1.0 },
          { id: 2, user_id: user1.id, project: sibling_project, created_at: 10.days.ago, credits_used: 2.0 },
          # A flow not scoped to a project sits directly on the group path.
          { id: 3, user_id: user2.id, namespace: group,         created_at: 10.days.ago, credits_used: 4.0 }
        ]
      end

      it 'resolves the project association and returns null for namespace-level flows', :aggregate_failures do
        query = <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows {
                  aggregated {
                    nodes {
                      dimensions {
                        project { id }
                      }
                      totalCount
                      creditsUsed { sum }
                    }
                  }
                }
              }
            }
          }
        QUERY

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig('group', 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to match_array([
          {
            'dimensions' => { 'project' => { 'id' => project.to_global_id.to_s } },
            'totalCount' => 1,
            'creditsUsed' => { 'sum' => 1.0 }
          },
          {
            'dimensions' => { 'project' => { 'id' => sibling_project.to_global_id.to_s } },
            'totalCount' => 1,
            'creditsUsed' => { 'sum' => 2.0 }
          },
          {
            'dimensions' => { 'project' => nil },
            'totalCount' => 1,
            'creditsUsed' => { 'sum' => 4.0 }
          }
        ])
      end

      it 'counts distinct projects without the namespace-level flow', :aggregate_failures do
        query = <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows {
                  aggregated {
                    nodes {
                      totalCount
                      projectsCount
                    }
                  }
                }
              }
            }
          }
        QUERY

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        nodes = graphql_data.dig('group', 'analytics', 'duoWorkflows', 'aggregated', 'nodes')

        expect(nodes).to eq([{ 'totalCount' => 3, 'projectsCount' => 2 }])
      end
    end

    context 'when flows span a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }

      let(:flows_data) do
        [
          { id: 1, user_id: user1.id, namespace: group,           created_at: 10.days.ago, credits_used: 1.0 },
          { id: 2, user_id: user1.id, namespace: subgroup,        created_at: 10.days.ago, credits_used: 2.0 },
          { id: 3, user_id: user2.id, project: subgroup_project,  created_at: 10.days.ago, credits_used: 4.0 }
        ]
      end

      let(:nodes) { graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes') }
      let(:query) { group_query }

      def group_query(filters = nil)
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoWorkflows#{field_arguments(filters)} {
                  aggregated {
                    nodes {
                      dimensions {
                        group(depth: 2) { id fullPath }
                      }
                      totalCount
                      creditsUsed { sum }
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns flows and credits per subgroup, with a null group above that depth',
        :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(nodes).to match_array([
          {
            'dimensions' => { 'group' => { 'id' => subgroup.to_global_id.to_s, 'fullPath' => subgroup.full_path } },
            'totalCount' => 2,
            'creditsUsed' => { 'sum' => 6.0 }
          },
          {
            'dimensions' => { 'group' => nil },
            'totalCount' => 1,
            'creditsUsed' => { 'sum' => 1.0 }
          }
        ])
      end

      it 'filters down to the subgroup subtree, including its projects', :aggregate_failures do
        post_graphql(group_query(%(groupId: ["#{subgroup.to_global_id}"])), current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(nodes).to match_array([
          {
            'dimensions' => { 'group' => { 'id' => subgroup.to_global_id.to_s, 'fullPath' => subgroup.full_path } },
            'totalCount' => 2,
            'creditsUsed' => { 'sum' => 6.0 }
          }
        ])
      end

      it 'does not run policy or route queries per group' do
        # The first request warms request-independent caches, so it is not a fair baseline.
        post_graphql(query, current_user: current_user)
        control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

        extra_subgroups = create_list(:group, 2, :private, parent: group)
        clickhouse_fixture(:duo_workflows_workflows_enriched, extra_subgroups.each_with_index.map do |sub, index|
          {
            id: 10 + index,
            user_id: user1.id,
            project_id: nil,
            workflow_definition: 'software_development',
            status: statuses[:finished].value,
            model_used: '',
            created_at: 8.days.ago,
            updated_at: 8.days.ago,
            traversal_path: sub.traversal_path(with_organization: true).to_s,
            credits_used: 1.0,
            _siphon_deleted: false,
            _version: 8.days.ago
          }
        end)

        expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      end
    end
  end

  context 'for project' do
    let(:query_type) { 'project' }
    let(:resource_query) { %(project(fullPath: "#{project.full_path}")) }
    let(:scope_arguments) { '' }
    let(:inaccessible_source) { project }

    it_behaves_like 'duoWorkflows query'
    it_behaves_like 'reports inaccessible sources'
    it_behaves_like 'reports resource not available when dap_impact_v1 is disabled'
  end

  context 'for organization' do
    let(:query_type) { 'organization' }
    let(:resource_query) { %(organization(id: "#{organization.to_global_id}")) }
    let(:scope_arguments) { %(descendantsScope: { groupFullPaths: #{full_paths_argument(group)} }) }
    let(:inaccessible_source) { group }

    it_behaves_like 'duoWorkflows query'
    it_behaves_like 'reports inaccessible sources'

    context 'when requesting multiple groups' do
      let(:scope_arguments) { %(descendantsScope: { groupFullPaths: #{full_paths_argument(group, group2)} }) }

      it 'aggregates data across the requested groups' do
        post_graphql(minimal_query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes'))
          .to eq([{ 'totalCount' => 4 }])
      end
    end

    context 'when requesting a mix of groups and projects' do
      let(:scope_arguments) do
        <<~ARGS
          descendantsScope: {
            groupFullPaths: #{full_paths_argument(group)}
            projectFullPaths: #{full_paths_argument(project2)}
          }
        ARGS
      end

      it 'aggregates data from both the group and the project' do
        post_graphql(minimal_query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(graphql_data.dig(query_type, 'analytics', 'duoWorkflows', 'aggregated', 'nodes'))
          .to eq([{ 'totalCount' => 4 }])
      end
    end
  end
end
