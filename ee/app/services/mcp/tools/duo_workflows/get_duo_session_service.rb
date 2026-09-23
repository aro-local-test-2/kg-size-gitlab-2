# frozen_string_literal: true

module Mcp
  module Tools
    module DuoWorkflows
      class GetDuoSessionService < Base::GraphqlService
        ungovernable!

        register_version '0.1.0', {
          toolset: :duo_agent_platform,
          description: 'Check a Duo Agent Platform session started by trigger_duo_flow or ask_duo_agent. ' \
            'Running sessions include a poll_after_seconds hint. Finished and input-required sessions include ' \
            'the latest agent answer. Approval-required sessions need send_duo_session_input instead of polling.',
          input_schema: {
            type: 'object',
            properties: {
              workflow_id: {
                type: 'integer',
                description: 'Workflow ID returned by trigger_duo_flow or ask_duo_agent.'
              }
            },
            required: %w[workflow_id]
          },
          annotations: {
            readOnlyHint: true
          }
        }

        override :tool_aliases
        def self.tool_aliases
          ['get_duo_workflow_status']
        end

        protected

        override :perform_default
        def perform_default(arguments = {})
          execute_graphql_tool(arguments)
        end

        private

        def graphql_tool_class
          Mcp::Tools::DuoWorkflows::GetDuoSessionTool
        end
      end
    end
  end
end
