# frozen_string_literal: true

module QA
  module EE
    module Page
      module Component
        module SecretsManagerPermissions
          extend QA::Page::PageConcern

          PERMISSION_SCOPE_LABELS = {
            'read' => 'Read metadata',
            'read_metadata' => 'Read metadata',
            'read_value' => 'Read value',
            'write' => 'Write',
            'delete' => 'Delete'
          }.freeze

          def add_user_permission(username:, scopes:)
            add_permission(name: username, scopes: scopes, type: 'USER')
          end

          def has_user_permission?(username:, scopes:)
            has_permission?(name: username, scopes: scopes, tab: 'Users')
          end

          def delete_user_permission(username:)
            delete_permission(name: username, tab: 'Users')
          end

          def add_role_permission(role_name:, scopes:)
            add_permission(name: role_name.upcase, scopes: scopes, type: 'ROLE')
          end

          def has_role_permission?(role_name:, scopes:)
            has_permission?(name: role_name, scopes: scopes, tab: 'Roles')
          end

          def delete_role_permission(role_name:)
            delete_permission(name: role_name, tab: 'Roles')
          end

          def has_user_in_dropdown?(username:)
            within_element('crud-actions') do
              click_button('Add')
            end
            execute_script("document.querySelector('[data-testid=\"listbox-item-USER\"]').click()")
            wait_for_requests
            execute_script("document.querySelector('#secret-permission-principal button').click()")
            escaped_username = username.to_s.gsub('\\', '\\\\').gsub("'", "\\'")
            result = has_css?("[data-testid='listbox-item-#{escaped_username}']", wait: 2)
            execute_script("document.querySelector('[aria-label=\"Close\"]').click()")
            result
          end

          def has_add_permission_button?
            has_button?('Add')
          end

          def alert_text
            find('.js-secrets-manager-permissions-alert-container', wait: 5).text
          end

          private

          def select_principal(name:)
            execute_script("document.querySelector('#secret-permission-principal button').click()")
            wait_for_requests
            escaped_name = name.to_s.gsub('\\', '\\\\').gsub("'", "\\'")
            execute_script("document.querySelector(\"[data-testid='listbox-item-#{escaped_name}']\").click()")

            wait_for_requests
          end

          def set_permission_scopes(scopes)
            # Temporarily enable Read so Write/Delete become interactive, then restore intended state.
            check_permission('read') unless scopes.include?('read')
            scopes.each { |scope| check_permission(scope) }
            uncheck_permission('read') unless scopes.include?('read')
          end

          def check_permission(scope_name)
            set_permission(scope_name, checked: true)
          end

          def uncheck_permission(scope_name)
            set_permission(scope_name, checked: false)
          end

          # Scope names do not match their checkbox labels, so they are mapped rather than
          # derived. `read` is labelled "Read metadata", and deriving the label from the
          # scope name silently produced "Read_value" for `read_value`, which matched nothing.
          def set_permission(scope_name, checked:)
            label_text = PERMISSION_SCOPE_LABELS.fetch(scope_name.to_s) do
              raise ArgumentError, "Unknown permission scope: #{scope_name}"
            end

            # The modal renders outside the settings section this component is scoped to,
            # so these lookups go through the document instead of the current scope.
            label = page.document.find('label[class*="custom-control-label"]', text: label_text)
            state = "##{label[:for]}#{checked ? ':checked' : ':not(:checked)'}"

            label.click unless page.document.has_css?(state, visible: :all, wait: 0)
            return if page.document.has_css?(state, visible: :all, wait: 5)

            raise "Could not set the '#{label_text}' permission to checked=#{checked}. " \
              "Every scope other than Read metadata stays disabled until Read metadata is checked."
          end

          def click_save_button
            execute_script("document.querySelector('.js-modal-action-primary').click()")
          end

          def add_permission(name:, scopes:, type:)
            within_element('crud-actions') { click_button('Add') }
            click_element("listbox-item-#{type}")
            select_principal(name: name)
            set_permission_scopes(scopes)
            click_save_button
            wait_for_requests
          end

          def has_permission?(name:, scopes:, tab: nil)
            find('[role="tab"]', text: tab).click if tab.present?
            begin
              row = find('tr', text: name)
            rescue StandardError
              return false
            end

            # Mirrors the table's own formatting, which renders `read_value` as "Read value".
            scopes.each do |scope|
              return false unless row.has_text?(scope.to_s.tr('_', ' ').capitalize)
            end

            true
          end

          def delete_permission(name:, tab: nil)
            find('[role="tab"]', text: tab).click if tab.present?
            row = find('tr', text: name)
            within(row) do
              delete_button = find('[data-testid="remove-icon"]', wait: 2).ancestor('button')
              delete_button.click
              execute_script("document.querySelector('.js-modal-action-primary').click()")
            end
            wait_for_requests
          end
        end
      end
    end
  end
end
