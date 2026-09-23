# frozen_string_literal: true

module Security
  class SyncProjectPoliciesWorker
    include ApplicationWorker
    prepend ::Geo::SkipSecondary

    data_consistency :sticky

    deduplicate :until_executing, including_scheduled: true
    idempotent!
    feature_category :security_policy_management

    concurrency_limit -> { 200 }

    def perform(project_id, policy_configuration_id, params = {})
      project = Project.find_by_id(project_id)
      policy_configuration = Security::OrchestrationPolicyConfiguration.find_by_id(policy_configuration_id)

      return unless project && policy_configuration

      if link_policy_configuration?(params, policy_configuration)
        Security::SecurityOrchestrationPolicies::LinkPolicyConfigurationService.new(
          project: project,
          configuration: policy_configuration
        ).execute
      else
        policy_configuration.security_policies.undeleted.pluck_primary_key.each do |security_policy_id|
          Security::SyncProjectPolicyWorker.perform_async(
            project.id, security_policy_id, {}, build_policy_payload(params, security_policy_id)
          )
        end
      end
    end

    private

    def build_policy_payload(params, security_policy_id)
      return {} unless params['force_resync']

      { event: { event_type: 'Security::PolicyResyncEvent', data: { security_policy_id: security_policy_id } } }
    end

    def link_policy_configuration?(params, policy_configuration)
      params['triggered_by_assign'] &&
        Feature.enabled?(:sync_policies_in_bulk_on_policy_configuration_assign, policy_configuration.source)
    end
  end
end
