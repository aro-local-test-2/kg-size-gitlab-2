# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::UpdateReviewerStateService, feature_category: :code_review_workflow do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:merge_request) { create(:merge_request, reviewers: [create(:user)]) }
  let_it_be_with_reload(:non_reviewer) { create(:user) }
  let(:project) { merge_request.project }
  let(:service) { described_class.new(project: project, current_user: non_reviewer) }

  before_all do
    merge_request.project.add_developer(non_reviewer)
  end

  before do
    stub_licensed_features(multiple_merge_request_reviewers: true)
  end

  describe '#execute' do
    context 'when a non-reviewer submits a review' do
      context 'when the user submits a review' do
        where(:submitted_state) do
          %w[reviewed approved requested_changes].map { |reviewer_state| [reviewer_state] }
        end

        with_them do
          it 'creates the reviewer with the submitted state and returns success', :aggregate_failures do
            result = nil

            expect { result = service.execute(merge_request, submitted_state) }
              .to change { merge_request.merge_request_reviewers.where(user_id: non_reviewer.id).count }.by(1)

            expect(result[:status]).to eq :success
            expect(merge_request.find_reviewer(non_reviewer).state).to eq submitted_state
          end
        end
      end

      context 'and the reviewer limit is already reached' do
        before do
          stub_const('Issuable::MAX_NUMBER_OF_ASSIGNEES_OR_REVIEWERS', merge_request.reviewers.size)
        end

        it 'does not add another reviewer and returns an error', :aggregate_failures do
          result = nil

          expect { result = service.execute(merge_request, 'reviewed') }
            .not_to change { merge_request.merge_request_reviewers.count }

          expect(result[:status]).to eq :error
        end
      end

      it 'reflects the newly added reviewer in the webhook payload changes', :aggregate_failures do
        changes = nil

        allow(service).to receive(:execute_hooks) do |mr, _action, options|
          changes = mr.hook_reviewer_changes(options[:old_associations])
        end

        expect(service.execute(merge_request, 'reviewed')[:status]).to eq :success
        expect(changes).to have_key(:reviewers)

        old_reviewer_ids = changes[:reviewers].first.map { |r| r[:id] }
        new_reviewer_ids = changes[:reviewers].last.map { |r| r[:id] }

        expect(old_reviewer_ids).not_to include(non_reviewer.id)
        expect(new_reviewer_ids).to include(non_reviewer.id)
      end

      it 'records the reviewer_first_assigned_at metric' do
        service.execute(merge_request, 'reviewed')

        expect(merge_request.metrics.reload.reviewer_first_assigned_at).to be_present
      end
    end

    context 'when the submitter is the merge request author' do
      let(:service) { described_class.new(project: project, current_user: merge_request.author) }

      before do
        project.add_developer(merge_request.author)
      end

      it 'does not add the author as a reviewer of their own merge request', :aggregate_failures do
        expect { service.execute(merge_request, 'reviewed') }
          .not_to change { merge_request.merge_request_reviewers.count }

        expect(merge_request.find_reviewer(merge_request.author)).to be_nil
      end
    end
  end
end
