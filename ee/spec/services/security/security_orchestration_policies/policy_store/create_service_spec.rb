# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::PolicyStore::CreateService, :policy_store,
  feature_category: :security_policy_management do
  include_context 'with policy store service authorization'
  include_context 'with the policy store experiment active'

  let(:params) do
    {
      name: 'My approval policy',
      trigger_type: 'deployment_requested',
      rules: [{ 'type' => 'custom', 'value' => 'package governance' }],
      actions: [{ 'type' => 'require_approval' }],
      mode: 'audit'
    }
  end

  subject(:service) { described_class.new(container: container, current_user: current_user, params: params) }

  describe '#initialize' do
    it 'requires params, which the base class defaults' do
      expect { described_class.new(container: container, current_user: current_user) }
        .to raise_error(ArgumentError, /missing keyword: :params/)
    end
  end

  describe '#execute' do
    it 'returns the created policy as a store value object', :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policy]).to be_a(Gitlab::PolicyStore::Policy)
      expect(result.payload[:policy]).to have_attributes(
        organization_id: organization.id,
        namespace_id: nil,
        name: 'My approval policy',
        trigger_type: 'deployment_requested',
        actions: [{ 'type' => 'require_approval' }],
        mode: 'audit'
      )
    end

    it 'stores each rule with the rego the store compiled for it' do
      result = service.execute

      expect(result.payload[:policy].rules).to eq(
        [{ 'type' => 'custom', 'value' => 'package governance', 'rego' => 'package governance' }]
      )
    end

    it 'adds the policy to the store' do
      expect { service.execute }
        .to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }.by(1)
    end

    context 'with a rule the store cannot compile' do
      let(:params) do
        { name: 'Uncompilable', trigger_type: 'deployment_requested',
          rules: [{ 'type' => 'invalid_type' }] }
      end

      it 'returns an invalid error naming the rule', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to include('rule 0: unsupported rule type')
      end

      it 'does not add a policy to the store' do
        expect { service.execute }
          .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }
      end
    end

    context 'when the engine fails while validating' do
      let(:params) do
        { name: 'Engine fault', trigger_type: 'deployment_requested',
          rules: [{ 'type' => 'environment', 'value' => { 'tiers' => ['production'] } }] }
      end

      before do
        allow(Gitlab::PolicyStore).to receive(:create)
          .and_raise(Gitlab::PolicyStore::EngineError, 'rules[0] could not be validated')
      end

      it 'returns an engine error and tracks it, rather than calling the policy invalid', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(Gitlab::PolicyStore::EngineError), organization_id: organization.id)

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:engine_error)
        expect(result.message).to eq('rules[0] could not be validated')
      end
    end

    context 'with only the required attributes' do
      let(:params) { { name: 'Minimal policy', trigger_type: 'deployment_requested' } }

      it 'leaves the store to apply the default values' do
        result = service.execute

        expect(result.payload[:policy]).to have_attributes(
          version: 1,
          rules: [],
          actions: [],
          mode: 'warn',
          lifecycle_state: 'active'
        )
      end
    end

    context 'with a policy scope' do
      let(:params) do
        { name: 'Framework 5 only', trigger_type: 'deployment_requested',
          policy_scope: { compliance_frameworks: [{ id: 5 }] } }
      end

      it 'compiles scope_rego from the policy scope' do
        result = service.execute

        expect(result.payload[:policy].scope_rego).to include('package gitlab.scope')
      end
    end

    context 'with Rego authored directly' do
      let(:params) do
        { name: 'Hand-written scope', trigger_type: 'deployment_requested',
          scope_rego: "package gitlab.scope\n\napplies := true\n" }
      end

      it 'keeps the authored Rego and stores no structured scope' do
        result = service.execute

        expect(result.payload[:policy]).to have_attributes(
          scope_rego: "package gitlab.scope\n\napplies := true\n",
          policy_scope: nil
        )
      end
    end

    context 'with both a policy scope and Rego' do
      let(:params) do
        { name: 'Two scopes', trigger_type: 'deployment_requested',
          policy_scope: { compliance_frameworks: [{ id: 5 }] },
          scope_rego: "package gitlab.scope\n\napplies := true\n" }
      end

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('Only one of policy_scope or scope_rego can be provided')
      end

      it 'does not add a policy to the store' do
        expect { service.execute }
          .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }
      end

      # The store accepts either key form, so a string-keyed conflict has to be caught
      # here too. Left uncaught it reads as an absent policy_scope, and the store then
      # discards it in favour of the Rego instead of reporting the conflict.
      context 'when the keys arrive as strings' do
        let(:params) do
          { 'name' => 'Two scopes', 'trigger_type' => 'deployment_requested',
            'policy_scope' => { 'compliance_frameworks' => [{ 'id' => 5 }] },
            'scope_rego' => "package gitlab.scope\n\napplies := true\n" }
        end

        it 'returns the same invalid error', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:invalid)
          expect(result.message).to eq('Only one of policy_scope or scope_rego can be provided')
        end
      end
    end

    context 'when the keys arrive as strings' do
      let(:params) { { 'name' => 'String keyed policy', 'trigger_type' => 'deployment_requested' } }

      it 'reads them as attributes rather than as missing ones', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].name).to eq('String keyed policy')
      end
    end

    context 'when a required attribute is missing' do
      let(:params) { { trigger_type: 'deployment_requested' } }

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to include('name')
      end

      it 'does not add a policy to the store' do
        expect { service.execute }
          .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }
      end
    end

    context 'with an invalid mode' do
      let(:params) { { name: 'Invalid mode policy', trigger_type: 'deployment_requested', mode: 'block' } }

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('mode must be one of: audit, warn, enforce (got "block")')
      end

      it 'does not add a policy to the store' do
        expect { service.execute }
          .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }
      end
    end

    it_behaves_like 'a service that requires policy authorization', :create_govern_policy

    context 'with the persistent repository' do
      include_context 'with a persistent policy store'

      it 'returns a value object that matches the row it wrote', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy]).to eq(Gitlab::PolicyStore.find(result.payload[:policy].id))
        expect(Govern::Policy.find(result.payload[:policy].id).name).to eq('My approval policy')
      end

      context 'with only required attributes' do
        let(:params) { { name: 'Minimal policy', trigger_type: 'deployment_requested' } }

        it 'defaults mode to warn from the database', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].mode).to eq('warn')
          expect(Govern::Policy.find(result.payload[:policy].id).mode).to eq('warn')
        end
      end

      context 'when the name exceeds the limit' do
        let(:params) { super().merge(name: 'a' * 256) }

        it 'surfaces the port message rather than the model phrasing', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('name exceeds maximum length of 255 characters')
        end
      end
    end

    it_behaves_like 'a service gated by the policy store experiment', :create
  end

  context 'with a group container' do
    include_context 'with policy store group containers'

    let(:container) { group }
    let(:current_user) { group_owner }

    it "stamps the policy with the group's namespace", :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policy]).to have_attributes(
        organization_id: organization.id,
        namespace_id: group.id
      )
    end

    it 'is forbidden for an organization member who holds no group ability' do
      result = described_class.new(container: group, current_user: non_owner, params: params).execute

      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
    end

    it 'is allowed for the organization owner, who supervises every group of the organization' do
      result = described_class.new(container: group, current_user: owner, params: params).execute

      expect(result).to be_success
    end
  end
end
