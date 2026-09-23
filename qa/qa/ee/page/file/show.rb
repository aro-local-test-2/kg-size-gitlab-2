# frozen_string_literal: true

module QA
  module EE
    module Page
      module File
        module Show
          extend QA::Page::PageConcern

          def self.prepended(base)
            super

            base.class_eval do
              include QA::Page::Component::ConfirmModal

              # These two lock button elements are used for locking at directory level
              view 'ee/app/assets/javascripts/repository/components/lock_directory_button.vue' do
                element 'lock-button'
                element 'disabled-lock-button'
              end

              # Lock UI behind the repository_lock_information feature flag.
              # Remove the lock_directory_button.vue view above when the flag is removed.
              view 'ee/app/assets/javascripts/repository/components/header_area/lock_button.vue' do
                element 'lock-button'
                element 'lock-disclosure-toggle'
                element 'unlock-button'
              end

              view 'app/assets/javascripts/repository/components/header_area/blob_overflow_menu.vue' do
                element 'blob-overflow-menu'
              end

              view 'ee/app/assets/javascripts/vue_shared/components/code_owners/code_owners.vue' do
                element 'collapse-toggle'
              end
            end
          end

          def lock
            click_element('lock-button')
            click_confirmation_ok_button

            # With repository_lock_information enabled, a locked path shows a
            # "Locked" disclosure instead of an "Unlock" button
            wait_until(reload: false, message: 'Waiting for a locked control') do
              has_element?('lock-disclosure-toggle', wait: 1) || has_element?('lock-button', text: 'Unlock', wait: 1)
            end
          end

          # Files are locked from a header Lock button with
          # repository_lock_information enabled, or from the blob overflow menu
          # without it
          def lock_file
            if has_element?('lock-button', wait: 10)
              lock
            else
              # Raw find because the menu items are gitlab-ui elements without testids
              find('[data-testid="blob-overflow-menu"] > button').click
              click_button('Lock')
              click_confirmation_ok_button
            end
          end

          def unlock
            wait_until(reload: false, message: 'Waiting for an unlock control') do
              has_element?('lock-disclosure-toggle', wait: 1) || has_element?('lock-button', text: 'Unlock', wait: 1)
            end

            if has_element?('lock-disclosure-toggle', wait: 1)
              click_element('lock-disclosure-toggle')
              click_element('unlock-button')
            else
              click_element('lock-button')
            end

            click_confirmation_ok_button

            unless has_element?('lock-button', text: 'Lock')
              raise QA::Page::Base::ElementNotFound, %q(Button did not show expected state)
            end
          end

          def has_lock_button_disabled?
            has_element?('disabled-lock-button')
          end

          def has_code_owners_container?
            has_element?('codeowners-container')
          end

          def reveal_code_owners
            if has_element?('collapse-toggle', text: 'Show all')
              scroll_to_element('collapse-toggle', text: 'Show all')
              click_element('collapse-toggle', text: 'Show all')
            end
          end
        end
      end
    end
  end
end
