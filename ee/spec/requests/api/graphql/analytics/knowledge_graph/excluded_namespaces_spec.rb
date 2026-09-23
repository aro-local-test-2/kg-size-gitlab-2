# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Knowledge Graph excluded namespaces', :enable_admin_mode,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }
  let_it_be(:excluded_group) { create(:group, name: 'Excluded group') }
  let_it_be(:other_group) { create(:group) }

  let(:current_user) { admin }
  let(:query) do
    graphql_query_for(:knowledge_graph_excluded_namespaces, {}, 'nodes { id name fullPath webPath avatarUrl }')
  end

  before do
    create(:knowledge_graph_excluded_namespace, namespace: excluded_group)
    stub_feature_flags(knowledge_graph: true)
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  it 'returns excluded top-level groups' do
    post_graphql(query, current_user: current_user)

    expect(graphql_data_at(:knowledge_graph_excluded_namespaces, :nodes)).to contain_exactly(
      hash_including(
        'id' => excluded_group.to_global_id.to_s,
        'fullPath' => excluded_group.full_path,
        'webPath' => excluded_group.web_url(only_path: true)
      )
    )
  end

  context 'when on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    it 'returns a top-level access error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include(
        "The resource that you are attempting to access does not exist or you don't have permission"
      )
    end
  end

  context 'when the current user is not an admin' do
    let(:current_user) { user }

    it 'returns a top-level access error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include(
        "The resource that you are attempting to access does not exist or you don't have permission"
      )
    end
  end
end
