# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::PolicyStore::UpdateService, :policy_store,
  feature_category: :security_policy_management do
  using RSpec::Parameterized::TableSyntax

  include_context 'with policy store service authorization'
  include_context 'with the policy store experiment active'

  let(:policy) do
    create_policy(
      organization_id: organization.id,
      name: 'Test policy',
      trigger_type: 'deployment_requested'
    )
  end

  let(:params) { { name: 'Renamed policy' } }

  subject(:service) do
    described_class.new(container: container, current_user: current_user, policy_id: policy.id, params: params)
  end

  describe '#execute' do
    it 'returns the updated policy as a store value object', :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policy]).to be_a(Gitlab::PolicyStore::Policy)
      expect(result.payload[:policy].name).to eq('Renamed policy')
    end

    it 'persists the change' do
      service.execute

      expect(Gitlab::PolicyStore.find(policy.id).name).to eq('Renamed policy')
    end

    it 'bumps the version' do
      expect { service.execute }
        .to change { Gitlab::PolicyStore.find(policy.id).version }.from(1).to(2)
    end

    context 'when the policy does not exist' do
      subject(:service) do
        described_class.new(container: container, current_user: current_user,
          policy_id: non_existing_record_id, params: params)
      end

      it 'returns a not found error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
        expect(result.message).to eq('Policy was not found')
      end
    end

    context 'when the policy belongs to another organization' do
      let(:policy) do
        create_policy(
          organization_id: create(:organization).id,
          name: 'Other organization policy',
          trigger_type: 'deployment_requested'
        )
      end

      it 'returns the same not found error as a missing policy', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
        expect(result.message).to eq('Policy was not found')
      end

      it 'leaves the policy unchanged' do
        expect { service.execute }.not_to change { Gitlab::PolicyStore.find(policy.id).name }
      end
    end

    context 'when the policy is deleted between the lookup and the update' do
      before do
        allow(Gitlab::PolicyStore).to receive(:update).and_raise(Gitlab::PolicyStore::NotFound)
      end

      it 'returns the same not found error as a missing policy', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
        expect(result.message).to eq('Policy was not found')
      end
    end

    context 'when the engine fails while validating' do
      before do
        allow(Gitlab::PolicyStore).to receive(:update)
          .and_raise(Gitlab::PolicyStore::EngineError, 'rules[0] could not be validated')
      end

      it 'returns an engine error and tracks it, rather than calling the policy invalid', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(Gitlab::PolicyStore::EngineError), organization_id: organization.id, policy_id: policy.id
        )

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:engine_error)
        expect(result.message).to eq('rules[0] could not be validated')
      end
    end

    context 'with both a policy scope and Rego' do
      let(:params) do
        { policy_scope: { compliance_frameworks: [{ id: 5 }] }, scope_rego: "package gitlab.scope\n" }
      end

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('Only one of policy_scope or scope_rego can be provided')
      end

      it 'does not touch the store' do
        expect(Gitlab::PolicyStore).not_to receive(:update)

        service.execute
      end

      # The store accepts either key form, so a string-keyed conflict has to be caught
      # here too. Left uncaught it reads as an absent policy_scope, and the store then
      # discards it in favour of the Rego instead of reporting the conflict.
      context 'when the keys arrive as strings' do
        let(:params) do
          { 'policy_scope' => { 'compliance_frameworks' => [{ 'id' => 5 }] },
            'scope_rego' => "package gitlab.scope\n" }
        end

        it 'returns the same invalid error', :aggregate_failures do
          expect(Gitlab::PolicyStore).not_to receive(:update)

          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:invalid)
          expect(result.message).to eq('Only one of policy_scope or scope_rego can be provided')
        end
      end
    end

    context 'when the change set is empty' do
      let(:params) { {} }

      it 'succeeds without bumping the version, since nothing changed', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].version).to eq(1)
      end
    end

    context 'with an authored scope_rego to retire' do
      let(:authored_rego) { "package gitlab.scope\n\n# hand written" }

      let(:policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Test policy',
          trigger_type: 'deployment_requested',
          scope_rego: authored_rego
        )
      end

      where(:blank_scope_rego) { ['', nil] }

      with_them do
        context 'when the blank scope_rego arrives on its own' do
          let(:params) { { scope_rego: blank_scope_rego } }

          it 'retires the authored program instead of leaving it in place' do
            result = service.execute

            expect(result).to be_success
            expect(result.payload[:policy].scope_rego).not_to eq(authored_rego)
            expect(result.payload[:policy].scope_rego).to include('applies to all projects')
          end
        end

        context 'when a policy scope replaces it' do
          let(:params) do
            { scope_rego: blank_scope_rego, policy_scope: { 'compliance_frameworks' => [{ 'id' => 7 }] } }
          end

          it 'recompiles from the policy scope rather than reporting a conflict' do
            result = service.execute

            expect(result).to be_success
            expect(result.payload[:policy].scope_rego).to include('framework_id in {7}')
          end
        end
      end
    end

    context 'when a rename reaches a policy with an authored scope_rego' do
      let(:authored_rego) { "package gitlab.scope\n\n# hand written" }

      let(:policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Test policy',
          trigger_type: 'deployment_requested',
          scope_rego: authored_rego
        )
      end

      it 'keeps the authored program, since only a generated one tracks the name' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].scope_rego).to eq(authored_rego)
      end
    end

    context 'when a rename reaches a policy with a generated scope_rego' do
      let(:policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Test policy',
          trigger_type: 'deployment_requested',
          policy_scope: { 'compliance_frameworks' => [{ 'id' => 7 }] }
        )
      end

      it 'recompiles so the program carries the new name', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].scope_rego).to include('# policy "Renamed policy"')
        expect(result.payload[:policy].scope_rego).to include('framework_id in {7}')
      end
    end

    context 'when a policy scope arrives without a scope_rego key' do
      let(:params) { { policy_scope: { 'compliance_frameworks' => [{ 'id' => 7 }] } } }

      it 'recompiles from it', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].policy_scope).to eq('compliance_frameworks' => [{ 'id' => 7 }])
        expect(result.payload[:policy].scope_rego).to include('framework_id in {7}')
      end
    end

    context 'with a structured scope to clear' do
      let(:policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Test policy',
          trigger_type: 'deployment_requested',
          policy_scope: { 'compliance_frameworks' => [{ 'id' => 5 }] }
        )
      end

      context 'when an empty policy scope arrives' do
        let(:params) { { policy_scope: {} } }

        it 'un-scopes the policy', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].scope_rego).to include('applies to all projects')
          expect(result.payload[:policy].scope_rego).not_to include('framework_id')
        end
      end

      context 'when a blank scope_rego arrives instead' do
        let(:params) { { scope_rego: '' } }

        it 'keeps the scope and recompiles from it', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].policy_scope).to eq('compliance_frameworks' => [{ 'id' => 5 }])
          expect(result.payload[:policy].scope_rego).to include('framework_id in {5}')
        end
      end
    end

    context 'when every supplied value already matches the stored policy' do
      let(:params) { { name: 'Test policy', trigger_type: 'deployment_requested' } }

      it 'succeeds without bumping the version, as with an empty change set', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].version).to eq(1)
      end
    end

    context 'when the new name is taken by another policy in the organization' do
      before do
        create_policy(
          organization_id: organization.id,
          name: 'Renamed policy',
          trigger_type: 'deployment_requested'
        )
      end

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('Name has already been taken')
      end

      context 'when the taken name is the policy\'s own' do
        let(:params) { { name: 'Test policy', description: 'Restated its own name' } }

        it 'succeeds, since the policy does not conflict with itself' do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].description).to eq('Restated its own name')
        end
      end
    end

    context 'when the change is invalid' do
      let(:params) { { name: 'a' * 256 } }

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to include('name exceeds maximum length of 255')
      end

      it 'leaves the policy unchanged' do
        expect { service.execute }.not_to change { Gitlab::PolicyStore.find(policy.id).name }
      end
    end

    # Params are forwarded whole rather than sliced to a permitted list, so these pin the
    # store's own guards reaching the caller as :invalid. Slicing here would answer a typo
    # or a re-home attempt with a silent success instead.
    context 'with an attribute the store refuses to change' do
      let(:params) { { organization_id: non_existing_record_id, name: 'Moved' } }

      it 'returns an invalid error rather than re-homing the policy', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('Attributes cannot be changed: organization_id')
        expect(Gitlab::PolicyStore.find(policy.id).organization_id).to eq(organization.id)
      end
    end

    context 'with an attribute the store does not recognise' do
      let(:params) { { nmae: 'Misspelled' } }

      it 'returns an invalid error naming it', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('Unknown attributes: nmae')
      end
    end

    describe 'mode transitions' do
      using RSpec::Parameterized::TableSyntax

      let(:policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Test policy',
          trigger_type: 'deployment_requested',
          mode: initial_mode
        )
      end

      where(:initial_mode, :target_mode) do
        'warn'    | 'enforce'
        'enforce' | 'warn'
        'warn'    | 'audit'
        'audit'   | 'warn'
        'enforce' | 'audit'
        'audit'   | 'enforce'
      end

      with_them do
        let(:params) { { mode: target_mode } }

        it 'transitions mode and bumps version', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].mode).to eq(target_mode)
          expect(result.payload[:policy].version).to eq(2)
        end
      end
    end

    context 'with an invalid mode' do
      let(:params) { { mode: 'block' } }

      it 'returns an invalid error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:invalid)
        expect(result.message).to eq('mode must be one of: audit, warn, enforce (got "block")')
      end

      it 'leaves the policy unchanged' do
        expect { service.execute }.not_to change { Gitlab::PolicyStore.find(policy.id).mode }
      end
    end

    it_behaves_like 'a service that requires policy authorization', :update_govern_policy

    context 'with the persistent repository' do
      include_context 'with a persistent policy store'

      it 'writes the change to the row and bumps its version' do
        service.execute

        expect(Govern::Policy.find(policy.id)).to have_attributes(name: 'Renamed policy', version: 2)
      end

      context 'when the policy belongs to another organization' do
        let(:policy) do
          create_policy(organization_id: create(:organization).id, name: 'Foreign policy',
            trigger_type: 'deployment_requested')
        end

        it 'reports not found and leaves the row alone', :aggregate_failures do
          expect(service.execute).to be_error
          expect(Govern::Policy.find(policy.id).name).to eq('Foreign policy')
        end
      end

      context 'when the policy belongs to a group within the organization' do
        include_context 'with policy store group containers'

        let(:policy) do
          create_policy(
            organization_id: organization.id,
            namespace_id: group.id,
            name: 'Group policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'updates the policy (organization owner supervises every group)' do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policy].name).to eq('Renamed policy')
        end
      end
    end

    it_behaves_like 'a service gated by the policy store experiment', :update
  end

  context 'with a group container' do
    include_context 'with policy store group containers'

    let(:container) { group }
    let(:current_user) { group_owner }

    it 'refuses to update an organization-wide policy, leaving it unchanged', :aggregate_failures do
      result = service.execute

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
      expect(Gitlab::PolicyStore.find(policy.id).name).to eq('Test policy')
    end

    it 'refuses a differing namespace_id as an attempt to re-home the policy', :aggregate_failures do
      group_policy = create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group policy',
        trigger_type: 'deployment_requested'
      )

      result = described_class.new(
        container: group, current_user: group_owner, policy_id: group_policy.id,
        params: { name: 'Renamed policy', namespace_id: other_group.id }
      ).execute

      expect(result).to be_error
      expect(result.reason).to eq(:invalid)
      expect(Gitlab::PolicyStore.find(group_policy.id).namespace_id).to eq(group.id)
    end

    it "updates the group's own policy" do
      group_policy = create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group policy',
        trigger_type: 'deployment_requested'
      )

      result = described_class.new(
        container: group, current_user: group_owner, policy_id: group_policy.id, params: params
      ).execute

      expect(result).to be_success
      expect(result.payload[:policy].name).to eq('Renamed policy')
    end
  end
end
