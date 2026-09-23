# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management,
    feature_flag: { name: 'secrets_manager_api_access', scope: :global }
  ) do
    include_context 'group secrets manager base'

    describe 'Group Secret API Access' do
      let(:secret_name) { 'api_access_secret' }
      let(:secret_value) { 'my-secret-value-for-api' }
      let(:reader) { create(:user) }
      let(:reader_token) { reader.create_personal_access_token!.token }
      let(:scopes) { %w[read read_value] }

      before do
        group.add_member(reader, Resource::Members::AccessLevel::DEVELOPER)
        grant_permission_and_add_secret
      end

      context 'when a client reads a group secret from OpenBao' do
        it 'returns the secret value for a minted access token' do
          vault = mint_secrets_manager_access_token(group, token: reader_token)
          openbao_token = log_in_to_openbao(vault)

          expect(read_openbao_secret_value(vault, secret_name, token: openbao_token)).to eq(secret_value)
        end
      end

      private

      # Owners cannot be granted secrets permissions, so the reader is a separate member.
      # `read` comes along with `read_value` because the UI keeps the read value checkbox
      # disabled until read is checked.
      #
      # Both steps share one signed-in session so the spec pays for a single login.
      def grant_permission_and_add_secret
        Flow::Login.while_signed_in(as: owner) do
          group.visit!

          Page::Group::Menu.perform(&:go_to_general_settings)
          Page::Group::Settings::General.perform do |settings|
            settings.add_user_permission(username: reader.username, scopes: scopes)

            unless settings.has_user_permission?(username: reader.username, scopes: scopes)
              raise "Failed to grant #{scopes.join(', ')} to #{reader.username}"
            end
          end

          Page::Group::Menu.perform(&:go_to_secrets_manager)
          EE::Page::Group::Secure::SecretsManager.perform do |secrets_page|
            secrets_page.click_new_secret
            secrets_page.create_secret(
              name: secret_name,
              value: secret_value,
              description: 'Group secret for non-CI API access test',
              environment: '*'
            )

            # Confirm the secret is stored before reading it back from OpenBao, so a slow
            # or failed save shows up here instead of as a confusing read failure later.
            raise "Secret #{secret_name} was not created" unless secrets_page.has_secret_in_table?(secret_name)
          end
        end
      end
    end
  end
end
