# frozen_string_literal: true

module Security
  # Helpers for the two Security::PolicyAvailability entry points. Dependency Firewall is a Premium
  # feature while security_orchestration_policies is Ultimate, so any_available? gates open for
  # namespaces that never had an Ultimate licence - these helpers make that case cheap to express.
  module PolicyAvailabilityHelpers
    # Satisfies every condition Security::DependencyFirewall::Availability.enforced_for? requires:
    # the SaaS feature, the licence and the root namespace setting. The feature flag
    # (dependency_firewall_phase1) is left alone because flags default to enabled in specs.
    def stub_dependency_firewall_enforced(root_group, security_orchestration_policies: false)
      stub_saas_features(dependency_firewall: true)
      stub_licensed_features(
        dependency_firewall: true,
        security_orchestration_policies: security_orchestration_policies
      )
      root_group.namespace_settings.update!(dependency_firewall_enabled: true)
    end

    def stub_dependency_firewall_unavailable(security_orchestration_policies: false)
      stub_saas_features(dependency_firewall: false)
      stub_licensed_features(
        dependency_firewall: false,
        security_orchestration_policies: security_orchestration_policies
      )
    end
  end
end
