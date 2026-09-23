# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanExecutionPoliciesFinder, feature_category: :security_policy_management do
  let!(:policy) { build(:scan_execution_policy, name: 'Run DAST in every pipeline', policy_scope: policy_scope) }
  let(:expected_extra_attrs) { { type: 'scan_execution_policy', policy_index: 0 } }
  let!(:policy_yaml) do
    build(:orchestration_policy_yaml, scan_execution_policy: [policy])
  end

  include_context 'with security policies information'

  subject(:policies) { described_class.new(actor, object, params).execute }

  context 'when actor is Clusters::Agent' do
    let_it_be(:actor) { create(:cluster_agent, project: object) }

    before do
      stub_licensed_features(security_orchestration_policies: true)
    end

    context 'when agent project has security_orchestration_policy project' do
      it 'returns policy matching the given scan type' do
        is_expected.to match_array([policy.merge(
          {
            config: policy_configuration,
            project: object,
            namespace: nil,
            inherited: false,
            csp: false,
            type: 'scan_execution_policy',
            policy_index: 0
          })])
      end
    end

    context 'when the security policy project is linked to the group' do
      let!(:policy_configuration) do
        create(
          :security_orchestration_policy_configuration,
          :namespace,
          security_policy_management_project: policy_management_project,
          namespace: group
        )
      end

      let(:relationship) { :inherited }

      it 'returns policy matching the given scan type' do
        is_expected.to match_array([policy.merge(
          {
            config: policy_configuration,
            project: nil,
            namespace: group,
            inherited: true,
            csp: false,
            type: 'scan_execution_policy',
            policy_index: 0
          })])
      end

      context 'and object is not a Project' do
        let(:object) { group }

        it 'returns empty response' do
          is_expected.to be_empty
        end
      end
    end
  end

  context 'when action_scan_types is given' do
    before do
      stub_licensed_features(security_orchestration_policies: true)
      object.add_developer(actor)
    end

    context 'when there are multiple policies' do
      let(:secret_detection_policy) do
        build(
          :scan_execution_policy,
          name: 'Run secret detection in every pipeline',
          description: 'Secret detection',
          actions: [{ scan: 'secret_detection' }]
        )
      end

      let(:policy_yaml) do
        build(
          :orchestration_policy_yaml,
          scan_execution_policy: [policy, secret_detection_policy]
        )
      end

      let(:action_scan_types) { [::Types::Security::ReportTypeEnum.values['DAST'].value] }

      it 'returns policy matching the given scan type' do
        is_expected.to match_array([policy.merge(
          {
            config: policy_configuration,
            project: object,
            namespace: nil,
            inherited: false,
            csp: false,
            type: 'scan_execution_policy',
            policy_index: 0
          })])
      end
    end

    context 'when there are no matching policies' do
      let(:action_scan_types) { [::Types::Security::ReportTypeEnum.values['CONTAINER_SCANNING'].value] }

      it 'returns empty response' do
        is_expected.to be_empty
      end
    end
  end

  context 'when an inherited policy is scoped by a security attribute' do
    let_it_be(:security_category) do
      create(:security_category, namespace: group, template_type: :business_impact, name: 'Business Impact')
    end

    let_it_be(:security_attribute) do
      create(:security_attribute, namespace: group, security_category: security_category, name: 'Critical')
    end

    let(:policy_scope) { { business_impact: { including: [{ id: security_attribute.id }] } } }
    let(:relationship) { :inherited }

    # The project has no configuration of its own, so the scope can only be resolved
    # against the group configuration the policy came from.
    let!(:policy_configuration) { nil }

    let!(:group_policy_configuration) do
      create(
        :security_orchestration_policy_configuration,
        :namespace,
        security_policy_management_project: policy_management_project,
        namespace: group,
        experiments: { security_attributes_policy_scope: { enabled: true } })
    end

    before do
      stub_licensed_features(security_orchestration_policies: true)

      object.add_developer(actor)
    end

    it 'excludes the policy when the project does not carry the attribute' do
      expect(policies).to be_empty
    end

    context 'when the project carries the attribute' do
      before do
        create(:project_to_security_attribute,
          project: object,
          security_attribute: security_attribute,
          traversal_ids: object.namespace.traversal_ids)
      end

      it 'includes the policy' do
        expect(policies).to contain_exactly(a_hash_including(config: group_policy_configuration))
      end
    end
  end

  it_behaves_like 'security policies finder'
end
