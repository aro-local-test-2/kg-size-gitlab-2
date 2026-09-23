# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEvaluation, feature_category: :security_policy_management do
  subject(:evaluation) { build(:govern_policy_evaluation) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:policy).required.inverse_of(:evaluations) }
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:environment).optional }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:violations).inverse_of(:evaluation) }
  end

  describe 'enums' do
    it 'snapshots the policy trigger types' do
      is_expected.to define_enum_for(:trigger_type)
        .with_values(deployment_requested: 0, environment_advanced: 1, deployment_promoted: 2).with_prefix
    end

    it { is_expected.to define_enum_for(:mode).with_values(audit: 0, warn: 1, enforce: 2).with_prefix }

    it 'defines the verdicts' do
      is_expected.to define_enum_for(:verdict)
        .with_values(allow: 0, deny: 1, require_approval: 2).with_prefix
    end
  end

  describe 'scopes' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:policy) { create(:govern_policy, :without_namespace, organization: organization) }
    let_it_be(:other_policy) { create(:govern_policy, :without_namespace, organization: organization) }

    let_it_be(:earlier_evaluation) do
      create(:govern_policy_evaluation, policy: policy, evaluated_at: 2.days.ago)
    end

    let_it_be(:later_evaluation) do
      create(:govern_policy_evaluation, policy: other_policy, evaluated_at: 1.day.ago)
    end

    let_it_be(:other_organization_evaluation) { create(:govern_policy_evaluation) }

    describe '.for_organization' do
      it 'returns only the evaluations of the organization' do
        expect(described_class.for_organization(organization))
          .to contain_exactly(earlier_evaluation, later_evaluation)
      end
    end

    describe '.for_policy' do
      it 'returns only the evaluations of the policy' do
        expect(described_class.for_policy(policy.id)).to contain_exactly(earlier_evaluation)
      end
    end

    describe '.evaluated_after' do
      it 'returns the evaluations at or after the time' do
        expect(described_class.for_organization(organization).evaluated_after(36.hours.ago))
          .to contain_exactly(later_evaluation)
      end
    end

    describe '.evaluated_before' do
      it 'returns the evaluations at or before the time' do
        expect(described_class.for_organization(organization).evaluated_before(36.hours.ago))
          .to contain_exactly(earlier_evaluation)
      end
    end

    describe '.order_by_evaluated_at_desc' do
      it 'orders newest first' do
        expect(described_class.for_organization(organization).order_by_evaluated_at_desc)
          .to eq([later_evaluation, earlier_evaluation])
      end
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:trigger_type) }
    it { is_expected.to validate_presence_of(:mode) }
    it { is_expected.to validate_presence_of(:verdict) }
    it { is_expected.to validate_presence_of(:evaluated_at) }
    it { is_expected.to validate_numericality_of(:policy_version).only_integer.is_greater_than(0) }

    it { is_expected.to be_valid }

    context 'when the organization does not match the policy organization' do
      subject(:evaluation) { build(:govern_policy_evaluation, organization: build(:organization)) }

      it 'is invalid' do
        expect(evaluation).not_to be_valid
        expect(evaluation.errors[:organization_id]).to include("must match the policy's organization")
      end
    end
  end
end
