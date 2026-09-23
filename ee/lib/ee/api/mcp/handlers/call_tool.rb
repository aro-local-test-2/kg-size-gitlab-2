# frozen_string_literal: true

module EE
  module API
    module Mcp
      module Handlers
        module CallTool
          extend ActiveSupport::Concern

          prepended do
            include ::Gitlab::InternalEventsTracking
            include ::Mcp::Tools::Concerns::ResourceFinder
            include ::Gitlab::Utils::StrongMemoize
          end

          private

          def track_start_event(tool_name, session_id, current_user, params: nil)
            track_internal_event(
              'start_mcp_tool_call',
              user: current_user,
              **resolve_tracking_scope(params),
              additional_properties: {
                session_id: session_id,
                tool_name: tool_name
              }
            )
          end

          def track_finish_event(tool_name, session_id, current_user, success:, error: nil, params: nil)
            additional_properties = {
              session_id: session_id,
              tool_name: tool_name,
              has_tool_call_success: success.to_s
            }

            if error
              additional_properties[:failure_reason] = error.class.name
              additional_properties[:error_status] = error.message&.truncate(255)
            end

            track_internal_event(
              'finish_mcp_tool_call',
              user: current_user,
              **resolve_tracking_scope(params),
              additional_properties: additional_properties
            )
          end

          def tool_call_namespace(params)
            scope = resolve_tracking_scope(params)
            (scope[:project] || scope[:namespace])&.root_ancestor
          end

          # Resolve the tool's target project/group so the analytics event is
          # attributed to it. No permission check: this feeds internal telemetry
          # only, never the response.
          def resolve_tracking_scope(params)
            strong_memoize_with(:resolved_tracking_scope, params) do
              arguments = params.to_h.with_indifferent_access[:arguments] || {}
              project_id = arguments[:project_id]
              group_id = arguments[:group_id]

              {}.tap do |tracking_scope|
                tracking_scope[:project] = lookup_project(project_id.to_s) if project_id.present?
                tracking_scope[:namespace] = lookup_group(group_id.to_s) if group_id.present?
              end.compact
            end
          end
        end
      end
    end
  end
end
