# frozen_string_literal: true

RSpec.shared_context 'with dependency firewall enforced without security_orchestration_policies licence' do
  before do
    stub_saas_features(dependency_firewall: true)
    stub_licensed_features(security_orchestration_policies: false, dependency_firewall: true)
    root_group.namespace_settings.update!(dependency_firewall_enabled: true)
  end
end
