# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class BuildAdditionalContextService
      DWS_STANDARD_CONTEXT_CATEGORY = "agent_platform_standard_context"
      DWS_TRIGGER_CONTEXT_CATEGORY = "agent_platform_trigger_context"
      DWS_RESOURCE_CONTEXT_CATEGORY = "agent_platform_resource_context"
      DWS_CONTEXT_VERSION = "1.0.0"
      DWS_STANDARD_CONTEXT_VERSION = "1.1.0"
      DWS_RESOURCE_CONTEXT_VERSION = "1.1.0"

      def initialize(standard_context_params:, trigger_params: {}, additional_context: nil, resource: nil)
        @standard_context_params = standard_context_params
        @trigger_params = trigger_params
        @resource = resource
        @additional_context = remove_dws_reserved_contexts(additional_context)
      end

      def execute
        context = additional_context + standard_context + trigger_context + resource_context

        ServiceResponse.success(payload: { context: context })
      end

      private

      attr_reader :standard_context_params, :trigger_params, :additional_context, :resource

      # Standard, trigger, and resource context categories are controlled by Rails:
      # drop any caller-supplied envelope with a colliding category so the central
      # version always wins.
      def remove_dws_reserved_contexts(context)
        reserved = [DWS_STANDARD_CONTEXT_CATEGORY, DWS_TRIGGER_CONTEXT_CATEGORY, DWS_RESOURCE_CONTEXT_CATEGORY]
        Array.wrap(context).reject do |envelope|
          category = envelope["Category"] || envelope[:Category]
          reserved.include?(category)
        end
      end

      def standard_context
        fields = ::Ai::DuoWorkflows::AdditionalContext::StandardContextBuilder.build(**standard_context_params)

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_STANDARD_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_STANDARD_CONTEXT_VERSION
          )
        ]
      end

      # Separate envelope so the standard context schema stays frozen across deploys:
      # an unknown category is skipped with a warning; an unknown field inside a known
      # category fails envelope validation.
      def trigger_context
        fields = ::Ai::DuoWorkflows::AdditionalContext::TriggerContextBuilder.build(**trigger_params)

        return [] unless fields

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_TRIGGER_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_CONTEXT_VERSION
          )
        ]
      end

      def resource_context
        fields = ::Ai::DuoWorkflows::AdditionalContext::ResourceContextBuilder.build(resource)
        return [] unless fields

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_RESOURCE_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_RESOURCE_CONTEXT_VERSION
          )
        ]
      end
    end
  end
end
