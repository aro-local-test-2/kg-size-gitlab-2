# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CD environments Integration (GraphQL fixtures)', type: :request,
  feature_category: :continuous_delivery do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:organization) { create(:organization) }
  # The index spec asserts on the deploying user's username, so it is pinned here rather
  # than left to the User factory sequence, which is shared across every fixture spec.
  let_it_be(:user) do
    create(:organization_user, :owner, organization: organization,
      user: create(:user, username: 'cd-deployer', organizations: [])).user
  end

  let_it_be(:agent_project) { create(:project, organization: organization) }
  let_it_be(:production_agent) { create(:cluster_agent, project: agent_project, name: 'production-cluster') }
  let_it_be(:staging_agent) { create(:cluster_agent, project: agent_project, name: 'staging-cluster') }

  # The connection returns newest first, and the list fixtures below are capped at
  # PAGE_SIZE so the app can exercise "Load more". Creation order therefore decides
  # which environments land on the first page: the two richest ones go last.
  let_it_be(:staging) do
    create(:cd_environment, :staging, organization: organization, name: 'staging-eu')
  end

  let_it_be(:development) do
    create(:cd_environment, :development, organization: organization, name: 'dev-sandbox')
  end

  let_it_be(:production) do
    create(:cd_environment, :production, organization: organization, name: 'production-eu')
  end

  # driver_config is opaque to the backend and holds the raw numeric agent id, while
  # cdAvailableAgents returns global ids. The cards join the two, so the fixtures have
  # to carry ids of agents that the agents fixture actually returns.
  let_it_be(:production_binding) do
    create(:cd_environment_driver_binding, environment: production,
      driver_config: { 'cluster_agent_id' => production_agent.id.to_s })
  end

  let_it_be(:staging_binding) do
    create(:cd_environment_driver_binding, environment: staging,
      driver_config: { 'cluster_agent_id' => staging_agent.id.to_s })
  end

  let_it_be(:checkout_app) { create(:cd_application, organization: organization, name: 'checkout') }
  let_it_be(:payments_app) { create(:cd_application, organization: organization, name: 'payments') }

  let_it_be(:production_checkout_health) do
    create(:cd_service_environment_health, environment: production, health: :healthy,
      service: create(:cd_service, application: checkout_app))
  end

  let_it_be(:production_payments_health) do
    create(:cd_service_environment_health, environment: production, health: :healthy,
      service: create(:cd_service, application: payments_app))
  end

  let_it_be(:staging_health) do
    create(:cd_service_environment_health, environment: staging, health: :degraded,
      service: create(:cd_service, application: checkout_app))
  end

  let_it_be(:version_set) do
    create(:cd_version_set, application: checkout_app, name: 'release-2026.08.1')
  end

  let_it_be(:rollout) do
    create(:cd_rollout, application: checkout_app, version_set: version_set, state: :completed,
      workflow_ref: 'autoflow/rollout/1', started_at: Time.utc(2026, 8, 20, 9, 45, 0))
  end

  let_it_be(:rollout_transition) do
    create(:cd_rollout_transition, rollout: rollout, principal: "user:#{user.id}")
  end

  let_it_be(:rollout_environment) do
    create(:cd_rollout_environment, rollout: rollout, environment: production,
      driver_binding: production_binding, state: :completed,
      finished_at: Time.utc(2026, 8, 20, 10, 0, 0))
  end

  base_output_path = 'graphql/cd/integration/'
  environments_query = 'cd/graphql/environments/cd_environments.query.graphql'

  # Mirrors ENVIRONMENTS_PAGE_SIZE and the search term the index spec types.
  page_size = 50
  search_term = 'prod'

  # The app always asks for ENVIRONMENTS_PAGE_SIZE, so capping the resolver is the only
  # way to record a real paginated response without seeding 50+ environments.
  fixture_page_size = 2

  before do
    stub_current_organization(organization)
    allow(Resolvers::Cd::OrganizationEnvironmentsResolver)
      .to receive(:max_page_size).and_return(fixture_page_size)
  end

  def environments_page_info
    graphql_dig_at(graphql_data, :organization, :cd_environments, :page_info)
  end

  describe GraphQL::Query do
    it "#{base_output_path}cd_environments.query.graphql.json" do
      query = get_graphql_query_as_string(environments_query, ee: true)

      post_graphql(query, current_user: user, variables: { search: '', tier: nil, first: page_size })

      expect_graphql_errors_to_be_empty
      # Guards the fixture's purpose: without a next page the load-more spec tests nothing.
      expect(environments_page_info['hasNextPage']).to be(true)
    end

    it "#{base_output_path}cd_environments_next_page.query.graphql.json" do
      query = get_graphql_query_as_string(environments_query, ee: true)

      post_graphql(query, current_user: user, variables: { search: '', tier: nil, first: page_size })

      expect_graphql_errors_to_be_empty
      cursor = environments_page_info['endCursor']

      post_graphql(query, current_user: user,
        variables: { search: '', tier: nil, first: page_size, after: cursor })

      expect_graphql_errors_to_be_empty
      expect(environments_page_info['hasNextPage']).to be(false)
    end

    it "#{base_output_path}cd_environments_production_tier.query.graphql.json" do
      query = get_graphql_query_as_string(environments_query, ee: true)

      post_graphql(query, current_user: user,
        variables: { search: '', tier: 'PRODUCTION', first: page_size })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}cd_environments_search.query.graphql.json" do
      query = get_graphql_query_as_string(environments_query, ee: true)

      post_graphql(query, current_user: user,
        variables: { search: search_term, tier: nil, first: page_size })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}cd_environment_tiers.query.graphql.json" do
      query = get_graphql_query_as_string('cd/graphql/environments/cd_environment_tiers.query.graphql', ee: true)

      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}cd_available_agents.query.graphql.json" do
      query = get_graphql_query_as_string('cd/graphql/environments/cd_available_agents.query.graphql', ee: true)

      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'mutations' do
    it "#{base_output_path}cd_environment_create.mutation.graphql.json" do
      query = get_graphql_query_as_string('cd/graphql/environments/cd_environment_create.mutation.graphql', ee: true)

      # Serialized up front because post_graphql camelizes nested variable keys, which would
      # rename the driver's own snake_case driver_config properties.
      variables = Gitlab::Json.dump({
        input: {
          organizationId: organization.to_global_id.to_s,
          name: 'production-ap',
          tier: 'PRODUCTION',
          environmentDriverBinding: {
            driverRef: 'argo-rollouts',
            driverConfig: { cluster_agent_id: production_agent.id.to_s }
          }
        }
      })

      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty
    end
  end
end
