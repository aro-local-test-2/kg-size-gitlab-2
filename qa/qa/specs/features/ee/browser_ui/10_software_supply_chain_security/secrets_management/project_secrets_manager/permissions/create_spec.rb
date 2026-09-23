# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    include_context 'secrets manager base'
    describe 'Create on project secret permissions' do
      context 'when owner creates permission for non-project user' do
        let!(:non_project_user) { create(:user) }

        it 'fails to create the secret permission' do
          Flow::Login.while_signed_in(as: owner) do
            project.visit!

            Page::Project::Menu.perform(&:go_to_general_settings)
            Page::Project::Settings::Main.perform do |settings|
              settings.expand_visibility_project_features_permissions do |permissions_page|
                expect(permissions_page).not_to have_user_in_dropdown(username: non_project_user.username)
              end
            end
          end
        end
      end

      context 'when owner creates permission for developer-role without read permission' do
        it 'fails to create the secret permission' do
          Flow::Login.while_signed_in(as: owner) do
            project.visit!

            Page::Project::Menu.perform(&:go_to_general_settings)
            Page::Project::Settings::Main.perform do |settings|
              settings.expand_visibility_project_features_permissions do |permissions_page|
                scopes = %w[write delete]
                permissions_page.add_role_permission(role_name: 'Developer', scopes: scopes)
                expect(permissions_page.alert_text).to eq('Actions must include read, read_metadata, or read_value')
              end
            end
          end
        end
      end
    end
  end
end
