# frozen_string_literal: true

module Security
  module SecurityOrchestrationPolicies
    module PolicyStore
      class BaseService
        # The container is the authorization subject: an Organization manages every
        # policy of the organization, while a Group manages only the policies
        # stamped with its namespace, so a group Owner never reads or edits
        # organization-wide policies or another group's through this seam.
        def initialize(container:, current_user:, params: {})
          @container = container
          @current_user = current_user
          @params = params.to_h.symbolize_keys
        end

        private

        attr_reader :container, :current_user, :params

        def organization
          container.is_a?(::Group) ? container.organization : container
        end

        def namespace_id
          container.is_a?(::Group) ? container.id : nil
        end

        def experiment_active?
          container.policy_store_experiment_active?
        end

        def authorized?(ability)
          Ability.allowed?(current_user, ability, container)
        end

        # A group container returns the same not-found for a policy outside its
        # namespace as for a missing id, so probing ids leaks nothing.
        def find_policy(policy_id)
          policy = ::Gitlab::PolicyStore.find(policy_id)

          return unless policy.organization_id == organization.id
          return if namespace_id && policy.namespace_id != namespace_id

          policy
        rescue ::Gitlab::PolicyStore::NotFound
          nil
        end

        def experiment_not_active_error
          ServiceResponse.error(
            message: experiment_not_active_message,
            reason: :experiment_not_active
          )
        end

        def experiment_not_active_message
          if container.is_a?(::Group)
            s_('GovernPolicies|Policy Store experiment is not active for this group')
          else
            s_('GovernPolicies|Policy Store experiment is not active for this organization')
          end
        end

        def forbidden_error
          ServiceResponse.error(
            message: forbidden_message,
            reason: :forbidden
          )
        end

        def forbidden_message
          if container.is_a?(::Group)
            s_('GovernPolicies|You are not authorized to perform this action on policies in this group')
          else
            s_('GovernPolicies|You are not authorized to perform this action on policies in this organization')
          end
        end

        def policy_not_found_error
          ServiceResponse.error(
            message: s_('GovernPolicies|Policy was not found'),
            reason: :not_found
          )
        end

        def engine_error(error, **context)
          ::Gitlab::ErrorTracking.track_exception(error, organization_id: organization.id, **context)

          ServiceResponse.error(message: error.message, reason: :engine_error)
        end

        def conflicting_scope?
          params[:policy_scope].present? && params[:scope_rego].present?
        end

        def conflicting_scope_error
          ServiceResponse.error(
            message: s_('GovernPolicies|Only one of policy_scope or scope_rego can be provided'),
            reason: :invalid
          )
        end
      end
    end
  end
end
