# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'KnowledgeGraphExcludedNamespaceDestroy mutation', :enable_admin_mode,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  let(:current_user) { admin }
  let(:mutation) { graphql_mutation(:knowledge_graph_excluded_namespace_destroy, group_path: group.full_path) }

  before do
    create(:knowledge_graph_excluded_namespace, namespace: group)
    stub_feature_flags(knowledge_graph: true)
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL',
    :update_knowledge_graph_setting do
    let(:user) { admin }
    let(:boundary_object) { :instance }
    let(:mutation) do
      graphql_mutation(:knowledge_graph_excluded_namespace_destroy, { group_path: group.full_path }, 'errors')
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  it 'removes the group exclusion' do
    expect { post_graphql_mutation(mutation, current_user: current_user) }
      .to change { Analytics::KnowledgeGraph::ExcludedNamespace.count }.by(-1)

    expect(graphql_mutation_response(:knowledge_graph_excluded_namespace_destroy)).to include(
      'group' => hash_including('id' => group.to_global_id.to_s),
      'errors' => be_empty
    )
  end

  context 'when the group is not excluded' do
    before do
      Analytics::KnowledgeGraph::ExcludedNamespace.where(root_namespace_id: group.id).delete_all
    end

    it 'succeeds without changing exclusions' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { Analytics::KnowledgeGraph::ExcludedNamespace.count }

      expect(graphql_mutation_response(:knowledge_graph_excluded_namespace_destroy)).to include(
        'group' => hash_including('id' => group.to_global_id.to_s),
        'errors' => be_empty
      )
    end
  end

  context 'when on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    it 'returns a top-level access error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(
        "The resource that you are attempting to access does not exist or you don't have permission"
      )
    end
  end

  context 'when the current user is not an admin' do
    let(:current_user) { user }

    it 'returns a top-level access error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(
        "The resource that you are attempting to access does not exist or you don't have permission"
      )
    end
  end
end
