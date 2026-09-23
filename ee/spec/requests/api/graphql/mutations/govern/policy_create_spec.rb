# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a policy in the policy store', :policy_store, feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let(:current_user) { organization_owner }

  let(:params) do
    {
      organization_id: organization.to_global_id.to_s,
      name: 'Block production deployments',
      description: 'Blocks deployments to production during the freeze window',
      trigger_type: 'deployment_requested',
      rules: [{ type: 'environment', value: { names: %w[production] } }],
      actions: [{ type: 'block' }],
      mode: 'enforce'
    }
  end

  let(:mutation) { graphql_mutation(:govern_policy_create, params) }

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:govern_policy_create)
  end

  it 'creates the policy and returns it', :aggregate_failures do
    request

    expect_graphql_errors_to_be_empty
    expect(mutation_response['errors']).to eq([])
    expect(mutation_response['policy']).to match(a_hash_including(
      'organizationId' => organization.id,
      'name' => 'Block production deployments',
      'description' => 'Blocks deployments to production during the freeze window',
      'triggerType' => 'deployment_requested',
      # The store enriches each rule with its compiled `rego` program, so assert
      # only the authored keys.
      'rules' => [a_hash_including('type' => 'environment', 'value' => { 'names' => ['production'] })],
      'actions' => [{ 'type' => 'block' }],
      'mode' => 'enforce'
    ))

    created_policy = ::Gitlab::PolicyStore.find(mutation_response.dig('policy', 'id'))
    expect(created_policy.name).to eq('Block production deployments')
    expect(created_policy.organization_id).to eq(organization.id)
  end

  def organization_policies
    ::Gitlab::PolicyStore.list(organization_id: organization.id)
  end

  context 'when the rules are empty' do
    let(:params) { super().merge(rules: []) }

    # A policy needs at least one rule. The store itself permits empty rules, so the
    # argument validation is the only layer enforcing this for GraphQL writes.
    it 'rejects the argument without creating a policy', :aggregate_failures do
      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => a_string_including('rules')))
      expect(organization_policies).to be_empty
    end
  end

  context 'when the rules exceed the maximum array size' do
    let(:params) do
      super().merge(rules: Array.new(::Types::BaseArgument::MAX_ARRAY_SIZE + 1) { { type: 'environment' } })
    end

    it 'rejects the argument without creating a policy', :aggregate_failures do
      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => a_string_including('rules')))
      expect(organization_policies).to be_empty
    end
  end

  context 'when the actions exceed the maximum array size' do
    let(:params) do
      super().merge(actions: Array.new(::Types::BaseArgument::MAX_ARRAY_SIZE + 1) { { type: 'block' } })
    end

    it 'rejects the argument without creating a policy', :aggregate_failures do
      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => a_string_including('actions')))
      expect(organization_policies).to be_empty
    end
  end

  context 'when the policy is invalid for the store' do
    let(:params) { super().merge(name: '') }

    it 'returns the validation message without creating a policy', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['policy']).to be_nil
      expect(mutation_response['errors']).to contain_exactly(a_string_including('name'))
      expect(organization_policies).to be_empty
    end
  end

  context 'when the service fails for an unmapped reason' do
    before do
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::CreateService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'store internals', reason: :unavailable)
        )
      end
    end

    it 'tracks the reason and surfaces a generic error', :aggregate_failures do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(Mutations::Govern::PolicyCreate::UnmappedReasonError),
        service_message: 'store internals'
      )

      request

      expect(graphql_errors).to contain_exactly(
        a_hash_including('message' => Mutations::Govern::PolicyCreate::UNMAPPED_REASON_MESSAGE)
      )
    end
  end

  context 'when the service reports an engine fault' do
    before do
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::CreateService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'rules[0] could not be validated', reason: :engine_error)
        )
      end
    end

    it 'surfaces the message as a top-level error without tracking it again' do
      expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => 'rules[0] could not be validated'))
    end
  end

  context 'when both policy_scope and scope_rego are provided' do
    let(:params) do
      super().merge(
        policy_scope: { projects: { including: [1] } },
        scope_rego: 'package policy'
      )
    end

    it 'returns the conflicting scope message without creating a policy', :aggregate_failures do
      request

      expect(mutation_response['policy']).to be_nil
      expect(mutation_response['errors']).to contain_exactly(
        'Only one of policy_scope or scope_rego can be provided'
      )
      expect(organization_policies).to be_empty
    end
  end

  context 'when the user is an organization member without the owner role' do
    let(:current_user) { organization_member }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the user does not belong to the organization' do
    let(:current_user) { create(:user) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the experiment is disabled for the instance' do
    before do
      stub_application_setting(policy_store_experiment_enabled: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the license does not include security orchestration policies' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:create_govern_policy, :read_govern_policy] do
    let(:user) { organization_owner }
    let(:boundary_object) { :instance }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
