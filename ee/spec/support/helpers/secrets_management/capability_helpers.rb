# frozen_string_literal: true

module SecretsManagement
  module CapabilityHelpers
    # Stubs the live OpenBao capabilities lookup for both the group and project service,
    # granting or withholding `read_metadata` for specs that render capability-gated UI.
    def stub_secrets_manager_read_capability(read: true)
      [
        UserPermissions::GroupEffectiveCapabilitiesService,
        UserPermissions::ProjectEffectiveCapabilitiesService
      ].each do |service_class|
        allow_next_instance_of(service_class) do |service|
          allow(service).to receive(:execute).and_return(
            { 'read_metadata' => read, 'create' => false, 'update' => false, 'delete' => false }
          )
        end
      end
    end
  end
end
