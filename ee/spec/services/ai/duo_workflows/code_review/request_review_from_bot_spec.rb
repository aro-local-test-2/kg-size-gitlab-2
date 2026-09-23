# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::RequestReviewFromBot, feature_category: :duo_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

  subject(:service) { described_class.new(merge_request: merge_request, current_user: user, bot: bot) }

  describe '#execute' do
    context 'when the bot is already a reviewer' do
      before do
        merge_request.merge_request_reviewers.create!(reviewer: bot)
      end

      it 'requests a re-review and returns the RequestReviewService result' do
        expect_next_instance_of(
          ::MergeRequests::RequestReviewService,
          project: project, current_user: user
        ) do |svc|
          expect(svc).to receive(:execute).with(merge_request, bot).and_return({ status: :success })
        end

        expect(service.execute).to eq({ status: :success })
      end
    end

    context 'when the bot is not yet a reviewer' do
      it 'adds the bot as a reviewer and returns the UpdateReviewersService result' do
        expect_next_instance_of(
          ::MergeRequests::UpdateReviewersService,
          project: project,
          current_user: user,
          params: { reviewer_ids: merge_request.reviewer_ids | [bot.id] }
        ) do |svc|
          expect(svc).to receive(:execute).with(merge_request).and_return({ status: :success })
        end

        expect(service.execute).to eq({ status: :success })
      end
    end
  end
end
