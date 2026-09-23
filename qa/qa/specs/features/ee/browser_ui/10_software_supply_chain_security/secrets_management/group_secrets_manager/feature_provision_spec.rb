# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    describe 'Group Secrets Manager Feature Provision' do
      include QA::EE::Support::Helpers::SecretsManagement::SecretsManagerHelper # rubocop: disable Cop/InjectEnterpriseEditionModule -- Helpers are added this way

      let(:owner) { create(:user) }
      let(:group) { create(:group) }

      before do
        # SM availability requires instance enrollment on self-managed.
        enroll_instance_in_secrets_manager
      end

      it 'shows Owner permissions in group settings once provisioned and hides them after deprovisioning' do
        owner_msg = 'Expected Owner role to have Read metadata, Write, Delete in the Roles tab'

        group.add_member(owner, Resource::Members::AccessLevel::OWNER)

        Support::Waiter.wait_until(max_duration: 30, sleep_interval: 1) do
          group.reload!
          group.find_member(owner.username).present?
        end

        provision_secrets_manager(group, token: owner.create_personal_access_token!.token)

        Flow::Login.while_signed_in(as: owner) do
          group.visit!
          Page::Group::Menu.perform(&:go_to_general_settings)

          Page::Group::Settings::General.perform do |settings|
            expect(settings).to have_secrets_manager_section
            expect(settings).to have_secrets_manager_permissions_section

            settings.click_roles_tab

            expect { settings.has_owner_permissions? }
              .to eventually_be_truthy
              .within(max_duration: 30, sleep_interval: 1, message: owner_msg)
          end

          deprovision_secrets_manager(group)
          wait_for_secrets_manager_status(group, nil)

          group.visit!
          Page::Group::Menu.perform(&:go_to_general_settings)

          Page::Group::Settings::General.perform do |settings|
            expect(settings).to have_no_secrets_manager_permissions_section
          end
        end
      end
    end
  end
end
