# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Duo Agent Platform recent session projects', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :private, group: group, developers: user) }
  let_it_be(:other_project) { create(:project, :private, group: group, developers: user) }

  let(:query) do
    graphql_query_for(:duo_workflow_recent_session_projects, {}, 'id fullPath nameWithNamespace')
  end

  let(:recent_session_projects) { graphql_data_at(:duo_workflow_recent_session_projects) }

  it 'returns the projects the current user has sessions in' do
    create(:duo_workflows_workflow, project: other_project, user: user, updated_at: 2.days.ago)
    create(:duo_workflows_workflow, project: project, user: user, updated_at: 1.hour.ago)

    post_graphql(query, current_user: user)

    expect(recent_session_projects).to match([
      a_graphql_entity_for(project, :full_path, :name_with_namespace),
      a_graphql_entity_for(other_project, :full_path, :name_with_namespace)
    ])
  end

  it 'returns nothing for an anonymous request' do
    create(:duo_workflows_workflow, project: project, user: user)

    post_graphql(query)

    expect(recent_session_projects).to be_empty
  end

  it 'avoids N+1 queries' do
    create(:duo_workflows_workflow, project: project, user: user)

    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }

    create(:duo_workflows_workflow, project: other_project, user: user)

    expect { post_graphql(query, current_user: user) }.not_to exceed_query_limit(control)
  end
end
