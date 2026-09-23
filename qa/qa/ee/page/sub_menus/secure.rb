# frozen_string_literal: true

module QA
  module EE
    module Page
      module SubMenus
        module Secure
          def go_to_security_dashboard
            open_secure_submenu('Security dashboard')
          end

          def go_to_vulnerability_report
            open_secure_submenu('Vulnerability report')

            # wait_for_requests guards against reading current_url before the report page has loaded.
            wait_for_requests

            # Force the report onto PostgreSQL by clearing the tracked-ref filter (trackedRefIds=ALL).
            # Elasticsearch, used when a ref is filtered, is slow in some environments.
            # Done through the URL because the token isn't rendered until the default branch context loads.
            # TODO: Remove this workaround once https://gitlab.com/gitlab-org/gitlab/-/merge_requests/251159 gets merged
            visit("#{page.current_url.split('?').first}?trackedRefIds=ALL")
          end

          def go_to_dependency_list
            open_secure_submenu('Dependency list')
          end

          def go_to_policies
            open_secure_submenu('Policies')
          end

          def go_to_audit_events
            open_secure_submenu("Audit events")
          end

          def go_to_security_configuration
            open_secure_submenu('Security configuration')
          end

          private

          def open_secure_submenu(sub_menu)
            open_submenu('Secure', sub_menu)
          end
        end
      end
    end
  end
end
