# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::ComplianceManagement::ComplianceFrameworkPolicySummaryType,
  feature_category: :compliance_management do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('ComplianceFrameworkPolicySummary') }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields(%w[name type source has_active_projects])
  end

  describe '#type' do
    subject(:resolved_type) { resolve_field(:type, policy_hash) }

    context 'when the policy type is scan_result_policy (legacy name)' do
      let(:policy_hash) { { name: 'Legacy Policy', type: 'scan_result_policy' } }

      it 'normalizes to approval_policy' do
        expect(resolved_type).to eq('approval_policy')
      end
    end

    context 'when the policy type is approval_policy' do
      let(:policy_hash) { { name: 'Approval Policy', type: 'approval_policy' } }

      it 'returns approval_policy unchanged' do
        expect(resolved_type).to eq('approval_policy')
      end
    end

    context 'when the policy type is scan_execution_policy' do
      let(:policy_hash) { { name: 'SEP Policy', type: 'scan_execution_policy' } }

      it 'returns scan_execution_policy unchanged' do
        expect(resolved_type).to eq('scan_execution_policy')
      end
    end

    context 'when the policy type is nil' do
      let(:policy_hash) { { name: 'Unnamed Policy', type: nil } }

      it 'returns nil' do
        expect(resolved_type).to be_nil
      end
    end
  end

  describe '#has_active_projects' do
    subject(:resolved_field) do
      result = resolve_field(:has_active_projects, policy_hash)
      result.is_a?(GraphQL::Execution::Lazy) ? result.value : result
    end

    let(:policy) { create(:security_policy, :scan_execution_policy, linked_projects: linked_projects) }
    let(:policy_hash) do
      {
        name: policy.name,
        config: policy.security_orchestration_policy_configuration,
        type: policy.type,
        policy_index: policy.policy_index
      }
    end

    context 'when the policy has non-archived assigned projects' do
      let(:linked_projects) { [create(:project)] }

      it 'returns true' do
        expect(resolved_field).to be(true)
      end
    end

    context 'when the policy has only archived assigned projects' do
      let(:linked_projects) { [create(:project, :archived)] }

      it 'returns false' do
        expect(resolved_field).to be(false)
      end
    end

    context 'when the policy has archived and non-archived assigned projects' do
      let(:linked_projects) { [create(:project, :archived), create(:project)] }

      it 'returns true' do
        expect(resolved_field).to be(true)
      end
    end

    context 'when the policy has no assigned projects' do
      let(:linked_projects) { [] }

      it 'returns false' do
        expect(resolved_field).to be(false)
      end
    end
  end
end
