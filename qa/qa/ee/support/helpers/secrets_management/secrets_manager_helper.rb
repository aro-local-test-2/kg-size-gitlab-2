# frozen_string_literal: true

module QA
  module EE
    module Support
      module Helpers
        module SecretsManagement
          module SecretsManagerHelper
            PAID_ENTITLEMENT_STATES = %w[OFFLINE_PAID PAID TRIAL].freeze
            UNAUTHORIZED_MESSAGE = "you don't have permission"

            # Deprovisions a secrets manager for a project or group via GraphQL
            #
            # @param resource [QA::Resource::Project, QA::Resource::Group] The resource to deprovision
            # @return [Hash] The GraphQL response
            def deprovision_secrets_manager(resource)
              if resource.is_a?(QA::Resource::Group)
                mutation = <<~GRAPHQL
                  mutation {
                    groupSecretsManagerDeprovision(input: { groupPath: "#{resource.full_path}" }) {
                      groupSecretsManager {
                        status
                      }
                      errors
                    }
                  }
                GRAPHQL
                mutation_key = :groupSecretsManagerDeprovision
              else
                mutation = <<~GRAPHQL
                  mutation {
                    projectSecretsManagerDeprovision(input: { projectPath: "#{resource.full_path}" }) {
                      projectSecretsManager {
                        status
                        project {
                          id
                          fullPath
                        }
                      }
                      errors
                    }
                  }
                GRAPHQL
                mutation_key = :projectSecretsManagerDeprovision
              end

              parsed_response = post_secrets_manager_graphql(
                mutation,
                token: QA::Runtime::User::Store.default_api_client.personal_access_token
              )
              mutation_response = parsed_response.dig(:data, mutation_key)

              QA::Runtime::Logger.info("Successfully initiated deprovisioning for: #{resource.full_path}")

              mutation_response
            end

            # Enrolls the GitLab instance in Secrets Manager via GraphQL.
            # Required on self-managed (GDK) since SM availability gates on
            # `Availability.enabled_for_*?` which checks (FF AND enrollment).
            #
            # Raises if enrollment fails for a reason other than "already enrolled"
            # so callers don't silently proceed with an unenrolled instance.
            #
            # @return [Hash] The GraphQL mutation response
            def enroll_instance_in_secrets_manager
              mutation = <<~GRAPHQL
                mutation {
                  instanceSecretsManagerEnroll(input: {}) {
                    errors
                  }
                }
              GRAPHQL

              parsed_response = post_secrets_manager_graphql(
                mutation,
                token: QA::Runtime::User::Store.admin_api_client.personal_access_token
              )
              errors = graphql_errors(parsed_response, :instanceSecretsManagerEnroll)

              unless errors.empty? || errors == ['Instance is already enrolled.']
                raise "Failed to enroll instance in Secrets Manager: #{errors.join(', ')}"
              end

              QA::Runtime::Logger.info("Instance is enrolled in Secrets Manager")
              provision_license_add_ons

              parsed_response.dig(:data, :instanceSecretsManagerEnroll)
            end

            # On CNG the license arrives through GITLAB_LICENSE_FILE, which never runs the
            # self-managed add-on provisioners. Re-adding it through the API and deleting the
            # superseded copy runs Licenses::DestroyService, which does. See the MR description.
            def provision_license_add_ons
              license = QA::Runtime::Env.ee_license
              return if license.to_s.strip.empty?
              return if SecretsManagerHelper.license_add_ons_provisioned
              # Every example enrolls, so a failed attempt fails once and fast instead of
              # re-adding the license and waiting again for each example.
              raise SecretsManagerHelper.license_add_ons_error if SecretsManagerHelper.license_add_ons_error

              provision_license_add_ons!(license)
            rescue StandardError => e
              SecretsManagerHelper.license_add_ons_error = e
              raise
            end

            def provision_license_add_ons!(license)
              # Another QA process may have done this already.
              return SecretsManagerHelper.license_add_ons_provisioned = true if paid_instance_entitlement?

              client = QA::Runtime::API::Client.as_admin
              # rubocop:disable Rails/Pluck -- plain Array of Hashes, not AR
              superseded_ids = QA::EE::Resource::License.all(client).map { |license_data| license_data[:id] }
              # rubocop:enable Rails/Pluck

              response = QA::Support::API.post(
                QA::Runtime::API::Request.new(client, "/license").url,
                { license: license.strip }
              )

              unless response.code == QA::Support::API::HTTP_STATUS_CREATED
                raise "Failed to add a copy of the license (#{response.code})"
              end

              QA::Runtime::Logger.info("Removing superseded licenses #{superseded_ids.inspect} for the new copy")
              superseded_ids.each do |id|
                delete_response = QA::Support::API.delete(QA::Runtime::API::Request.new(client, "/license/#{id}").url)
                # Another QA process may have removed it already.
                if [QA::Support::API::HTTP_STATUS_NO_CONTENT, QA::Support::API::HTTP_STATUS_NOT_FOUND].include?(delete_response.code)
                  next
                end

                raise "Failed to remove superseded license #{id} (#{delete_response.code})"
              end

              wait_for_paid_instance_entitlement

              SecretsManagerHelper.license_add_ons_provisioned = true
              QA::Runtime::Logger.info("Provisioned the license add-on purchases")
            end

            # DELETE /license/:id hides the DestroyService result and GET /license does not
            # expose add_on_products, so ask the entitlement itself. It is request-scoped,
            # so polling cannot pin a stale answer.
            def wait_for_paid_instance_entitlement
              entitlement = nil
              paid = QA::Support::Waiter.wait_until(max_duration: 60, sleep_interval: 3, raise_on_failure: false) do
                entitlement = instance_entitlement
                paid_entitlement?(entitlement)
              end
              return if paid

              raise "The instance entitlement is still #{entitlement.inspect} after re-adding the license. " \
                "The license most likely has no secrets_manager add-on. " \
                "Check that QA_EE_LICENSE carries the add-on."
            end

            def paid_instance_entitlement?
              paid_entitlement?(instance_entitlement)
            end

            def paid_entitlement?(entitlement)
              PAID_ENTITLEMENT_STATES.include?(entitlement&.fetch(:state, nil))
            end

            def instance_entitlement
              query = <<~GRAPHQL
                query {
                  secretsManagerInstanceEntitlement {
                    state
                    blockedReason
                  }
                }
              GRAPHQL

              parsed_response = post_secrets_manager_graphql(
                query,
                token: QA::Runtime::User::Store.admin_api_client.personal_access_token
              )
              entitlement = parsed_response.dig(:data, :secretsManagerInstanceEntitlement)&.slice(:state,
                :blockedReason)
              QA::Runtime::Logger.info("Instance entitlement: #{entitlement.inspect}")

              entitlement
            end

            class << self
              attr_accessor :license_add_ons_provisioned, :license_add_ons_error
            end

            # Provisions a secrets manager for a project or group via GraphQL and
            # waits until OpenBao reports it as ACTIVE. Provisioning runs in a
            # Sidekiq worker, so the mutation alone only starts it.
            #
            # @param resource [QA::Resource::Project, QA::Resource::Group] The resource to provision
            # @param token [String] Access token of a user who can provision (defaults to the admin token)
            # @return [Hash] The GraphQL mutation response
            def provision_secrets_manager(resource, token: QA::Runtime::User::Store.admin_api_client.personal_access_token)
              if resource.is_a?(QA::Resource::Group)
                mutation = <<~GRAPHQL
                  mutation {
                    groupSecretsManagerInitialize(input: { groupPath: "#{resource.full_path}" }) {
                      groupSecretsManager {
                        status
                      }
                      errors
                    }
                  }
                GRAPHQL
                mutation_key = :groupSecretsManagerInitialize
              else
                mutation = <<~GRAPHQL
                  mutation {
                    projectSecretsManagerInitialize(input: { projectPath: "#{resource.full_path}" }) {
                      projectSecretsManager {
                        status
                      }
                      errors
                    }
                  }
                GRAPHQL
                mutation_key = :projectSecretsManagerInitialize
              end

              # Project authorizations refresh asynchronously after a member is added, so a
              # fresh Owner can be denied for a moment. Retry only that error.
              parsed_response = nil
              QA::Support::Waiter.wait_until(max_duration: 30, sleep_interval: 2, raise_on_failure: false) do
                parsed_response = post_secrets_manager_graphql(mutation, token: token)
                graphql_errors(parsed_response, mutation_key).none? { |error| error.include?(UNAUTHORIZED_MESSAGE) }
              end
              errors = graphql_errors(parsed_response, mutation_key)

              raise "Failed to provision Secrets Manager for #{resource.full_path}: #{errors.join(', ')}" if errors.any?

              wait_for_secrets_manager_status(resource, 'ACTIVE')

              QA::Runtime::Logger.info("Provisioned Secrets Manager for: #{resource.full_path}")

              parsed_response.dig(:data, mutation_key)
            end

            # Current secrets manager status for a project or group, or nil when
            # no secrets manager record exists (never provisioned, or deprovisioned).
            #
            # @param resource [QA::Resource::Project, QA::Resource::Group]
            # @return [String, nil] One of the *SecretsManagerStatus enum values
            def secrets_manager_status(resource)
              if resource.is_a?(QA::Resource::Group)
                query = <<~GRAPHQL
                  query {
                    groupSecretsManager(groupPath: "#{resource.full_path}") {
                      status
                    }
                  }
                GRAPHQL
                query_key = :groupSecretsManager
              else
                query = <<~GRAPHQL
                  query {
                    projectSecretsManager(projectPath: "#{resource.full_path}") {
                      status
                    }
                  }
                GRAPHQL
                query_key = :projectSecretsManager
              end

              parsed_response = post_secrets_manager_graphql(
                query,
                token: QA::Runtime::User::Store.admin_api_client.personal_access_token
              )

              parsed_response.dig(:data, query_key, :status)
            end

            # Waits for the secrets manager to reach a status. Pass nil to wait for
            # the record to disappear after deprovisioning.
            #
            # @param resource [QA::Resource::Project, QA::Resource::Group]
            # @param status [String, nil] Expected status, or nil for "no secrets manager"
            def wait_for_secrets_manager_status(resource, status, max_duration: 120)
              message = "Timed out waiting for Secrets Manager status #{status.inspect} on #{resource.full_path}"

              QA::Support::Waiter.wait_until(max_duration: max_duration, sleep_interval: 2, message: message) do
                secrets_manager_status(resource) == status
              end
            end

            # Mints a short-lived JWT and the OpenBao connection details for
            # non-CI access, the same way an external client does.
            # See doc/ci/secrets/secrets_manager/non_cicd_access.md.
            #
            # @param resource [QA::Resource::Project, QA::Resource::Group] The resource owning the secrets
            # @param token [String] Access token with the api scope
            # @return [Hash] The vault connection details from the mint response
            def mint_secrets_manager_access_token(resource, token:)
              scope = resource.is_a?(QA::Resource::Group) ? 'groups' : 'projects'
              path = "/api/v4/#{scope}/#{resource.id}/secrets_manager/access_token"

              response = QA::Support::API.post(
                "#{QA::Runtime::Scenario.gitlab_address}#{path}",
                {},
                headers: { 'PRIVATE-TOKEN' => token }
              )

              unless response.code == QA::Support::API::HTTP_STATUS_CREATED
                raise "Failed to mint an access token for #{resource.full_path} (#{response.code})"
              end

              QA::Support::API.parse_body(response).fetch(:provider).fetch(:vault)
            end

            # Exchanges a minted JWT for an OpenBao token.
            #
            # @param vault [Hash] The vault connection details from the mint response
            # @return [String] The OpenBao client token
            def log_in_to_openbao(vault)
              jwt = vault.fetch(:auth).fetch(:jwt)

              response = QA::Support::API.post(
                "#{vault.fetch(:server)}/v1/auth/#{jwt.fetch(:path)}/login",
                { role: jwt.fetch(:role), jwt: jwt.fetch(:token) }.to_json,
                headers: openbao_headers(vault).merge('Content-Type' => 'application/json')
              )

              unless response.code == QA::Support::API::HTTP_STATUS_OK
                raise "Failed to log in to #{vault.fetch(:server)} (#{response.code})"
              end

              QA::Support::API.parse_body(response).dig(:auth, :client_token)
            end

            # Reads a secret value straight from OpenBao.
            #
            # @param vault [Hash] The vault connection details from the mint response
            # @param secret_name [String] Name of the secret to read
            # @param token [String] The OpenBao client token
            # @return [String] The secret value
            def read_openbao_secret_value(vault, secret_name, token:)
              path = "#{vault.fetch(:path)}/data/#{vault.fetch(:secrets_path)}/#{secret_name}"

              response = QA::Support::API.get(
                "#{vault.fetch(:server)}/v1/#{path}",
                headers: openbao_headers(vault).merge('X-Vault-Token' => token)
              )

              unless response.code == QA::Support::API::HTTP_STATUS_OK
                raise "Failed to read #{secret_name} from OpenBao (#{response.code})"
              end

              QA::Support::API.parse_body(response).dig(:data, :data, :value)
            end

            private

            def openbao_headers(vault)
              { 'X-Vault-Namespace' => vault.fetch(:namespace) }
            end

            def post_secrets_manager_graphql(query, token:)
              response = QA::Support::API.post(
                "#{QA::Runtime::Scenario.gitlab_address}/api/graphql",
                { query: query },
                headers: { Authorization: "Bearer #{token}" }
              )

              JSON.parse(response.body, symbolize_names: true)
            end

            # GraphQL surfaces auth/transport errors at the top level and
            # mutation-level errors inside the payload, so check both.
            def graphql_errors(parsed_response, mutation_key)
              # rubocop:disable Rails/Pluck -- parsed_response[:errors] is a plain Ruby Array, not AR
              top_level_errors = (parsed_response[:errors] || []).map { |error| error[:message] }
              # rubocop:enable Rails/Pluck

              top_level_errors + (parsed_response.dig(:data, mutation_key, :errors) || [])
            end
          end
        end
      end
    end
  end
end
