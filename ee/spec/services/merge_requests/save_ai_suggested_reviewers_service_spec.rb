# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::SaveAiSuggestedReviewersService, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:user_a) { create(:user) }
  let_it_be(:user_b) { create(:user) }

  let(:suggestions) do
    [
      { user_id: user_a.id, reason: 'Owns the changed files.' },
      { user_id: user_b.id, reason: 'Recently reviewed similar code.' }
    ]
  end

  subject(:service) do
    described_class.new(merge_request: merge_request, suggestions: suggestions)
  end

  describe '#execute' do
    it 'persists the suggestions with the merge request project' do
      response = service.execute

      expect(response).to be_success

      records = merge_request.ai_suggested_reviewers.reset
      expect(records.count).to eq(2)
      expect(records.map(&:user_id)).to match_array([user_a.id, user_b.id])
      expect(records.map(&:project_id)).to all(eq(project.id))

      persisted = records.find_by(user_id: user_a.id)
      expect(persisted.reason).to eq('Owns the changed files.')
    end

    context 'when suggestions already exist for the merge request' do
      before do
        create(:ai_suggested_reviewer, merge_request: merge_request, project: project, user: user_a)
      end

      it 'replaces the existing set (clears then inserts)' do
        expect { service.execute }.to change { merge_request.ai_suggested_reviewers.reset.pluck(:user_id) }
          .from([user_a.id]).to match_array([user_a.id, user_b.id])
      end
    end

    context 'when suggestions is empty' do
      let(:suggestions) { [] }

      before do
        create(:ai_suggested_reviewer, merge_request: merge_request, project: project, user: user_a)
      end

      it 'clears existing suggestions and inserts nothing' do
        response = service.execute

        expect(response).to be_success
        expect(merge_request.ai_suggested_reviewers.reset).to be_empty
      end
    end

    context 'when a record is invalid' do
      let(:suggestions) { [{ user_id: user_a.id, reason: 'a' * 2049 }] }

      it 'returns an error response and persists nothing' do
        response = service.execute

        expect(response).to be_error
        expect(merge_request.ai_suggested_reviewers.reset).to be_empty
      end

      context 'when suggestions already exist' do
        let_it_be(:existing) do
          create(:ai_suggested_reviewer, merge_request: merge_request, project: project, user: user_b)
        end

        it 'rolls back and preserves the existing suggestions' do
          response = service.execute

          expect(response).to be_error
          expect(merge_request.ai_suggested_reviewers.reset.pluck(:user_id)).to eq([user_b.id])
        end
      end
    end

    context 'when the payload contains a duplicate user' do
      let(:suggestions) do
        [
          { user_id: user_a.id, reason: 'First mention.' },
          { user_id: user_a.id, reason: 'Duplicate mention.' }
        ]
      end

      it 'keeps the first mention and drops the duplicate' do
        response = service.execute

        expect(response).to be_success
        expect(merge_request.ai_suggested_reviewers.reset.pluck(:reason)).to eq(['First mention.'])
      end
    end

    context 'when a suggested user does not exist' do
      let(:suggestions) { [{ user_id: non_existing_record_id }] }

      it 'returns an error response instead of raising' do
        response = service.execute

        expect(response).to be_error
        expect(merge_request.ai_suggested_reviewers.reset).to be_empty
      end
    end

    context 'when a suggestion references an approval rule' do
      let_it_be(:approval_project_rule) { create(:approval_project_rule, project: project) }
      let_it_be(:code_owner_rule) { create(:code_owner_rule, merge_request: merge_request) }

      before do
        stub_licensed_features(merge_request_approvers: true, code_owners: true)
      end

      context 'when the id resolves to an ApprovalMergeRequestRule' do
        let(:suggestions) do
          [{ user_id: user_a.id, approval_rule_id: code_owner_rule.id, approval_rule_type: 'merge_request_rule' }]
        end

        it 'sets approval_merge_request_rule_id' do
          service.execute

          record = merge_request.ai_suggested_reviewers.reset.find_by(user_id: user_a.id)
          expect(record.approval_merge_request_rule_id).to eq(code_owner_rule.id)
          expect(record.approval_project_rule_id).to be_nil
        end
      end

      context 'when the id resolves to an ApprovalProjectRule' do
        let(:suggestions) do
          [{ user_id: user_a.id, approval_rule_id: approval_project_rule.id, approval_rule_type: 'project_rule' }]
        end

        it 'sets approval_project_rule_id' do
          service.execute

          record = merge_request.ai_suggested_reviewers.reset.find_by(user_id: user_a.id)
          expect(record.approval_project_rule_id).to eq(approval_project_rule.id)
          expect(record.approval_merge_request_rule_id).to be_nil
        end
      end

      context 'when the id does not resolve to a rule the merge request currently has' do
        using RSpec::Parameterized::TableSyntax

        let_it_be(:other_project) { create(:project) }
        let_it_be(:other_merge_request) { create(:merge_request, source_project: other_project) }
        let_it_be(:other_project_rule) { create(:approval_project_rule, project: other_project) }
        let_it_be(:other_mr_rule) { create(:code_owner_rule, merge_request: other_merge_request) }

        let(:non_existing_id) { non_existing_record_id }
        let(:other_mr_rule_id) { other_mr_rule.id }
        let(:other_project_rule_id) { other_project_rule.id }

        where(:case_description, :approval_rule_id, :approval_rule_type) do
          [
            ['a non-existing id',            ref(:non_existing_id),       'merge_request_rule'],
            ["another merge request's rule", ref(:other_mr_rule_id),      'merge_request_rule'],
            ["another project's rule",       ref(:other_project_rule_id), 'project_rule']
          ]
        end

        with_them do
          let(:suggestions) do
            [{ user_id: user_a.id, approval_rule_id: approval_rule_id, approval_rule_type: approval_rule_type }]
          end

          it 'leaves both foreign keys nil' do
            service.execute

            record = merge_request.ai_suggested_reviewers.reset.find_by(user_id: user_a.id)
            expect(record.approval_merge_request_rule_id).to be_nil
            expect(record.approval_project_rule_id).to be_nil
          end
        end
      end
    end
  end
end
