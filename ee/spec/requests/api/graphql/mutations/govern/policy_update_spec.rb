# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Updating a policy in the policy store', :policy_store, feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let(:current_user) { organization_owner }

  let(:policy) do
    create_policy(
      organization_id: organization.id,
      name: 'Block production deployments',
      description: 'Blocks deployments to production during the freeze window',
      trigger_type: 'deployment_requested',
      rules: [{ type: 'environment', value: { names: %w[production] } }],
      actions: [{ type: 'block' }],
      mode: 'enforce'
    )
  end

  let(:params) do
    {
      organization_id: organization.to_global_id.to_s,
      policy_id: policy.id,
      name: 'Warn on production deployments',
      mode: 'warn'
    }
  end

  let(:mutation) { graphql_mutation(:govern_policy_update, params) }

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:govern_policy_update)
  end

  def stored_policy
    ::Gitlab::PolicyStore.find(policy.id)
  end

  it 'updates the policy and returns it', :aggregate_failures do
    request

    expect_graphql_errors_to_be_empty
    expect(mutation_response['errors']).to eq([])
    expect(mutation_response['policy']).to match(a_hash_including(
      'id' => policy.id,
      'organizationId' => organization.id,
      'name' => 'Warn on production deployments',
      'mode' => 'warn'
    ))

    expect(stored_policy.name).to eq('Warn on production deployments')
    expect(stored_policy.mode).to eq('warn')
  end

  context 'when all mutable fields are supplied' do
    let(:params) do
      {
        organization_id: organization.to_global_id.to_s,
        policy_id: policy.id,
        name: 'Audit staging deployments',
        description: 'Audits deployments to staging environments',
        trigger_type: 'environment_advanced',
        rules: [{ type: 'environment', value: { names: %w[staging] } }],
        actions: [{ type: 'require_approval' }],
        mode: 'audit',
        lifecycle_state: 'disabled',
        policy_scope: { projects: { including: [1] } }
      }
    end

    it 'updates every field', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to eq([])

      expect(stored_policy.name).to eq('Audit staging deployments')
      expect(stored_policy.description).to eq('Audits deployments to staging environments')
      expect(stored_policy.trigger_type).to eq('environment_advanced')
      expect(stored_policy.mode).to eq('audit')
      expect(stored_policy.lifecycle_state).to eq('disabled')
      # The store enriches each rule with its compiled `rego` program and compiles
      # the authored scope into `scope_rego`.
      expect(stored_policy.rules).to contain_exactly(
        a_hash_including('type' => 'environment', 'value' => { 'names' => %w[staging] },
          'rego' => an_instance_of(String))
      )
      expect(stored_policy.actions).to eq([{ 'type' => 'require_approval' }])
      expect(stored_policy.policy_scope).to eq('projects' => { 'including' => [1] })
      expect(stored_policy.scope_rego).to be_present
    end
  end

  it 'leaves omitted fields unchanged', :aggregate_failures do
    request

    expect_graphql_errors_to_be_empty
    expect(stored_policy.description).to eq('Blocks deployments to production during the freeze window')
    expect(stored_policy.trigger_type).to eq('deployment_requested')
    expect(stored_policy.rules.map { |rule| rule['type'] }).to eq(%w[environment])
    expect(stored_policy.actions).to eq([{ 'type' => 'block' }])
  end

  # The repository returns the stored policy untouched when the request carries no
  # change, so a client sending only the identifiers must not bump the version.
  context 'when no updatable field is supplied' do
    let(:params) { { organization_id: organization.to_global_id.to_s, policy_id: policy.id } }

    it 'returns the policy unchanged', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to eq([])
      expect(mutation_response['policy']).to match(a_hash_including('id' => policy.id, 'version' => 1))
      expect(stored_policy.version).to eq(1)
      expect(stored_policy.name).to eq('Block production deployments')
    end
  end

  context 'when the policy does not exist' do
    let(:params) { super().merge(policy_id: non_existing_record_id) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the policy belongs to another organization' do
    let_it_be(:other_organization) { create(:organization) }

    let(:policy) do
      create_policy(
        organization_id: other_organization.id,
        name: 'Foreign policy',
        trigger_type: 'deployment_requested'
      )
    end

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not change the policy' do
      request

      expect(stored_policy.name).to eq('Foreign policy')
    end
  end

  context 'when the rules are supplied but empty' do
    let(:params) { super().merge(rules: []) }

    # An updated policy still needs at least one rule. The store itself permits empty
    # rules, so the argument validation is the only layer enforcing this for GraphQL writes.
    it 'rejects the argument without updating the policy', :aggregate_failures do
      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => a_string_including('rules')))
      expect(stored_policy.name).to eq('Block production deployments')
    end
  end

  context 'when the actions exceed the maximum array size' do
    let(:params) do
      super().merge(actions: Array.new(::Types::BaseArgument::MAX_ARRAY_SIZE + 1) { { type: 'block' } })
    end

    it 'rejects the argument without updating the policy', :aggregate_failures do
      request

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => a_string_including('actions')))
      expect(stored_policy.name).to eq('Block production deployments')
    end
  end

  context 'when the policy is invalid for the store' do
    let(:params) { super().merge(name: '') }

    it 'returns the validation message without updating the policy', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['policy']).to be_nil
      expect(mutation_response['errors']).to contain_exactly(a_string_including('name'))
      expect(stored_policy.name).to eq('Block production deployments')
    end
  end

  context 'when both policy_scope and scope_rego are provided' do
    let(:params) do
      super().merge(
        policy_scope: { projects: { including: [1] } },
        scope_rego: 'package policy'
      )
    end

    it 'returns the conflicting scope message without updating the policy', :aggregate_failures do
      request

      expect(mutation_response['policy']).to be_nil
      expect(mutation_response['errors']).to contain_exactly(
        'Only one of policy_scope or scope_rego can be provided'
      )
      expect(stored_policy.name).to eq('Block production deployments')
    end
  end

  # The conflict check above only looks at one request. Authoring a structured scope
  # over a policy that stored hand-written Rego has to recompile scope_rego, otherwise
  # the policy keeps enforcing the stale program while the API reports the new scope.
  context 'when a structured scope replaces hand-authored scope rego' do
    let(:policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Block production deployments',
        trigger_type: 'deployment_requested',
        scope_rego: "package gitlab.scope\n\n# hand-authored-sentinel\napplies := true\n"
      )
    end

    let(:params) do
      {
        organization_id: organization.to_global_id.to_s,
        policy_id: policy.id,
        policy_scope: { projects: { including: [1] } }
      }
    end

    it 'recompiles the scope rego from the new scope', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(stored_policy.policy_scope).to eq('projects' => { 'including' => [1] })
      expect(stored_policy.scope_rego).to include('input.project.id in {1}')
      expect(stored_policy.scope_rego).not_to include('hand-authored-sentinel')
    end
  end

  context 'when a nullable field is explicitly null' do
    let(:params) { super().except(:name, :mode).merge(description: nil) }

    it 'clears the field', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to eq([])
      expect(stored_policy.description).to be_nil
    end
  end

  context 'when a non-nullable field is explicitly null' do
    let(:params) { super().merge(mode: nil) }

    it 'returns the validation message without updating the policy', :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['policy']).to be_nil
      expect(mutation_response['errors']).to contain_exactly(a_string_including('mode'))
      expect(stored_policy.mode).to eq('enforce')
    end
  end

  context 'when the service fails for an unmapped reason' do
    before do
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::UpdateService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'store internals', reason: :unavailable)
        )
      end
    end

    it 'tracks the reason and surfaces a generic error', :aggregate_failures do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(Mutations::Govern::PolicyUpdate::UnmappedReasonError),
        service_message: 'store internals'
      )

      request

      expect(graphql_errors).to contain_exactly(
        a_hash_including('message' => Mutations::Govern::PolicyUpdate::UNMAPPED_REASON_MESSAGE)
      )
    end
  end

  context 'when the service reports an engine fault' do
    before do
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::UpdateService) do |service|
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

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:update_govern_policy, :read_govern_policy] do
    let(:user) { organization_owner }
    let(:boundary_object) { :instance }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
