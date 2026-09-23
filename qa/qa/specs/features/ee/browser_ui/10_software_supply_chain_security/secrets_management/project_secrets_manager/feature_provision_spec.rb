# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    describe 'Project Secrets Manager Feature Provision' do
      include QA::EE::Support::Helpers::SecretsManagement::SecretsManagerHelper # rubocop: disable Cop/InjectEnterpriseEditionModule -- Helpers are added this way
      let(:owner) { create(:user) }
      let(:project) { create(:project, :with_readme, name: 'secrets-manager-test-project') }

      before do
        # SM availability requires instance enrollment on self-managed.
        enroll_instance_in_secrets_manager

        project.add_member(owner, Resource::Members::AccessLevel::OWNER)

        Support::Waiter.wait_until(max_duration: 10, sleep_interval: 1) do
          project.reload!
          project.find_member(owner.username).present?
        end
      end

      it 'shows Owner permissions in project settings once provisioned and hides them after deprovisioning' do
        owner_msg = 'Expected Owner role to have Read metadata, Write, Delete in the Roles tab'

        provision_secrets_manager(project, token: owner.create_personal_access_token!.token)

        Flow::Login.while_signed_in(as: owner) do
          project.visit!
          Support::WaitForRequests.wait_for_requests

          Page::Project::Menu.perform(&:go_to_general_settings)

          Page::Project::Settings::Main.perform do |settings|
            settings.expand_visibility_project_features_permissions do |permissions|
              expect(permissions).to have_secrets_manager_section
              expect(permissions).to have_secrets_manager_permissions_section

              permissions.click_roles_tab

              expect { permissions.has_owner_permissions? }
                .to eventually_be_truthy
                .within(max_duration: 30, sleep_interval: 1, message: owner_msg)
            end
          end

          deprovision_secrets_manager(project)
          wait_for_secrets_manager_status(project, nil)

          project.visit!
          Page::Project::Menu.perform(&:go_to_general_settings)

          Page::Project::Settings::Main.perform do |settings|
            settings.expand_visibility_project_features_permissions do |permissions|
              expect(permissions).to have_no_secrets_manager_permissions_section
            end
          end
        end
      end
    end
  end
end
