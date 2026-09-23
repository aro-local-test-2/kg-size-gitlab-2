# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group(fullPath).ciVariables', feature_category: :pipeline_composition do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:variable) { create(:ci_group_variable, group: group, key: 'GROUP_TOKEN') }
  let_it_be(:hidden_variable) do
    create(:ci_group_variable, group: group, key: 'HIDDEN_GROUP_TOKEN', masked: true, hidden: true)
  end

  it_behaves_like 'auditing CI/CD variable value access' do
    let(:audit_scope) { group }
    let(:auth_user) { owner }
    let(:variable_key) { variable.key }
    let(:hidden_variable_key) { hidden_variable.key }

    def variables_query(fields)
      <<~GQL
        query {
          group(fullPath: "#{group.full_path}") {
            ciVariables { nodes { #{fields.join(' ')} } }
          }
        }
      GQL
    end
  end

  describe 'recording variable value access' do
    let_it_be(:warmup_user) { create(:user, owner_of: group) }
    let_it_be(:control_user) { create(:user, owner_of: group) }
    let_it_be(:action_user) { create(:user, owner_of: group) }

    let(:value_query) do
      graphql_query_for('group', { 'fullPath' => group.full_path },
        query_graphql_field('ciVariables', {}, query_graphql_field('nodes', {}, %w[key value])))
    end

    before do
      stub_licensed_features(audit_events: true)
    end

    # A different user per request avoids false positives from authentication
    # queries that only run on a user's first request.
    it 'avoids N+1 queries when resolving the variable owner', :request_store, :use_sql_query_cache do
      create(:ci_group_variable, group: group)
      post_graphql(value_query, current_user: warmup_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(value_query, current_user: control_user)
      end

      create_list(:ci_group_variable, 3, group: group)

      expect do
        post_graphql(value_query, current_user: action_user)
      end.to issue_same_number_of_queries_as(control)
    end
  end
end
