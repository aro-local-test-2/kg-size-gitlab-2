# frozen_string_literal: true

module EE
  module Organizations
    module OrganizationUsers
      module DestroyService
        extend ::Gitlab::Utils::Override

        override :execute
        def execute
          owner_removed = organization_user.owner?

          result = super

          revoke_organization_admin_role if owner_removed && result.success?

          result
        end

        private

        def revoke_organization_admin_role
          return unless ::Authn::IamDataAccessService.configured?

          ::Authz::Organizations::RevokeOwnerRoleWorker.perform_async(
            organization_user.organization_id, organization_user.user_id, current_user.id)
        end
      end
    end
  end
end
