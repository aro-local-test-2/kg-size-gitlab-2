# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::StartReviewWorker, :request_store,
  feature_category: :duo_code_review do
  let_it_be(:project) { create(:project, :repository, :in_group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:review_service) { instance_double(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService, execute: nil) }

  subject(:perform) { described_class.new.perform(merge_request.id, user.id) }

  before do
    allow(::Gitlab::Duo::CodeReview).to receive(:dap?).and_return(true)
  end

  shared_examples 'does not start a review' do |reason|
    it 'does not start a review by either route' do
      expect(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService).not_to receive(:new)
      expect(::Llm::ReviewMergeRequestService).not_to receive(:new)

      perform
    end

    it "logs the skip with reason #{reason}" do
      # Allowed first so unrelated log lines (note creation, for one) do not fail the
      # constrained expectation below.
      allow(::Gitlab::AppLogger).to receive(:info)

      expect(::Gitlab::AppLogger).to receive(:info).with(
        hash_including(
          message: "Duo Code Review flow not started: #{reason}",
          merge_request_id: an_instance_of(Integer)
        )
      )

      perform
    end
  end

  it 'starts the review for the given merge request and user' do
    expect(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService)
      .to receive(:new).with(user: user, merge_request: merge_request).and_return(review_service)
    expect(review_service).to receive(:execute)

    perform
  end

  # This is the whole reason the worker exists: if the opt-out is ever dropped, the job
  # inherits the enqueuing flow's identity and the original bug returns.
  # See https://gitlab.com/gitlab-org/gitlab/-/work_items/612038.
  it 'opts out of the composite identity passthrough' do
    expect(described_class.skip_composite_identity_passthrough?).to be(true)
  end

  describe 'guards' do
    context 'when the merge request no longer exists' do
      subject(:perform) { described_class.new.perform(non_existing_record_id, user.id) }

      it_behaves_like 'does not start a review', :merge_request_not_found
    end

    context 'when the user no longer exists' do
      subject(:perform) { described_class.new.perform(merge_request.id, non_existing_record_id) }

      it_behaves_like 'does not start a review', :user_not_found
    end

    context 'when the merge request is no longer startable' do
      before do
        allow_next_found_instance_of(MergeRequest) do |mr|
          allow(mr).to receive(:duo_code_review_startable?).and_return(false)
        end
      end

      it_behaves_like 'does not start a review', :not_startable
    end

    context 'when the merge request was merged after enqueue' do
      before do
        merge_request.mark_as_merged!
      end

      it_behaves_like 'does not start a review', :not_startable
    end

    context 'when the merge request was closed after enqueue' do
      before do
        merge_request.close!
      end

      it_behaves_like 'does not start a review', :not_startable
    end

    context 'when the user lost access to Duo Code Review after enqueue' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:dap?).and_return(false)

        allow_next_found_instance_of(MergeRequest) do |mr|
          allow(mr).to receive(:ai_review_merge_request_allowed?).and_return(false)
        end
      end

      it_behaves_like 'does not start a review', :duo_code_review_unavailable
    end

    # Sidekiq delivers at least once, so this is what makes the `idempotent!` declaration
    # true rather than aspirational.
    context 'when a review flow is already in flight' do
      before do
        allow_next_found_instance_of(MergeRequest) do |mr|
          allow(mr).to receive(:duo_code_review_in_flight?).and_return(true)
        end
      end

      it_behaves_like 'does not start a review', :review_already_in_flight

      # RequestReviewService has already posted the "requested review from Duo" note, sent
      # the todo and the email, so exiting on a log line alone leaves the requester waiting
      # for a review that will never arrive. The mention entry point answers the same race.
      it 'tells the requester a review is already running' do
        expect { perform }.to change { merge_request.notes.count }.by(1)

        expect(merge_request.notes.last.note).to eq(::Gitlab::Duo::CodeReview::Messages.review_in_progress)
      end
    end
  end

  # The request-side funnel falls back to the classic flow when the mode is not DAP, and the
  # worker re-checks the mode, so it has to offer the same fallback or a mode flip between
  # enqueue and execution silently drops the review.
  context 'when the mode is no longer DAP but the classic flow is still allowed' do
    before do
      allow(::Gitlab::Duo::CodeReview).to receive(:dap?).and_return(false)

      allow_next_found_instance_of(MergeRequest) do |mr|
        allow(mr).to receive(:ai_review_merge_request_allowed?).and_return(true)
      end
    end

    it 'falls back to the classic review service' do
      expect(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService).not_to receive(:new)
      expect_next_instance_of(::Llm::ReviewMergeRequestService, user, merge_request) do |svc|
        expect(svc).to receive(:execute)
      end

      perform
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [merge_request.id, user.id] }

    # The stand-in mimics the one side effect the in-flight guard reads - a running
    # code review workflow for this merge request - so the second run exercises the real
    # guard rather than a stub of it.
    before do
      allow(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService).to receive(:new) do
        value = ::Ai::DuoWorkflows::Workflow.state_machines[:status].states[:running].value
        create(:duo_workflows_workflow, project: project, user: user, status: value,
          workflow_definition: ::Ai::Catalog::FoundationalFlow.code_review.foundational_flow_reference,
          merge_request_id: merge_request.id)

        review_service
      end
    end

    it 'starts exactly one review flow across repeated runs' do
      perform_idempotent_work

      expect(::Ai::DuoWorkflows::CodeReview::ReviewMergeRequestService).to have_received(:new).once
    end
  end
end
