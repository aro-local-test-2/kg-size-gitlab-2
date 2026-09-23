# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PipelineExecutionSchedulePolicyTestRun', feature_category: :security_policy_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:policy_management_project) { create(:project) }
  let_it_be(:current_user) { create(:user) }

  let_it_be(:policy_configuration) do
    create(:security_orchestration_policy_configuration,
      project: project,
      security_policy_management_project: policy_management_project)
  end

  let_it_be(:policy) do
    create(:security_policy, :pipeline_execution_schedule_policy,
      security_orchestration_policy_configuration: policy_configuration,
      security_policy_management_project: policy_management_project)
  end

  let(:input) do
    {
      projectPath: project.full_path,
      policyId: policy.to_global_id.to_s
    }
  end

  let(:mutation) { graphql_mutation(:pipeline_execution_schedule_policy_test_run, input, test_run_fields) }

  def test_run_fields
    <<~FIELDS
      testRun {
        id
        state
      }
      errors
    FIELDS
  end

  def mutation_result
    graphql_mutation_response(:pipeline_execution_schedule_policy_test_run)
  end

  before_all do
    project.add_developer(current_user)
    policy_management_project.add_developer(current_user)
  end

  before do
    stub_licensed_features(security_orchestration_policies: true)
  end

  describe 'GraphQL mutation' do
    context 'when user has permissions' do
      it_behaves_like 'authorizing granular token permissions for GraphQL', :create_policy_schedule_test_run do
        let(:user) { current_user }
        let(:boundary_object) { project }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      it 'triggers a test run' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .to change { Security::ScheduledPipelineExecutionPolicyTestRun.count }.by(1)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_result['errors']).to be_empty
        expect(mutation_result['testRun']).to include('state' => 'PENDING')
      end
    end
  end
end
