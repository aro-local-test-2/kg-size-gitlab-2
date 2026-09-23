# frozen_string_literal: true

module Vulnerabilities
  class TriggerResolutionWorkflowWorker
    include ApplicationWorker
    include Gitlab::InternalEventsTracking
    include Gitlab::Utils::StrongMemoize
    include Vulnerabilities::WorkflowTriggerable
    prepend Vulnerabilities::WorkflowTrackable

    sidekiq_retries_exhausted do |job, _exception|
      new.handle_retry_exhaustion(job)
    end

    StartWorkflowServiceError = Class.new(StandardError)

    data_consistency :delayed
    feature_category :vulnerability_management
    urgency :throttled
    idempotent!
    concurrency_limit -> { 100 }
    sidekiq_options retry: 10
    skip_composite_identity_passthrough!

    CONFIDENCE_THRESHOLD = 0.6
    WORKFLOW_DEFINITION = 'resolve_sast_vulnerability/v1'
    WORKFLOW_NAME = 'vulnerability resolution workflow'

    def perform(item_id, execution_id = nil)
      finding = execution_id ? find_bulk_finding(item_id) : find_automatic_finding(item_id)
      return unless finding
      return if execution_id && !finding.sast?
      return unless finding.resolution_workflow_enabled?

      vulnerability = finding.vulnerability
      project = finding.project

      user = resolve_workflow_user(vulnerability, project)
      unless user
        log_no_eligible_user(vulnerability, project)
        return
      end

      consumer = find_consumer(user, project)
      unless consumer
        log_consumer_not_found(finding)
        return
      end

      service_account = find_service_account(consumer)

      unless service_account
        log_service_account_not_found(vulnerability, consumer, WORKFLOW_NAME)
        return
      end

      result = trigger_workflow(vulnerability, project, user, consumer, service_account)
      if result.success?
        track_event(finding) if create_triggered_workflow_record(finding, result)
      else
        handle_error(result, finding)
      end
    rescue StandardError => error
      log_exception(error, item_id, execution_id, finding&.vulnerability_id)
    end

    protected

    def finding_from_args(finding_uuid)
      find_bulk_finding(finding_uuid)
    end

    private

    def find_automatic_finding(vulnerability_flag_id)
      vulnerability_flag = find_vulnerability_flag(vulnerability_flag_id)
      return unless vulnerability_flag
      return unless vulnerability_flag.eligible_for_resolution_workflow?

      vulnerability_flag.finding
    end

    def find_bulk_finding(finding_uuid)
      strong_memoize_with(:find_bulk_finding, finding_uuid) do
        ::Vulnerabilities::Finding.by_uuid(finding_uuid).first
      end
    end

    def find_vulnerability_flag(vulnerability_flag_id)
      ::Vulnerabilities::Flag.with_associations.find_by_id(vulnerability_flag_id)
    end

    def trigger_workflow(vulnerability, project, user, consumer, service_account)
      flow_params = {
        item_consumer: consumer,
        service_account: service_account,
        execute_workflow: true,
        event_type: 'sidekiq_worker',
        user_prompt: vulnerability.id.to_s
      }

      ::Ai::Catalog::Flows::ExecuteService.new(
        project: project,
        current_user: user,
        params: flow_params
      ).execute
    end

    def find_consumer(user, project)
      ::Ai::Catalog::ItemConsumersFinder.new(user, params: {
        project_id: project.id,
        item_type: Ai::Catalog::Item::FLOW_TYPE,
        foundational_flow_reference: WORKFLOW_DEFINITION
      }).execute.first
    end

    def find_service_account(consumer)
      if consumer.project.present?
        consumer.parent_item_consumer&.service_account
      else
        consumer.service_account
      end
    end

    def log_consumer_not_found(finding)
      Gitlab::AppLogger.error(
        message: 'No consumer configured for vulnerability resolution workflow',
        finding_id: finding.id,
        project_id: finding.project_id,
        workflow_definition: WORKFLOW_DEFINITION
      )
    end

    def create_triggered_workflow_record(finding, response)
      workflow = response.payload[:workflow]
      return unless workflow

      ::Vulnerabilities::TriggeredWorkflow.create!(
        vulnerability_occurrence_id: finding.id,
        workflow_id: workflow.id,
        workflow_name: :resolve_sast_vulnerability
      )
    rescue ActiveRecord::RecordInvalid => error
      Gitlab::ErrorTracking.track_exception(
        error,
        vulnerability_id: finding.vulnerability_id,
        workflow_id: workflow&.id
      )

      nil
    end

    def handle_error(result, finding)
      Gitlab::AppLogger.error(
        message: 'Failed to create and start workflow for vulnerability resolution',
        vulnerability_id: finding.vulnerability_id,
        finding_id: finding.id,
        error: result.message,
        reason: result.reason
      )

      raise StartWorkflowServiceError, "Failed to start workflow for vulnerability resolution: #{result.message}"
    end

    def log_exception(error, item_id, execution_id, vulnerability_id)
      context = { vulnerability_id: vulnerability_id }

      if execution_id
        context[:execution_id] = execution_id
        context[:finding_uuid] = item_id
      else
        context[:vulnerability_flag_id] = item_id
      end

      Gitlab::ErrorTracking.log_and_raise_exception(error, **context)
    end

    def track_event(finding)
      vulnerability = finding.vulnerability

      track_internal_event(
        'trigger_sast_vulnerability_resolution_workflow',
        project: finding.project,
        additional_properties: {
          label: 'automatic',
          value: vulnerability.id,
          property: vulnerability.severity
        }
      )
    end
  end
end
