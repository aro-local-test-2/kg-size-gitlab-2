# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::CancelReviewService, feature_category: :duo_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be_with_reload(:merge_request) do
    create(:merge_request, source_project: project, target_project: project)
  end

  let_it_be(:code_review_definition) { ::Ai::Catalog::FoundationalFlow.code_review.foundational_flow_reference }

  subject(:execute) { described_class.new(merge_request: merge_request, current_user: current_user).execute }

  def create_workflow(status, definition: code_review_definition, messaging_context: nil)
    create(:duo_workflows_workflow, status, project: project,
      workflow_definition: definition, merge_request_id: merge_request.id,
      messaging_callback_context: messaging_context)
  end

  def create_progress_note
    review_bot = build_stubbed(:user, user_type: :duo_code_review_bot)

    ::SystemNotes::MergeRequestsService.new(
      noteable: merge_request,
      container: merge_request.project,
      author: review_bot
    ).duo_code_review_started
  end

  context 'when an in-flight code review workflow exists' do
    let_it_be(:workflow) { create_workflow(:running) }

    before do
      create_progress_note
    end

    it 'stops the workflow and destroys the progress note' do
      expect { execute }.to change { merge_request.reload.duo_code_review_progress_note }.to(nil)

      expect(workflow.reload.status_name).to eq(:stopped)
    end
  end

  context 'when a Duo conversation runs alongside the review' do
    let_it_be(:workflow) { create_workflow(:running) }
    let_it_be(:conversation) do
      create_workflow(:running, messaging_context: { 'adapter' => 'gitlab_duo_note' })
    end

    before do
      create_progress_note
    end

    it 'stops only the review and still destroys the progress note' do
      expect { execute }.to change { merge_request.reload.duo_code_review_progress_note }.to(nil)

      expect(workflow.reload.status_name).to eq(:stopped)
      expect(conversation.reload.status_name).to eq(:running)
    end
  end

  context 'when there is no in-flight workflow' do
    let!(:note) { create_progress_note }

    it 'does nothing' do
      expect(::Ai::DuoWorkflows::UpdateWorkflowStatusService).not_to receive(:new)

      expect { execute }.not_to change { merge_request.reload.duo_code_review_progress_note&.id }
    end
  end

  context 'when one of two in-flight workflows fails to stop' do
    let_it_be(:stopped_workflow) { create_workflow(:running) }
    let_it_be(:stuck_workflow) { create_workflow(:running) }

    before do
      create_progress_note

      allow(::Ai::DuoWorkflows::UpdateWorkflowStatusService).to receive(:new).and_wrap_original do |method, **kwargs|
        service = method.call(**kwargs)

        if kwargs[:workflow] == stuck_workflow
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'nope'))
        end

        service
      end
    end

    it 'keeps the progress note and logs the failure' do
      expect(::Gitlab::AppLogger).to receive(:warn).with(
        message: 'Duo Code Review flow not stopped',
        error_message: 'nope',
        merge_request_id: merge_request.id,
        workflow_id: stuck_workflow.id
      )

      expect { execute }.not_to change { merge_request.reload.duo_code_review_progress_note&.id }

      expect(stopped_workflow.reload.status_name).to eq(:stopped)
      expect(stuck_workflow.reload.status_name).to eq(:running)
    end
  end

  context 'when a workflow does not match the flow definition or status' do
    let_it_be(:other_flow) { create_workflow(:running, definition: 'chat') }
    let_it_be(:terminal_flow) { create_workflow(:finished) }

    before do
      create_progress_note
    end

    it 'ignores both workflows and leaves the progress note' do
      expect(::Ai::DuoWorkflows::UpdateWorkflowStatusService).not_to receive(:new)

      expect { execute }.not_to change { merge_request.reload.duo_code_review_progress_note&.id }
    end
  end
end
