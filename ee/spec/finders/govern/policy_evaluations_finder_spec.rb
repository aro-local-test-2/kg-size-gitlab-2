# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEvaluationsFinder, feature_category: :security_policy_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:policy) { create(:govern_policy, :without_namespace, organization: organization) }
  let_it_be(:other_policy) { create(:govern_policy, :without_namespace, organization: organization) }

  let_it_be(:audit_allow_evaluation) do
    create(:govern_policy_evaluation, policy: policy, mode: :audit, verdict: :allow, evaluated_at: 3.days.ago)
  end

  let_it_be(:enforce_deny_evaluation) do
    create(:govern_policy_evaluation, policy: other_policy, mode: :enforce, verdict: :deny, evaluated_at: 1.day.ago)
  end

  let_it_be(:other_organization_evaluation) { create(:govern_policy_evaluation) }

  let(:params) { {} }

  subject(:evaluations) { described_class.new(organization: organization, params: params).execute }

  it 'returns the evaluations of the organization, newest first' do
    expect(evaluations).to eq([enforce_deny_evaluation, audit_allow_evaluation])
  end

  context 'with a policy_id filter' do
    let(:params) { { policy_id: policy.id } }

    it 'returns only the evaluations of the policy' do
      expect(evaluations).to contain_exactly(audit_allow_evaluation)
    end
  end

  context 'with a mode filter' do
    let(:params) { { mode: 'enforce' } }

    it 'returns only the evaluations that ran in the mode' do
      expect(evaluations).to contain_exactly(enforce_deny_evaluation)
    end
  end

  context 'with a verdict filter' do
    let(:params) { { verdict: 'allow' } }

    it 'returns only the evaluations that produced the verdict' do
      expect(evaluations).to contain_exactly(audit_allow_evaluation)
    end
  end

  context 'with an evaluated_after filter' do
    let(:params) { { evaluated_after: 2.days.ago } }

    it 'returns only the evaluations at or after the time' do
      expect(evaluations).to contain_exactly(enforce_deny_evaluation)
    end
  end

  context 'with an evaluated_before filter' do
    let(:params) { { evaluated_before: 2.days.ago } }

    it 'returns only the evaluations at or before the time' do
      expect(evaluations).to contain_exactly(audit_allow_evaluation)
    end
  end

  context 'with combined filters' do
    let(:params) { { policy_id: other_policy.id, mode: 'enforce', verdict: 'deny', evaluated_after: 2.days.ago } }

    it 'applies all of them' do
      expect(evaluations).to contain_exactly(enforce_deny_evaluation)
    end
  end
end
