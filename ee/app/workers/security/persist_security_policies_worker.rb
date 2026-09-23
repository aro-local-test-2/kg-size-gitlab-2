# frozen_string_literal: true

module Security
  class PersistSecurityPoliciesWorker
    include ApplicationWorker
    include ::Gitlab::InternalEventsTracking

    data_consistency :sticky
    idempotent!
    deduplicate :until_executed, if_deduplicated: :reschedule_once
    feature_category :security_policy_management

    def perform(configuration_id, params = {})
      configuration = Security::OrchestrationPolicyConfiguration.find_by_id(configuration_id) || return

      configuration.invalidate_policy_yaml_cache

      force_resync = params['force_resync'] || false
      triggered_by_assign = params['triggered_by_assign'] || false

      persist_policy(configuration, configuration.scan_result_policies, :approval_policy,
        force_resync, triggered_by_assign)
      persist_policy(configuration, configuration.scan_execution_policy, :scan_execution_policy,
        force_resync, triggered_by_assign)
      persist_policy(configuration, configuration.pipeline_execution_policy, :pipeline_execution_policy,
        force_resync, triggered_by_assign)
      persist_policy(configuration, configuration.vulnerability_management_policy, :vulnerability_management_policy,
        force_resync, triggered_by_assign)
      persist_policy(
        configuration,
        configuration.pipeline_execution_schedule_policy,
        :pipeline_execution_schedule_policy,
        force_resync,
        triggered_by_assign
      )

      if ::Security::DependencyFirewall::Availability.feature_flag_enabled?(configuration.source)
        persist_policy(configuration, configuration.dependency_firewall_policy,
          :dependency_firewall_policy, force_resync, triggered_by_assign)
      end

      if triggered_by_assign &&
          Feature.enabled?(:sync_policies_in_bulk_on_policy_configuration_assign, configuration.source)
        ::Gitlab::EventStore.publish(
          Security::PolicyConfigurationAssignedEvent.build(configuration: configuration)
        )
      end

      track_csp_usage(configuration)

      Security::CollectPoliciesLimitAuditEventsWorker.perform_async(configuration.id)
    end

    private

    def persist_policy(configuration, policies, policy_type, force_resync = false, triggered_by_assign = false)
      Security::SecurityOrchestrationPolicies::PersistPolicyService.new(
        policy_configuration: configuration,
        policies: policies,
        policy_type: policy_type,
        force_resync: force_resync,
        triggered_by_assign: triggered_by_assign
      ).execute
    end

    def track_csp_usage(configuration)
      return unless configuration.designated_as_csp?

      track_internal_event(
        'sync_csp_configuration',
        namespace: configuration.namespace
      )
    end
  end
end
