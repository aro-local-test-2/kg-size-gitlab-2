# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::AiSuggestedReviewer, feature_category: :code_review_workflow do
  describe 'associations' do
    it { is_expected.to belong_to(:merge_request) }
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:approval_merge_request_rule).optional }
    it { is_expected.to belong_to(:approval_project_rule).optional }

    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:ai_suggested_reviewer) }

    it { is_expected.to validate_length_of(:reason).is_at_most(2048).allow_nil }

    context 'when both approval rule associations are set' do
      subject(:suggested_reviewer) do
        build(:ai_suggested_reviewer,
          approval_merge_request_rule: build_stubbed(:approval_merge_request_rule),
          approval_project_rule: build_stubbed(:approval_project_rule))
      end

      it 'is invalid' do
        expect(suggested_reviewer).to be_invalid
        expect(suggested_reviewer.errors[:base])
          .to include('Cannot be associated with both an approval merge request rule and an approval project rule')
      end
    end

    context 'when only one approval rule association is set' do
      subject(:suggested_reviewer) do
        build(:ai_suggested_reviewer, approval_merge_request_rule: build_stubbed(:approval_merge_request_rule))
      end

      it 'is valid' do
        expect(suggested_reviewer).to be_valid
      end
    end
  end

  describe 'project derivation' do
    it 'derives project_id from the merge request' do
      merge_request = build_stubbed(:merge_request)
      suggested_reviewer = build(:ai_suggested_reviewer, merge_request: merge_request, project: nil)

      suggested_reviewer.validate

      expect(suggested_reviewer.project_id).to eq(merge_request.target_project_id)
    end
  end

  describe '#approval_rule' do
    it 'returns the approval merge request rule when set' do
      rule = build_stubbed(:approval_merge_request_rule)
      suggested_reviewer = build(:ai_suggested_reviewer, approval_merge_request_rule: rule)

      expect(suggested_reviewer.approval_rule).to eq(rule)
    end

    it 'returns the approval project rule when set' do
      rule = build_stubbed(:approval_project_rule)
      suggested_reviewer = build(:ai_suggested_reviewer, approval_project_rule: rule)

      expect(suggested_reviewer.approval_rule).to eq(rule)
    end

    it 'returns nil when neither is set' do
      suggested_reviewer = build(:ai_suggested_reviewer)

      expect(suggested_reviewer.approval_rule).to be_nil
    end
  end

  it 'includes BulkInsertSafe' do
    expect(described_class.ancestors).to include(BulkInsertSafe)
  end

  describe 'factory' do
    it 'builds a valid record' do
      expect(build(:ai_suggested_reviewer)).to be_valid
    end
  end
end
