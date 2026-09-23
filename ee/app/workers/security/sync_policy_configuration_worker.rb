# frozen_string_literal: true

module Security
  class SyncPolicyConfigurationWorker
    include Gitlab::EventStore::Subscriber

    data_consistency :sticky
    deduplicate :until_executed, if_deduplicated: :reschedule_once
    idempotent!

    concurrency_limit -> { 100 }

    feature_category :security_policy_management

    BATCH_SIZE = 100
    BATCH_DELAY_INTERVAL = 1.second

    # Override: the CloudEvent `time` attribute varies per event, so deduplicate on configuration_id only.
    def self.idempotency_arguments(arguments)
      _event_type, data = arguments

      [data.dig("data", "configuration_id")]
    end

    def handle_event(event)
      configuration_id = event.event_data[:configuration_id]
      configuration = Security::OrchestrationPolicyConfiguration.find_by_id(configuration_id) || return

      return unless Feature.enabled?(
        :sync_policies_in_bulk_on_policy_configuration_assign,
        configuration.source
      )

      config_context = if configuration.namespace?
                         { namespace: configuration.namespace }
                       else
                         { project: configuration.project }
                       end

      total_slice_index = 0

      configuration.all_project_ids do |project_ids|
        project_ids.each_slice(BATCH_SIZE) do |batch|
          delay = (total_slice_index + 1) * BATCH_DELAY_INTERVAL

          ::Security::SyncProjectPoliciesWorker.bulk_perform_in_with_contexts(
            delay,
            batch,
            arguments_proc: ->(project_id) { [project_id, configuration_id, { 'triggered_by_assign' => true }] },
            context_proc: ->(_) { config_context }
          )

          total_slice_index += 1
        end
      end
    end
  end
end
