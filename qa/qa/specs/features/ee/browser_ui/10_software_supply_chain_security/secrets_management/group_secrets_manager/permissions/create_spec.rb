# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    include_context 'group secrets manager base'
    describe 'Create on group secret permissions' do
      context 'when owner creates permission for non-group user' do
        let!(:non_group_user) { create(:user) }

        it 'fails to create the secret permission' do
          Flow::Login.while_signed_in(as: owner) do
            group.visit!

            Page::Group::Menu.perform(&:go_to_general_settings)
            Page::Group::Settings::General.perform do |settings|
              expect(settings).not_to have_user_in_dropdown(username: non_group_user.username)
            end
          end
        end
      end

      context 'when owner creates permission for developer-role without read permission' do
        it 'fails to create the secret permission' do
          Flow::Login.while_signed_in(as: owner) do
            group.visit!

            Page::Group::Menu.perform(&:go_to_general_settings)
            Page::Group::Settings::General.perform do |settings|
              scopes = %w[write delete]
              settings.add_role_permission(role_name: 'Developer', scopes: scopes)
              expect(settings.alert_text).to eq('Actions must include read, read_metadata, or read_value')
            end
          end
        end
      end
    end
  end
end
