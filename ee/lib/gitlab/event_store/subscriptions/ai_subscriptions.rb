# frozen_string_literal: true

module Gitlab
  module EventStore
    module Subscriptions
      class AiSubscriptions < BaseSubscriptions
        def register
          store.subscribe ::Ai::ActiveContext::Code::CreateEnabledNamespaceEventWorker,
            to: ::Ai::ActiveContext::Code::CreateEnabledNamespaceEvent

          store.subscribe ::Ai::ActiveContext::Code::MarkRepositoryAsReadyEventWorker,
            to: ::Ai::ActiveContext::Code::MarkRepositoryAsReadyEvent

          store.subscribe ::Ai::ActiveContext::Code::MarkRepositoryAsPendingDeletionEventWorker,
            to: ::Ai::ActiveContext::Code::MarkRepositoryAsPendingDeletionEvent

          store.subscribe ::Ai::ActiveContext::Code::ProcessPendingEnabledNamespaceEventWorker,
            to: ::Ai::ActiveContext::Code::ProcessPendingEnabledNamespaceEvent

          store.subscribe ::Ai::ActiveContext::Code::ProcessInvalidEnabledNamespaceEventWorker,
            to: ::Ai::ActiveContext::Code::ProcessInvalidEnabledNamespaceEvent

          store.subscribe ::Ai::DuoWorkflows::UpdateWorkflowStatusEventWorker,
            to: ::Ci::Workloads::WorkloadFinishedEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ci::Workloads::WorkloadFinishedEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ai::DuoWorkflows::WorkflowStartedEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ai::DuoWorkflows::WorkflowFinishedEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ai::DuoWorkflows::WorkflowFailedEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ai::DuoWorkflows::WorkflowApprovalRequiredEvent

          store.subscribe ::Ai::Messaging::CallbackWorker,
            to: ::Ai::DuoWorkflows::WorkflowInputRequiredEvent

          store.subscribe ::Ai::Catalog::Flows::ExecuteMergeRequestCreatedWorkflowTriggersWorker,
            to: ::MergeRequests::AfterCreateCloudEvent,
            if: ->(event) {
              ::Ai::FlowTrigger.registered_for?(event.event_data[:project_id], :merge_request)
            }

          store.subscribe ::Ai::Catalog::Flows::ExecuteMergeRequestReadyWorkflowTriggersWorker,
            to: ::MergeRequests::ReadyEvent

          store.subscribe ::Ai::Catalog::Flows::ExecuteCodeConflictAiWorkflowTriggersWorker,
            to: ::MergeRequests::CodeConflictEvent

          store.subscribe ::Ai::Catalog::Flows::ExecuteMergeRequestApprovedWorkflowTriggersWorker,
            to: ::MergeRequests::ApprovedCloudEvent

          store.subscribe ::Ai::Catalog::Flows::ExecuteMergeRequestMergedWorkflowTriggersWorker,
            to: ::MergeRequests::MergedCloudEvent,
            if: ->(event) {
              ::Ai::FlowTrigger.registered_for?(event.event_data[:project_id], :merge_request)
            }

          store.subscribe ::Ai::Catalog::Flows::ExecuteWorkItemCreatedWorkflowTriggersWorker,
            to: ::WorkItems::CreatedEvent,
            if: ->(event) {
              ::Ai::FlowTrigger.registered_for?(event.event_data[:project_id], :work_item)
            }

          store.subscribe ::Ai::Catalog::Flows::ExecuteWorkItemStatusChangedWorkflowTriggersWorker,
            to: ::WorkItems::StatusChangedEvent,
            if: ->(event) {
              ::Ai::FlowTrigger.registered_for?(event.event_data[:project_id], :work_item)
            }
        end
      end
    end
  end
end
