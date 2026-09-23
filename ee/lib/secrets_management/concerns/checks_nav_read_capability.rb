# frozen_string_literal: true

module SecretsManagement
  module Concerns
    # Sidebar counterpart of the secrets controllers' `check_read_capability!`, which
    # 404s users without an OpenBao read grant once the secrets manager is active.
    module ChecksNavReadCapability
      extend ActiveSupport::Concern

      # The lookup runs on every page render (the service caches it for its CACHE_TTL); this budget
      # makes a slow OpenBao hide the item instead of stalling the render.
      CAPABILITIES_HTTP_TIMEOUT = 3

      private

      def user_can_read_secrets_metadata?(service_class, secrets_manager:, resource:)
        service_class.new(
          secrets_manager: secrets_manager,
          current_user: context.current_user,
          resource: resource,
          http_timeout: CAPABILITIES_HTTP_TIMEOUT
        ).execute['read_metadata']
      end
    end
  end
end
