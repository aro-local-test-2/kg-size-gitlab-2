# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ExecuteWorkItemStatusChangedWorkflowTriggersWorker,
  feature_category: :code_suggestions do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:work_item) { create(:work_item, project: project, author: user) }
  let_it_be(:status) { ::WorkItems::Statuses::SystemDefined::Status.find(2) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]]
    )
  end

  let(:cloud_event) { ::WorkItems::StatusChangedEvent.build(work_item: work_item, current_user: user, status: status) }
  let(:resource) { work_item }
  let(:event) { cloud_event }

  let(:wrong_event) do
    ::MergeRequests::DraftStateChangeEvent.new(
      data: { current_user_id: user.id, merge_request_id: non_existing_record_id, new_draft_status: false }
    )
  end

  let(:doomed_resource) { create(:work_item, project: project) }

  let(:doomed_resource_event) do
    ::WorkItems::StatusChangedEvent.build(work_item: doomed_resource, current_user: user, status: status)
  end

  it_behaves_like 'subscribes to event'
  it_behaves_like 'a cloud events flow trigger worker' do
    # Override filter_data to include the status name injected by filter_data_extras.
    let(:filter_data) { { 'action' => 'status_changed', 'status' => { 'name' => status.name.to_s } } }
  end

  describe '#handle_event' do
    subject(:handle_event) { described_class.new.handle_event(cloud_event) }

    let(:run_service) { instance_double(::Ai::FlowTriggers::RunService) }
    let(:filter_evaluator) { instance_double(::Ai::FlowTriggers::FilterEvaluator, allowed?: true) }

    before do
      allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_return(filter_evaluator)
      allow(::Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
      allow(run_service).to receive(:execute)
    end

    context 'when filter_data_extras returns an action key' do
      before do
        allow_next_instance_of(described_class) do |worker|
          allow(worker).to receive(:filter_data_extras).and_return('action' => 'other', 'status' => { 'name' => 'x' })
        end
      end

      it 'keeps the action defined by the worker class' do
        expect(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).with(
          hash_including(data: { 'action' => 'status_changed', 'status' => { 'name' => 'x' } })
        ).and_return(filter_evaluator)

        handle_event
      end
    end

    context 'when the work item has no project (group-level epic)' do
      let_it_be(:group) { create(:group) }
      let_it_be(:epic) { create(:work_item, :epic, namespace: group, author: user) }

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: epic, current_user: user, status: status)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the trigger has a status.name filter' do
      # Separate project so the top-level unfiltered `flow_trigger` does not also fire.
      let_it_be(:filtered_project) { create(:project) }
      let_it_be(:filtered_work_item) { create(:work_item, project: filtered_project, author: user) }

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: filtered_work_item, current_user: user, status: status)
      end

      let(:filter) do
        {
          'work_item' => {
            'rules' => [
              { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
              { 'field' => 'status.name', 'operator' => 'in', 'value' => [filtered_status_name] }
            ]
          }
        }
      end

      before do
        create(:ai_flow_trigger,
          project: filtered_project,
          user: service_account,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: filter)

        allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_call_original
      end

      context 'when the new status name matches the filter' do
        let(:filtered_status_name) { status.name.to_s }

        it 'starts a flow' do
          expect(run_service).to receive(:execute)

          handle_event
        end
      end

      context 'when the new status name does not match the filter' do
        let(:filtered_status_name) { 'Some Other Status' }

        it 'does not start a flow' do
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end
    end
  end
end
