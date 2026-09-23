# frozen_string_literal: true

module Ai
  module Messaging
    module Adapters
      class Slack < Base
        InstallationNotFoundError = Class.new(StandardError)

        FEEDBACK_ACTION_ID = 'duo_feedback'

        APPROVAL_REVIEW_ACTION_ID = 'duo_approval_review'

        MONOLOGUE_MAX_LENGTH = 1500

        # Cancelled maps to complete since Slack has no cancelled state
        TODO_PLAN_STATUSES = {
          'completed' => 'complete',
          'cancelled' => 'complete',
          'in_progress' => 'in_progress',
          'pending' => 'pending'
        }.freeze

        def self.adapter_key
          'slack'
        end

        def self.supports_live_progress?
          true
        end

        def self.private_to_invoker?
          true
        end

        # Async path: reconstructed from persisted callback context by CallbackWorker.
        # Only deliver_result, deliver_error, and lifecycle hooks are called on this instance.
        def self.from_callback_context(ctx)
          new(
            team_id: ctx['team_id'],
            channel_id: ctx['channel_id'],
            thread_ts: ctx['thread_ts'],
            message_ts: ctx['message_ts'],
            user_id: ctx['user_id']
          )
        end

        # Sync path: constructed by the caller (AppMentionedService) with full event state.
        def initialize(team_id:, channel_id:, thread_ts:, message_ts:, user_id:)
          @team_id = team_id
          @channel_id = channel_id
          @thread_ts = thread_ts
          @message_ts = message_ts
          @user_id = user_id
        end

        def build_callback_context
          {
            'team_id' => @team_id,
            'channel_id' => @channel_id,
            'thread_ts' => @thread_ts,
            'message_ts' => @message_ts,
            'user_id' => @user_id
          }
        end

        # Earliest user-visible acknowledgement, fired synchronously before the
        # workflow exists: an eyes reaction plus a rotating status indicator via
        # assistant.threads.setStatus. Slack clears the status automatically once
        # the first real message is posted (by on_progress, or by deliver_result
        # if on_progress never fires).
        def on_request_received
          slack_api.add_reaction(channel: @channel_id, name: 'eyes', timestamp: @message_ts)

          messages = loading_messages
          slack_api.set_status(
            channel: @channel_id,
            thread_ts: @thread_ts,
            status: messages.first,
            loading_messages: messages
          )
        rescue StandardError => e
          track_slack_exception(e, build_callback_context)
        end

        # Records context only; posting no message here lets the on_request_received
        # status indicator keep spinning until on_progress posts the first real
        # content (or deliver_result posts the answer if on_progress never fires).
        #
        # Idempotent: CallbackWorker is at-least-once.
        def on_flow_started(callback_context:, workflow:)
          callback_context['session_url'] = workflow.web_url
          callback_context['workflow_id'] = workflow.id
          persist_progress_state(workflow, callback_context)
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        def on_flow_completed(callback_context:, workflow:) # rubocop:disable Lint/UnusedMethodArgument -- interface contract
          slack_api.remove_reaction(channel: callback_context['channel_id'], name: 'eyes',
            timestamp: callback_context['message_ts'])
          slack_api.add_reaction(channel: callback_context['channel_id'], name: 'white_check_mark',
            timestamp: callback_context['message_ts'])
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        # workflow: nil -- sync failure before a workflow exists, eyes was already added via on_request_received.
        # workflow: present -- async failure, either before on_flow_started (no message posted yet) or after it.
        # In both cases eyes was added, so we always attempt to remove it.
        def on_flow_failed(callback_context:, error:, workflow: nil)
          slack_api.remove_reaction(channel: callback_context['channel_id'], name: 'eyes',
            timestamp: callback_context['message_ts'])
          slack_api.add_reaction(channel: callback_context['channel_id'], name: 'x',
            timestamp: callback_context['message_ts'])

          # Surface the error, plus the session link so the failure can be
          # investigated in GitLab:
          #   * status_ts present -- a progress message exists; edit it with the error.
          #   * workflow but no progress message -- post a threaded reply with the error.
          #   * no workflow (sync failure) -- nothing to link; send an ephemeral error.
          if callback_context['status_ts']
            slack_api.update_message(
              channel: callback_context['channel_id'],
              ts: callback_context['status_ts'],
              text: error_text(error),
              blocks: [markdown_block(error_text(error))]
            )
            post_session_link_ephemeral(callback_context)
          elsif workflow
            callback_context['session_url'] = workflow.web_url
            post_threaded_reply(callback_context, error_text(error), blocks: [markdown_block(error_text(error))])
            post_session_link_ephemeral(callback_context)
          else
            deliver_error(callback_context: callback_context, error: error)
          end
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        def on_approval_required(callback_context:, workflow:)
          return unless Feature.enabled?(:slack_duo_api_flow, workflow.resource_parent&.root_ancestor)
          return unless workflow.tool_call_approval_required?

          pending = ::Ai::DuoWorkflows::PendingToolApproval.for(workflow)
          return unless pending
          return if callback_context['pending_approval'] == pending.fingerprint

          flush_pending_progress(workflow, callback_context)

          # Posted as a regular message so it survives a client reload; the
          # tool arguments stay out of the channel and only render in the
          # modal opened by the Review button.
          response = post_threaded_reply(
            callback_context,
            approval_request_text(pending),
            blocks: approval_blocks(pending, workflow)
          )
          return unless response['ok']

          # The fingerprint stops a redelivered event from posting twice; the ts
          # lets the decision handler update this message once it is answered.
          workflow.merge_messaging_callback_context!(
            callback_context.slice('status_ts').merge(
              'pending_approval' => pending.fingerprint,
              'pending_approval_ts' => response['ts']
            ).compact
          )
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        def on_progress(delta:, callback_context:)
          render_progress(delta.messages, callback_context)
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        # Edits the message on_progress already posted, or posts a fresh threaded
        # reply if it never did, so the whole run reads as one message.
        #
        # Slack errors are tracked, never raised: the client reports API and HTTP failures
        # as an `ok: false` response, so `ok` is what tells CallbackWorker the answer landed.
        def deliver_result(callback_context:, message:, workflow:)
          blocks = result_blocks(message, final_todos(workflow), callback_context)

          delivered =
            if callback_context['status_ts']
              update_result_message(callback_context, message, blocks)
            else
              post_threaded_reply(callback_context, message, blocks: blocks)['ok']
            end

          # Sessions are readable only by the invoker, so the link goes out as an
          # ephemeral message instead of the shared reply, where it would 404 for
          # everyone else in the channel.
          post_session_link_ephemeral(callback_context) if delivered

          delivered
        rescue StandardError => e
          track_slack_exception(e, callback_context)
          false
        end

        # Posts an ephemeral error message visible only to the requesting user.
        # Best-effort: errors are tracked, never raised, and nothing re-attempts this
        # delivery -- unlike deliver_result, there is no answer at stake.
        # Threads the error into an existing thread; a top-level mention gets
        # channel-root placement to maximise visibility of the private ephemeral.
        def deliver_error(callback_context:, error:)
          in_existing_thread = callback_context['thread_ts'].present? &&
            callback_context['thread_ts'] != callback_context['message_ts']
          thread_ts = in_existing_thread ? callback_context['thread_ts'] : nil

          slack_api.post_ephemeral(
            channel: callback_context['channel_id'],
            user: callback_context['user_id'],
            text: error_text(error),
            thread_ts: thread_ts
          )
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        private

        # Rotating strings shown via assistant.threads.setStatus for the whole run.
        # Slack auto-rotates through these as a loading animation and clears them
        # when the first real message is posted. When the agent produces no todo
        # list and no monologue, this status is the only progress signal the user
        # sees, so the strings describe the work generally rather than startup.
        # Built at call time (not a constant) so translations resolve dynamically.
        def loading_messages
          [
            s_('DuoSlack|is working on your request…'),
            s_('DuoSlack|is thinking it through…')
          ]
        end

        def flush_pending_progress(workflow, callback_context)
          return if callback_context['status_ts']

          delta = ::Ai::DuoWorkflows::ProgressReader.new
            .delta_since(workflow, cursor: callback_context['progress_cursor'])
          return unless delta.new_messages.any? { |m| renders_progress?(m) }

          render_progress(delta.messages, callback_context)
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        def renders_progress?(message)
          (message['message_type'] == 'agent' && message['content'].present?) ||
            message.dig('tool_info', 'name') == 'todo_write'
        end

        def render_progress(messages, callback_context)
          todos = latest_todos(messages)
          monologue = latest_monologue(messages)
          return if todos.empty? && monologue.blank?

          blocks = []

          blocks << plan_block(todos) if todos.any?

          blocks << markdown_block(monologue) if monologue.present?

          if callback_context['status_ts']
            slack_api.update_message(
              channel: callback_context['channel_id'],
              ts: callback_context['status_ts'],
              text: progress_fallback_text(todos, monologue),
              blocks: blocks
            )
          else
            # First real content: post a new message (the status indicator clears
            # automatically when a message is posted in the thread).
            response = slack_api.post_message(
              channel: callback_context['channel_id'],
              thread_ts: callback_context['thread_ts'],
              text: progress_fallback_text(todos, monologue),
              blocks: blocks
            )
            callback_context['status_ts'] = response['ts'] if response['ok']
          end
        end

        def final_todos(workflow)
          latest_todos(workflow.latest_ui_chat_log)
        end

        # The single source of truth for the final message blocks, so the post and
        # edit paths in deliver_result can never drift (that drift is what dropped
        # the feedback buttons from plan-less replies).
        def result_blocks(message, todos, callback_context)
          blocks = []
          blocks << plan_block(todos) if todos.any?
          blocks << markdown_block(message)
          blocks.concat(feedback_blocks(callback_context))
          blocks
        end

        def update_result_message(callback_context, message, blocks)
          response = slack_api.update_message(
            channel: callback_context['channel_id'],
            ts: callback_context['status_ts'],
            text: message,
            blocks: blocks
          )
          return true if response['ok']

          # Blocks rejected (e.g. the answer exceeds the markdown block's 12k
          # limit): re-edit with plain text so long answers are never lost.
          slack_api.update_message(
            channel: callback_context['channel_id'],
            ts: callback_context['status_ts'],
            text: message,
            blocks: []
          )['ok']
        end

        # block_id is freshly generated on every render: Slack requires a new
        # block_id for a plan update to take effect on an edited message.
        def plan_block(todos)
          tasks = todos.each_with_index.map do |todo, index|
            {
              task_id: "task_#{index}",
              title: todo['description'].to_s,
              status: TODO_PLAN_STATUSES.fetch(todo['status'].to_s)
            }
          end

          {
            type: 'plan',
            block_id: SecureRandom.hex(8),
            title: s_('DuoSlack|Plan'),
            tasks: tasks
          }
        end

        def progress_fallback_text(todos, monologue)
          return todos.map { |t| t['description'].to_s }.join("\n") if todos.any?

          monologue.to_s
        end

        def latest_monologue(messages)
          messages
            .reverse_each
            .detect { |m| m['message_type'] == 'agent' && m['content'].present? }
            &.dig('content')
            &.truncate(MONOLOGUE_MAX_LENGTH, separator: ' ')
        end

        def latest_todos(messages)
          todo_info = messages.reverse_each.detect do |m|
            m['tool_info'].is_a?(Hash) && m['tool_info']['name'] == 'todo_write'
          end&.dig('tool_info')

          todo_info&.dig('args', 'todos') || []
        end

        def post_threaded_reply(callback_context, text, blocks: [])
          slack_api.post_message(
            channel: callback_context['channel_id'],
            thread_ts: callback_context['thread_ts'],
            text: text,
            blocks: blocks
          )
        end

        # Standard Markdown, ~12k char limit, translated natively by Slack.
        def markdown_block(message)
          { type: 'markdown', text: message }
        end

        # Sessions are private to the invoker, so the link is delivered as an
        # ephemeral message only they can see; in the shared reply it would 404
        # for everyone else. Best-effort: ephemerals are transient anyway and the
        # session stays reachable through the GitLab session list.
        def post_session_link_ephemeral(callback_context)
          url = callback_context['session_url']
          return if url.blank?

          link_text = s_('DuoSlack|View your session in GitLab (only visible to you)')
          slack_api.post_ephemeral(
            channel: callback_context['channel_id'],
            user: callback_context['user_id'],
            text: "_<#{url}|#{link_text}>_",
            thread_ts: callback_context['thread_ts']
          )
        rescue StandardError => e
          track_slack_exception(e, callback_context)
        end

        def feedback_blocks(callback_context)
          workflow_id = callback_context['workflow_id']
          return [] if workflow_id.blank?

          [{
            type: 'context_actions',
            elements: [{
              type: 'feedback_buttons',
              action_id: FEEDBACK_ACTION_ID,
              positive_button: {
                text: { type: 'plain_text', text: s_('DuoSlack|Helpful') },
                accessibility_label: s_('DuoSlack|Mark this response as helpful'),
                value: "up:#{workflow_id}"
              },
              negative_button: {
                text: { type: 'plain_text', text: s_('DuoSlack|Not helpful') },
                accessibility_label: s_('DuoSlack|Mark this response as not helpful'),
                value: "down:#{workflow_id}"
              }
            }]
          }]
        end

        def approval_request_text(pending)
          format(
            s_('DuoSlack|GitLab Duo needs your approval to run: %{tool_names}'),
            tool_names: pending.tool_names.uniq.map { |name| "`#{name}`" }.join(', ')
          )
        end

        def approval_blocks(pending, workflow)
          [
            markdown_block(approval_request_text(pending)),
            {
              type: 'actions',
              block_id: "duo_approval_#{pending.fingerprint}",
              elements: [{
                type: 'button',
                action_id: APPROVAL_REVIEW_ACTION_ID,
                text: { type: 'plain_text', text: s_('DuoSlack|Review') },
                value: "#{workflow.id}:#{pending.fingerprint}",
                style: 'primary'
              }]
            }
          ]
        end

        def persist_progress_state(workflow, callback_context)
          workflow.merge_messaging_callback_context!(
            callback_context.slice('status_ts', 'session_url', 'workflow_id').compact
          )
        end

        def error_text(error)
          case error
          when :namespace_not_configured
            preferences_url = ::Gitlab::Routing.url_helpers.profile_preferences_url

            format(
              s_("DuoSlack|Set your default Duo namespace in your " \
                "GitLab preferences (%{preferences_url}) to use Duo from Slack."),
              preferences_url: preferences_url
            )
          when :flow_not_enabled
            s_("DuoSlack|The Duo Developer flow is not enabled for your namespace. " \
              "Ask a group owner to enable it in the Duo Agent Platform settings.")
          when :service_account_error
            s_("DuoSlack|Could not set up the service account for the Duo Developer flow. " \
              "Contact your group owner.")
          when :workspace_project_error
            s_("DuoSlack|Could not set up the workspace project. " \
              "Check that you have access to the namespace and permission to create projects.")
          when :execute_workflow_failed
            s_("DuoSlack|Failed to start the Duo Developer workflow. Try again.")
          when :flow_failed
            s_("DuoSlack|Something went wrong while running the task. Try again.")
          when :flow_stopped
            s_("DuoSlack|The session was stopped before it finished.")
          when :workflow_locked
            s_("DuoSlack|I'm still working on an earlier message in this thread. " \
              "Wait for that to finish, then mention me again.")
          when :forbidden
            s_("DuoSlack|You don't have access to Duo in this namespace, or it has run out of " \
              "GitLab Duo credits. Ask a group owner to check the Duo Agent Platform settings.")
          when :no_response
            s_("DuoSlack|The task completed but the agent didn't produce a response. " \
              "Check the session in GitLab for details.")
          when :message_too_long
            format(
              s_("DuoSlack|Your message is too long for me to process " \
                "(the limit is about %{limit} characters). Shorten it and mention me again."),
              limit: ActiveSupport::NumberHelper.number_to_delimited(::Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH)
            )
          else
            s_("DuoSlack|Something went wrong. Try again.")
          end
        end

        def slack_api
          @slack_api ||= begin
            installation = SlackIntegration.with_bot.find_by_team_id(@team_id)
            raise InstallationNotFoundError, "No Slack installation found for team #{@team_id}" unless installation

            ::Slack::API.new(installation)
          end
        end

        def track_slack_exception(exception, callback_context)
          Gitlab::ErrorTracking.track_exception(exception,
            slack_team_id: callback_context['team_id'],
            channel_id: callback_context['channel_id']
          )
        end
      end
    end
  end
end
