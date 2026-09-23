# frozen_string_literal: true

module Mcp
  module Tools
    module DuoWorkflows
      # Only the AI Catalog branch is exposed: a session created without a consumer has no
      # `ai_catalog_item_version`, and `send_duo_session_input` cannot answer it.
      class StartDuoSessionService < Base::AggregatedService
        include Gitlab::Utils::Override

        UNDERLYING_TOOL = :create_duo_workflow
        FORWARDED_PARAMS = %i[project_id ai_catalog_item_consumer_id goal].freeze
        FORCED_PARAMS = { start_workflow: true }.freeze
        ROUTE_PARAMS = (FORWARDED_PARAMS + FORCED_PARAMS.keys).freeze

        POLL_AFTER_SECONDS = GetDuoSessionTool::POLL_AFTER_SECONDS

        register_version '0.1.0', {
          toolset: :duo_agent_platform,
          description: <<~DESC.strip,
            Start a GitLab Duo Agent Platform session that runs a flow from the AI Catalog, and
            return its session id.

            The session runs asynchronously in a CI job that takes minutes to start. Poll
            get_duo_session with the returned workflow_id to follow it, and answer it with
            send_duo_session_input when it asks for input.

            This starts a real CI job that can push commits and open merge requests, so only call
            it when the user asked for the flow to run.
          DESC
          annotations: {
            readOnlyHint: false,
            destructiveHint: true
          },
          input_schema: {
            type: 'object',
            properties: {
              project_id: {
                type: 'string',
                description: 'ID or full path of the project the flow runs in.'
              },
              ai_catalog_item_consumer_id: {
                type: 'integer',
                description: 'ID of the AI Catalog item consumer that configures which flow to run. ' \
                  'Catalog flows are configured per project; ask the user which flow to run if unsure.'
              },
              goal: {
                type: 'string',
                description: 'What the agent should do, in prose. This is the prompt the flow starts from.'
              }
            },
            required: %w[project_id ai_catalog_item_consumer_id goal]
          }
        }

        override :tool_name
        def self.tool_name
          'start_duo_session'
        end

        protected

        override :perform_default
        def perform_default(arguments = {})
          session_response(super)
        end

        override :transform_arguments
        def transform_arguments(args)
          args.slice(*FORWARDED_PARAMS).merge(FORCED_PARAMS)
        end

        override :select_tool
        def select_tool(_args)
          tools.find { |tool| tool.name.to_sym == UNDERLYING_TOOL }
        end

        private

        def session_response(response)
          return response if response[:isError]

          workflow = response[:structuredContent]
          return response unless workflow.is_a?(Hash)

          content = {
            'workflow_id' => workflow['id'],
            'status' => workflow['status'],
            'workload_id' => workflow.dig('workload', 'id'),
            'poll_after_seconds' => POLL_AFTER_SECONDS
          }

          text = "Session #{workflow['id']} started. It runs in a CI job, which can take a few " \
            "minutes to start. Poll get_duo_session with workflow_id=#{workflow['id']} in " \
            "#{POLL_AFTER_SECONDS} seconds."

          ::Mcp::Tools::Base::Response.success([{ type: 'text', text: text }], content)
        end
      end
    end
  end
end
