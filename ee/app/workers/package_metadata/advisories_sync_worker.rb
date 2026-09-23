# frozen_string_literal: true

module PackageMetadata
  class AdvisoriesSyncWorker
    include ApplicationWorker
    include CronjobQueue # rubocop:disable Scalability/CronWorkerContext
    include ExclusiveLeaseGuard

    LEASE_TIMEOUT = 5.minutes

    data_consistency :always
    feature_category :software_composition_analysis
    urgency :low

    idempotent!
    sidekiq_options retry: false
    worker_has_external_dependencies!

    def perform
      return unless should_run?

      try_obtain_lease do
        SyncService.execute(data_type: 'advisories', lease: exclusive_lease)
      end
    end

    private

    def should_run?
      return false unless feature_available?
      return false if Rails.env.development? && ENV.fetch('PM_SYNC_IN_DEV', 'false') != 'true'

      true
    end

    # dependency_scanning is Ultimate-only; Premium reaches the sync through the
    # dependency firewall, which consumes this data.
    # https://gitlab.com/gitlab-org/gitlab/-/work_items/630259
    def feature_available?
      ::License.feature_available?(:dependency_scanning) ||
        ::Security::DependencyFirewall::Availability.instance_configurable?
    end

    def lease_timeout
      LEASE_TIMEOUT
    end
  end
end
