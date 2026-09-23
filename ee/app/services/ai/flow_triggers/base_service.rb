# frozen_string_literal: true

module Ai
  module FlowTriggers
    # Applies shared validation, authorization, compatibility, and audit behavior to flow-trigger mutations.
    #
    # User-driven services continue to require +:manage_ai_flow_triggers+. A create service may carry a
    # typed inherited-project authorization that bypasses only that actor-role check for the exact computed
    # foundational-flow consumer. Model validation, service-account alignment, and composite-identity
    # enforcement remain unchanged.
    class BaseService
      attr_reader :project, :current_user, :authorization_context

      ERROR_REASON_UNAUTHORIZED = :unauthorized
      ERROR_REASON_SERVICE_ACCOUNT_MISMATCH = :service_account_mismatch
      ERROR_REASON_INVALID_TRIGGER = :validation_error

      def execute(params)
        params = params.dup
        authorization_params = params.dup

        service_account = service_account(params[:user_id])
        ai_catalog_item_consumer = ai_catalog_item_consumer(params[:ai_catalog_item_consumer_id])

        params[:user_id] = nil if ai_catalog_item_consumer.present?

        unless user_is_authorized_to_service_account?(service_account, ai_catalog_item_consumer, authorization_params)
          return ServiceResponse.error(
            message: 'You are not authorized to use this service account in this project',
            reason: ERROR_REASON_UNAUTHORIZED
          )
        end

        unless service_account_compatible_with_item_consumer?(service_account, ai_catalog_item_consumer)
          return misaligned_service_account_error
        end

        trigger = yield(params)

        if trigger.valid?
          enforce_composite_identity!(service_account)

          ServiceResponse.success(payload: trigger)
        else
          ServiceResponse.error(message: trigger.errors.full_messages.to_sentence, reason: ERROR_REASON_INVALID_TRIGGER)
        end
      end

      private

      def service_account(service_account_id)
        return unless service_account_id.present?

        User.find_by_id(service_account_id)
      end

      def ai_catalog_item_consumer(ai_catalog_item_consumer_id)
        return unless ai_catalog_item_consumer_id.present?

        @ai_catalog_item_consumers ||= {}

        if @ai_catalog_item_consumers.key?(ai_catalog_item_consumer_id)
          return @ai_catalog_item_consumers[ai_catalog_item_consumer_id]
        end

        @ai_catalog_item_consumers[ai_catalog_item_consumer_id] =
          Ai::Catalog::ItemConsumer.find_by_id(ai_catalog_item_consumer_id)
      end

      # Inherited authorization never accepts a manually supplied service account.
      def user_is_authorized_to_service_account?(service_account, ai_catalog_item_consumer, params)
        if authorization_context
          return authorization_context.authorized_for_trigger?(
            project: project,
            item_consumer: ai_catalog_item_consumer,
            params: params
          )
        end

        allowed = Ability.allowed?(current_user, :manage_ai_flow_triggers, project)
        return allowed if service_account.nil? || allowed == false

        return false unless service_account.service_account?

        group = service_account.provisioned_by_group

        return false unless group
        return false unless group.root_ancestor.id == project.root_ancestor.id

        true
      end

      def enforce_composite_identity!(service_account)
        return if service_account.nil?

        service_account.update!(
          composite_identity_enforced: true
        )
      end

      # Older custom flows may have invalid configs, so prevent new trigger events for these flows,
      # as the trigger would be guaranteed to result in a DWS failure when it fires.
      def custom_flow_config_error(item_consumer)
        return unless item_consumer&.item&.custom_flow?

        result = Ai::Catalog::Items::ValidateConfigService
          .new(project: project, current_user: current_user)
          .execute(item_consumer.pinned_version&.definition)

        return if result.success?

        return result if result.reason == DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE

        ServiceResponse.error(
          message: s_('AICatalog|Cannot add trigger events because the custom flow configuration is invalid'),
          reason: DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG
        )
      end

      # Triggers for "manual" External Agents can only be created by users who can create External Agents.
      # See https://gitlab.com/gitlab-org/gitlab/-/issues/583687.
      def new_external_agents_allowed?
        Feature.enabled?(:ai_catalog_create_third_party_flows, current_user)
      end

      def disallow_new_external_agent_error
        ServiceResponse.error(message: 'You have insufficient permissions', reason: ERROR_REASON_UNAUTHORIZED)
      end

      # Inherited triggers use system attribution with hierarchy provenance.
      def audit_flow_trigger(event_name, trigger)
        return unless trigger

        audit_context = {
          name: event_name,
          author: audit_author,
          scope: trigger.project,
          target: trigger,
          target_details: "#{trigger.description} (ID: #{trigger.id})",
          message: event_name.humanize
        }
        audit_context[:additional_details] = audit_details if audit_details.present?

        ::Gitlab::Audit::Auditor.audit(audit_context)

        nil
      end

      def audit_author
        authorization_context&.audit_author || current_user
      end

      def audit_details
        authorization_context&.audit_details
      end

      def misaligned_service_account_error
        ServiceResponse.error(
          message: s_('AICatalog|The service account does not belong to the configuration for the agent or flow ' \
            'associated with this project'),
          reason: ERROR_REASON_SERVICE_ACCOUNT_MISMATCH
        )
      end

      def service_account_compatible_with_item_consumer?(service_account, ai_catalog_item_consumer)
        return true if service_account.nil? || ai_catalog_item_consumer.nil?

        ai_catalog_item_consumer.active_service_account == service_account
      end
    end
  end
end
