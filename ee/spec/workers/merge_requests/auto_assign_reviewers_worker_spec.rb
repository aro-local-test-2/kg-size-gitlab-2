# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::AutoAssignReviewersWorker, feature_category: :code_review_workflow do
  let_it_be_with_reload(:project) do
    create(:project).tap do |p|
      p.project_setting.update!(reviewer_assignment_strategy: 'code_owners')
    end
  end

  let_it_be(:author) { create(:user) }

  let(:merge_request) { create(:merge_request, source_project: project, author: author) }

  before_all do
    project.add_developer(author)
  end

  before do
    stub_licensed_features(merge_request_approvers: true, multiple_merge_request_reviewers: true, code_owners: true)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [merge_request.id] }
  end

  describe '#perform' do
    context 'when merge request does not exist' do
      it 'does nothing' do
        expect(MergeRequests::ReviewerAssignment::AssignService).not_to receive(:new)

        described_class.new.perform(non_existing_record_id)
      end
    end

    context 'when reviewer auto assignment is disabled' do
      before do
        merge_request.project.project_setting.update!(reviewer_assignment_strategy: 'disabled')
      end

      it 'does nothing' do
        expect(MergeRequests::ReviewerAssignment::AssignService).not_to receive(:new)

        described_class.new.perform(merge_request.id)
      end
    end

    context 'when the merge request is a draft' do
      before do
        merge_request.update!(title: "Draft: #{merge_request.title}")
      end

      it 'does not assign reviewers' do
        expect(MergeRequests::ReviewerAssignment::AssignService).not_to receive(:new)

        described_class.new.perform(merge_request.id)
      end
    end

    context 'when a non-automated reviewer is already assigned' do
      before do
        merge_request.reviewers = [create(:user)]
      end

      it 'does not assign reviewers' do
        expect(MergeRequests::ReviewerAssignment::AssignService).not_to receive(:new)

        described_class.new.perform(merge_request.id)
      end
    end

    context 'when only the Duo Code Review bot is assigned as a reviewer' do
      before do
        merge_request.reviewers = [create(:user, :duo_code_review_bot)]
      end

      it 'still delegates to AssignService' do
        expect_next_instance_of(
          MergeRequests::ReviewerAssignment::AssignService,
          merge_request: merge_request,
          current_user: author
        ) do |service|
          expect(service).to receive(:execute)
        end

        described_class.new.perform(merge_request.id)
      end
    end

    # Rows created before the bespoke path was removed can still hold `dap_powered`.
    # It maps to no strategy, so it counts as disabled rather than reaching
    # AssignService to be skipped there. See #607678.
    context 'when reviewer_assignment_strategy is still dap_powered' do
      before do
        project.project_setting.update!(reviewer_assignment_strategy: 'dap_powered')
      end

      it 'does not assign reviewers', :aggregate_failures do
        expect(MergeRequests::ReviewerAssignment::AssignService).not_to receive(:new)

        described_class.new.perform(merge_request.id)

        expect(merge_request.reset.reviewers).to be_empty
      end
    end

    context 'when reviewer_assignment_strategy is code_owners' do
      it 'delegates to AssignService with the merge request author as current_user' do
        expect_next_instance_of(
          MergeRequests::ReviewerAssignment::AssignService,
          merge_request: merge_request,
          current_user: author
        ) do |service|
          expect(service).to receive(:execute)
        end

        described_class.new.perform(merge_request.id)
      end
    end
  end
end
