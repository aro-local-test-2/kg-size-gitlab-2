# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::CleanupAiSuggestedReviewersWorker, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:other_merge_request) { create(:merge_request, :simple, source_project: project) }

  describe '.dispatch?' do
    let(:event) { ::MergeRequests::MergedEvent.new(data: { merge_request_id: merge_request.id }) }

    it 'is true only when the merge request has suggestions' do
      expect(described_class.dispatch?(event)).to be(false)

      create(:ai_suggested_reviewer, merge_request: merge_request)

      expect(described_class.dispatch?(event)).to be(true)
    end
  end

  describe '#handle_event' do
    subject(:handle_event) { described_class.new.handle_event(event) }

    context 'when the merge request is merged' do
      let(:event) { ::MergeRequests::MergedEvent.new(data: { merge_request_id: merge_request.id }) }

      it 'removes the suggestions of that merge request only' do
        create(:ai_suggested_reviewer, merge_request: merge_request)
        kept = create(:ai_suggested_reviewer, merge_request: other_merge_request)

        expect { handle_event }.to change { merge_request.ai_suggested_reviewers.count }.from(1).to(0)
        expect(other_merge_request.ai_suggested_reviewers).to contain_exactly(kept)
      end
    end
  end
end
