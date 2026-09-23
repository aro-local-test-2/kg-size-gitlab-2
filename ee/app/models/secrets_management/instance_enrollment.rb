# frozen_string_literal: true

module SecretsManagement
  class InstanceEnrollment
    def self.enrolled?
      ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled
    end

    # Secrets Manager on self-managed is beta only, so all enrolled instances are in beta.
    # When GA launches, add a secrets_manager_instance_ga_enrolled setting and also check !ga_enrolled?.
    def self.beta?
      enrolled?
    end

    # Self-managed counterpart of `NamespaceEnrollment.beta_enrolled?`. The marker
    # is written at enrollment time (`InstanceEnrollmentService#beta_enrollment?`)
    # and backfilled for earlier enrollments, so it never depends on live rows.
    def self.beta_enrolled?
      beta? && ::Gitlab::CurrentSettings.secrets_manager_instance_beta_enrolled
    end

    # Add-on intent: an administrator enabled paid Secrets Manager for the
    # instance without a trial. Distinct from plain enrollment, which the beta
    # opt-in also sets. Mirrors NamespaceEnrollment.add_on_requested?.
    def self.add_on_requested?
      enrolled? && ::Gitlab::CurrentSettings.secrets_manager_instance_add_on_requested_at.present?
    end

    # Writes the stamp only while it is still empty, so of two concurrent
    # enables exactly one gets `true` and claims the first conversion. Callers
    # must expire the settings and entitlement caches afterwards.
    def self.stamp_add_on_intent!
      settings = ::Gitlab::CurrentSettings.current_application_settings
      now = Time.current

      updated = ::ApplicationSetting
        .where(id: settings.id, secrets_manager_instance_add_on_requested_at: nil)
        .update_all(secrets_manager_instance_add_on_requested_at: now, updated_at: now)

      # The raw write bypasses the loaded record; bring it back in step so
      # readers holding the same cached instance see the stamp immediately.
      settings.reset if settings.persisted?

      updated == 1
    end

    def self.enrollment_allowed?
      !::Gitlab.com? && # rubocop:disable Gitlab/AvoidGitlabInstanceChecks -- instance enrollment is self-managed only
        ::License.feature_available?(:native_secrets_management) &&
        ::Feature.enabled?(:secrets_manager_instance_enrollment) # rubocop:disable Gitlab/FeatureFlagWithoutActor -- instance-level flag has no actor
    end

    # Gates the instance trial and add-on mutations and the entitlement query.
    # Self-managed only: gitlab.com keys entitlement by top-level group, not by instance.
    def self.paid_experience_allowed?
      !::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions) &&
        ::License.feature_available?(:native_secrets_management) &&
        ::Feature.enabled?(:secrets_manager_paid_experience, :instance)
    end

    # Anything but an online cloud license (offline, legacy, or none) has no CDot
    # connectivity, so no trial can start; the entitlement state cannot tell this apart.
    def self.offline_license?
      !::License.current&.online_cloud_license?
    end
  end
end
