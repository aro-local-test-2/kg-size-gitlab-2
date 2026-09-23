# frozen_string_literal: true

module QA
  module EE
    module Page
      module Component
        module SecretsManagerSettings
          extend QA::Page::PageConcern

          def self.included(base)
            super
            register_views(base)
          end

          def self.register_views(base)
            base.class_eval do
              view 'ee/app/assets/javascripts/pages/projects/shared/permissions/' \
                'secrets_manager/secrets_manager_settings.vue' do
                element 'secret-manager'
              end

              view 'ee/app/assets/javascripts/pages/projects/shared/permissions/' \
                'secrets_manager/components/secrets_manager_permissions_table.vue' do
                element 'secrets-manager-roles-tab'
                element 'secrets-manager-roles-content'
              end
            end
          end

          def has_secrets_manager_section?
            has_element?('secret-manager')
          end

          def has_secrets_manager_permissions_section?
            has_text?('User permissions')
          end

          def has_no_secrets_manager_permissions_section?
            has_no_text?('User permissions')
          end

          def click_roles_tab
            find_element('secrets-manager-roles-tab').click
          end

          def has_owner_permissions?
            within_element('secrets-manager-roles-content') do
              find('tr', text: 'Owner').has_text?('Read metadata, Write, Delete')
            rescue Capybara::ElementNotFound
              false
            end
          end
        end
      end
    end
  end
end
