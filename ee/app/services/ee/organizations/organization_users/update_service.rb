# frozen_string_literal: true

module EE
  module Organizations
    module OrganizationUsers
      module UpdateService
        extend ::Gitlab::Utils::Override

        override :execute
        def execute
          result = super

          sync_organization_admin_role if result.success?

          result
        end

        private

        # access_level currently has exactly two values (default/owner), so any
        # saved change is necessarily a transition across the owner boundary.
        # Revisit this if a third access_level is ever introduced.
        def sync_organization_admin_role
          return unless organization_user.saved_change_to_access_level?
          return unless ::Authn::IamDataAccessService.configured?

          worker = if organization_user.owner?
                     ::Authz::Organizations::GrantOwnerRoleWorker
                   else
                     ::Authz::Organizations::RevokeOwnerRoleWorker
                   end

          worker.perform_async(organization_user.organization_id, organization_user.user_id, current_user.id)
        end
      end
    end
  end
end
