# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Create scan execution policy for a project/namespace', feature_category: :security_policy_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, namespace: current_user.namespace) }
  let_it_be(:namespace) { create(:group) }
  let_it_be(:project_security_policy_management_project) { create(:project, :repository, namespace: current_user.namespace) }
  let_it_be(:namespace_security_policy_management_project) { create(:project, :repository, namespace: namespace) }
  let_it_be(:policy_name) { 'Test Policy' }
  let_it_be(:policy_yaml) { build(:scan_execution_policy, name: policy_name).merge(type: 'scan_execution_policy').to_yaml }

  def mutation
    variables = { full_path: container.full_path, name: policy_name, policy_yaml: policy_yaml, operation_mode: 'APPEND' }

    graphql_mutation(:scan_execution_policy_commit, variables) do
      <<-QL.strip_heredoc
        clientMutationId
        errors
        branch
      QL
    end
  end

  def mutation_response
    graphql_mutation_response(:scan_execution_policy_commit)
  end

  shared_context 'commits scan execution policies' do
    before do
      container.add_maintainer(current_user)
      container_security_policy_management_project.add_developer(current_user)

      stub_licensed_features(security_orchestration_policies: true)
    end

    it 'creates a branch with commit' do
      post_graphql_mutation(mutation, current_user: current_user)

      branch = mutation_response['branch']
      commit = container_security_policy_management_project.repository.commits(branch, limit: 5).first
      expect(response).to have_gitlab_http_status(:success)
      expect(branch).not_to be_nil
      expect(commit.message).to eq('Add a new policy to .gitlab/security-policies/policy.yml')
    end

    context 'when provided policy is invalid' do
      let_it_be(:policy_yaml) { build(:scan_execution_policy, name: policy_name).merge(type: 'scan_execution_policy', rules: [{ type: 'invalid_type', branches: ['master'] }]).to_yaml }

      it 'returns error with detailed information' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to eq(['Invalid policy YAML', "property '/scan_execution_policy/0/rules/0/type' is not one of: [\"pipeline\", \"schedule\"]"])
      end
    end

    context 'when current_user is a security_manager' do
      let_it_be(:security_manager_user) { create(:user) }

      before do
        container.add_security_manager(security_manager_user)
        container_security_policy_management_project.add_security_manager(security_manager_user)
      end

      it 'creates a branch with commit' do
        post_graphql_mutation(mutation, current_user: security_manager_user)

        branch = mutation_response['branch']
        commit = container_security_policy_management_project.repository.commits(branch, limit: 5).first
        expect(response).to have_gitlab_http_status(:success)
        expect(branch).not_to be_nil
        expect(commit.message).to eq('Add a new policy to .gitlab/security-policies/policy.yml')
      end
    end
  end

  context 'for project' do
    let(:container_security_policy_management_project) { project_security_policy_management_project }

    let_it_be(:policy_configuration) { create(:security_orchestration_policy_configuration, project: project, security_policy_management_project: project_security_policy_management_project) }

    let(:container) { project }

    it_behaves_like 'commits scan execution policies'
  end

  context 'for namespace' do
    let(:container_security_policy_management_project) { namespace_security_policy_management_project }

    let_it_be(:policy_configuration) { create(:security_orchestration_policy_configuration, :namespace, namespace: namespace, security_policy_management_project: namespace_security_policy_management_project) }

    let(:container) { namespace }

    it_behaves_like 'commits scan execution policies'
  end

  context 'with granular token authorization' do
    let_it_be(:project_policy_configuration) do
      create(:security_orchestration_policy_configuration, project: project,
        security_policy_management_project: project_security_policy_management_project)
    end

    let_it_be(:namespace_policy_configuration) do
      create(:security_orchestration_policy_configuration, :namespace, namespace: namespace,
        security_policy_management_project: namespace_security_policy_management_project)
    end

    before_all do
      project.add_maintainer(current_user)
      project_security_policy_management_project.add_developer(current_user)
      namespace.add_maintainer(current_user)
      namespace_security_policy_management_project.add_developer(current_user)
    end

    before do
      stub_licensed_features(security_orchestration_policies: true)

      # The service derives the branch name from `Time.now.to_i`, so two
      # successful mutations within the same second (the legacy and granular
      # token "grants access" examples) would create the same branch on the
      # persisted `let_it_be` policy management project repository, failing
      # with "branch already exists". Give each execution a unique name.
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyCommitService) do |service|
        allow(service).to receive(:branch_name).and_return("update-policy-#{SecureRandom.uuid}")
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_policy do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) do
        graphql_mutation(:scan_execution_policy_commit,
          { full_path: project.full_path, name: policy_name, policy_yaml: policy_yaml, operation_mode: 'APPEND' },
          'errors branch')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_policy do
      let(:user) { current_user }
      let(:boundary_object) { namespace }
      let(:mutation) do
        graphql_mutation(:scan_execution_policy_commit,
          { full_path: namespace.full_path, name: policy_name, policy_yaml: policy_yaml, operation_mode: 'APPEND' },
          'errors branch')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
