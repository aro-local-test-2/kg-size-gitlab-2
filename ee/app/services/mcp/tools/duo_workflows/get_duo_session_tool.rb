# frozen_string_literal: true

module Mcp
  module Tools
    module DuoWorkflows
      class GetDuoSessionTool < Mcp::Tools::Base::GraphqlTool
        POLL_AFTER_SECONDS = 30

        register_version VERSIONS[:v0_1_0], {
          graphql_operation: load_graphql('duo_workflows/get_duo_session.query.graphql'),
          operation_name: 'duoWorkflowWorkflows'
        }

        def build_variables
          {
            workflowId: Gitlab::GlobalId.build(
              model_name: ::Ai::DuoWorkflows::Workflow.name,
              id: params[:workflow_id]
            ).to_s
          }
        end

        private

        def process_result(result)
          processed_result = super
          return processed_result if processed_result[:isError]

          workflow = processed_result[:structuredContent]['nodes']&.first
          return ::Mcp::Tools::Base::Response.error('Operation returned no data') unless workflow

          session_response(workflow)
        end

        def session_response(workflow)
          status_name = workflow.fetch('statusName')
          status = status_name.tr('_', ' ')
          message = latest_agent_message(workflow)
          metadata = session_metadata(workflow, status)

          case status_name
          when 'finished'
            success_response(message || 'Session finished, but no final answer was produced.', metadata)
          when 'input_required'
            success_response(
              message || 'The last turn completed, but no agent answer was found.',
              metadata.merge('turn_complete' => true)
            )
          when 'tool_call_approval_required', 'plan_approval_required'
            approval_response(message, metadata)
          when 'paused'
            paused_response(message, metadata)
          else
            if terminal_status?(status_name)
              terminal_response(status, metadata)
            else
              running_response(status, message, metadata)
            end
          end
        end

        def session_metadata(workflow, status)
          {
            'workflow_id' => workflow.fetch('id').split('/').last.to_i,
            'status' => status,
            'web_url' => workflow.fetch('webUrl')
          }
        end

        def latest_agent_message(workflow)
          checkpoint = workflow['latestCheckpoint']
          return unless checkpoint

          last_message = checkpoint['lastDuoMessage']
          return last_message['content'] if agent_message?(last_message)

          # A trailing empty or tool-only turn must not hide the answer, so fall
          # back to the most recent agent message that actually has content.
          checkpoint['duoMessages']&.reverse_each&.find { |message| agent_message?(message) }&.dig('content')
        end

        def agent_message?(message)
          agent_authored?(message) && message['content'].present?
        end

        # Chat sessions tag the agent with role 'assistant'; flow sessions set
        # message_type 'agent' and often carry no role at all.
        def agent_authored?(message)
          return false unless message

          message['role'] == 'assistant' || message['messageType'] == 'agent'
        end

        def terminal_status?(status_name)
          ::Ai::DuoWorkflows::Workflow::TERMINAL_STATUSES.include?(status_name.to_sym)
        end

        def running_response(status, message, metadata)
          text = "Status: #{status}. Poll again in #{POLL_AFTER_SECONDS} seconds."
          text = "#{text}\n\nLatest agent update: #{message.truncate(500)}" if message

          success_response(text, metadata.merge('poll_after_seconds' => POLL_AFTER_SECONDS))
        end

        def approval_response(message, metadata)
          guidance = "Session is paused: #{metadata['status']}. Polling will NOT move it forward. " \
            "To proceed, call send_duo_session_input with workflow_id=#{metadata['workflow_id']} " \
            'and human_approval=true to approve, or false to reject. Include human_message with a ' \
            'rejection so the agent continues with your feedback. Without one, the agent is told not ' \
            'to proceed and the session continues.'
          text = message ? "#{message}\n\n#{guidance}" : guidance

          success_response(text, metadata.merge('awaiting_approval' => true))
        end

        def paused_response(message, metadata)
          guidance = 'Session is paused. Polling will NOT move it forward: it stays paused until ' \
            "something resumes it. See #{metadata['web_url']} to resume it."
          text = message ? "#{message}\n\n#{guidance}" : guidance

          success_response(text, metadata.merge('paused' => true))
        end

        def terminal_response(status, metadata)
          success_response("Session #{status}. See #{metadata['web_url']} for details.", metadata)
        end

        def success_response(text, metadata)
          ::Mcp::Tools::Base::Response.success([{ type: 'text', text: text }], metadata)
        end
      end
    end
  end
end
