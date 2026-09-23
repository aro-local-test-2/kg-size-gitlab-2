# frozen_string_literal: true

require 'spec_helper'
require Rails.root.join('gems/gitlab-policy-store/spec/support/shared_examples/evaluation_recorder_shared_examples')

RSpec.describe Govern::PolicyStore::ActiveRecordEvaluationRecorder, feature_category: :security_policy_management do
  subject(:recorder) { described_class.new }

  let_it_be(:policy) { create(:govern_policy) }

  let(:organization_id) { policy.organization_id }
  let(:policy_id) { policy.id }

  let(:valid_attributes) do
    {
      organization_id: organization_id,
      policy_id: policy_id,
      policy_version: 1,
      trigger_type: 'deployment_requested',
      mode: 'audit',
      verdict: 'deny',
      evaluated_at: Time.current,
      violations: [{ details: { 'rule_index' => 0 } }]
    }
  end

  it_behaves_like 'an evaluation recorder'

  describe '#record' do
    it 'persists the evaluation and violation rows' do
      expect { recorder.record(valid_attributes) }
        .to change { Govern::PolicyEvaluation.count }.by(1)
        .and change { Govern::PolicyViolation.count }.by(1)
    end

    it 'persists no rows when a violation is rejected', :aggregate_failures do
      oversized = valid_attributes.merge(violations: [{ details: { 'reason' => 'a' * 65.kilobytes } }])

      expect { recorder.record(oversized) }
        .to raise_error(::Gitlab::PolicyStore::ValidationError, /too large/)

      expect(Govern::PolicyEvaluation.count).to eq(0)
      expect(Govern::PolicyViolation.count).to eq(0)
    end

    it 'rejects a policy that does not exist' do
      expect { recorder.record(valid_attributes.merge(policy_id: non_existing_record_id)) }
        .to raise_error(::Gitlab::PolicyStore::ValidationError, /Policy must exist/)
    end

    it 'rejects an organization that does not match the policy' do
      other_organization = create(:organization)

      expect { recorder.record(valid_attributes.merge(organization_id: other_organization.id)) }
        .to raise_error(::Gitlab::PolicyStore::ValidationError, /must match the policy's organization/)
    end
  end
end
