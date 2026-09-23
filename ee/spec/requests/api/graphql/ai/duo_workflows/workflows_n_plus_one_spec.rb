# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Duo Workflows across many containers', :saas, feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }

  # Mirrors ee/app/assets/javascripts/ai/graphql/get_user_workflow.query.graphql.
  let(:fields) do
    <<~GRAPHQL
      pageInfo { endCursor hasNextPage }
      edges { node { id lastUpdatedAt: updatedAt title: goal aiCatalogItemVersionId agentName archived } }
    GRAPHQL
  end

  let(:query) { graphql_query_for('duoWorkflowWorkflows', { first: 20 }, fields) }

  include_context 'with duo features enabled and agentic chat available for group on SaaS'

  before do
    create(:gitlab_subscription, :ultimate, namespace: group)
    stub_licensed_features(agentic_chat: true, ai_workflows: true)
  end

  def returned_workflows
    graphql_data.dig('duoWorkflowWorkflows', 'edges')
  end

  # Group#duo_features_enabled and Project#duo_features_enabled cascade through
  # the ancestors with one namespace_settings read per container. Those reads
  # are not part of the N+1 this spec guards.
  shared_examples 'a page whose query count does not grow with its size' do
    it 'authorizes the page without one query per container', :request_store, :aggregate_failures do
      create_workflows(2)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: user)
      end

      expect(response).to have_gitlab_http_status(:ok)
      expect(returned_workflows.size).to eq(2)

      create_workflows(4)

      expect do
        post_graphql(query, current_user: user)
      end.not_to exceed_all_query_limit(control).ignoring(/FROM "namespace_settings"/)

      expect(returned_workflows.size).to eq(6)
    end
  end

  context 'with chat sessions in distinct projects' do
    def create_workflows(count)
      count.times do
        create(:duo_workflows_workflow, :agentic_chat, project: create(:project, group: group), user: user)
      end
    end

    it_behaves_like 'a page whose query count does not grow with its size'
  end

  context 'with chat sessions in distinct subgroups' do
    def create_workflows(count)
      count.times do
        create(:duo_workflows_workflow, :agentic_chat, namespace: create(:group, parent: group), user: user)
      end
    end

    it_behaves_like 'a page whose query count does not grow with its size'
  end

  context 'with flow sessions in distinct projects' do
    def create_workflows(count)
      count.times do
        create(:duo_workflows_workflow, project: create(:project, group: group), user: user,
          workflow_definition: 'software_development')
      end
    end

    it_behaves_like 'a page whose query count does not grow with its size'
  end
end
