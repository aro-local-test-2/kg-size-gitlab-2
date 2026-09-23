# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyViolation, feature_category: :security_policy_management do
  subject(:violation) { build(:govern_policy_violation) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:evaluation).required.inverse_of(:violations) }
    it { is_expected.to belong_to(:policy).required.inverse_of(:violations) }
  end

  describe 'validations' do
    it { is_expected.to be_valid }

    context 'when the organization does not match the evaluation organization' do
      subject(:violation) { build(:govern_policy_violation, organization: build(:organization)) }

      it 'is invalid' do
        expect(violation).not_to be_valid
        expect(violation.errors[:organization_id]).to include("must match the evaluation's organization")
      end
    end

    describe 'details' do
      it 'allows nil' do
        violation.details = nil

        expect(violation).to be_valid
      end

      it 'allows a JSON object' do
        violation.details = { 'rule_index' => 0, 'reason' => 'environment tier is production' }

        expect(violation).to be_valid
      end

      it 'rejects a non-object value' do
        violation.details = ['not an object']

        expect(violation).not_to be_valid
        expect(violation.errors[:details]).to include('must be a valid json schema')
      end

      it 'rejects a value over the size limit' do
        violation.details = { 'reason' => 'a' * 65.kilobytes }

        expect(violation).not_to be_valid
        expect(violation.errors[:details]).to include('is too large. Maximum size allowed is 64 KiB')
      end
    end

    context 'when the policy does not match the evaluation policy' do
      subject(:violation) do
        build(:govern_policy_violation, evaluation: create(:govern_policy_evaluation), policy: create(:govern_policy))
      end

      it 'is invalid' do
        expect(violation).not_to be_valid
        expect(violation.errors[:govern_policy_id]).to include("must match the evaluation's policy")
      end
    end
  end
end
