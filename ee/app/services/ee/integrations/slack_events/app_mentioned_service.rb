# frozen_string_literal: true

module EE
  module Integrations
    module SlackEvents
      module AppMentionedService
        extend ::Gitlab::Utils::Override

        FOUNDATIONAL_FLOW_REFERENCE = 'developer/v1'
        API_FLOW_REFERENCE = 'slack_assistant/v1'

        SLACK_CONTEXT_PREAMBLE = <<~PREAMBLE.strip
          You were mentioned in a Slack conversation.

          <formatting>
          Respond in standard Markdown. Slack renders it natively, so do not use
          Slack-specific mrkdwn syntax. Always write links as [text](url); never
          put a bare URL inside bold, italic, or code formatting.
          </formatting>
          Your final response will automatically be posted back to the Slack thread.
        PREAMBLE

        SLACK_GOAL_MAX = ::Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH

        CHANNEL_CONTEXT_MESSAGE_LIMIT = 15
        CHANNEL_CONTEXT_FETCH_LIMIT = 50
        USER_MAP_AUTHOR_LIMIT = 50

        # nil is a plain message, the rest all include useful info for Duo.
        # We exclude channel events such as a join, leave, or topic change.
        CHANNEL_CONTEXT_SUBTYPES = [nil, 'bot_message', 'me_message', 'thread_broadcast', 'file_share'].freeze

        CHANNEL_CONTEXT_NOTE = 'Recent messages from the channel, oldest first. Use them only as ' \
          'background; the conversation below is what you must respond to.'

        private

        override :experiment_features_available?
        def experiment_features_available?(gitlab_user)
          ::Ai::Catalog.user_can_access_experimental_and_beta_features?(gitlab_user)
        end

        override :trigger_duo_flow
        def trigger_duo_flow(gitlab_user)
          flow_reference = resolve_flow_reference(gitlab_user)

          resolved = resolve_flow(flow_reference, gitlab_user)

          adapter = build_adapter

          unless resolved.success?
            track_block_event(gitlab_user, "flow_resolver_#{resolved.reason || 'failed'}")
            adapter.deliver_error(
              callback_context: adapter.build_callback_context,
              error: resolved.reason
            )
            return
          end

          goal = build_goal(preamble_for(flow_reference))

          # build_goal returns nil when the triggering message alone exceeds the
          # budget, so truncation cannot produce a usable goal. Tell the user.
          unless goal
            track_block_event(gitlab_user, 'message_too_long')
            slack_api.add_reaction(channel: channel_id, name: 'x', timestamp: message_ts)
            adapter.deliver_error(
              callback_context: adapter.build_callback_context,
              error: :message_too_long
            )
            return
          end

          container = resolved.payload[:container]
          project = resolved.payload[:project]
          bundle = ::Ai::Messaging::Adapters::Base::TriggerBundle.new(
            current_user: gitlab_user,
            service_account: resolved.payload[:service_account],
            flow_reference: flow_reference,
            flow_config_id: resolved.payload[:flow_config_id],
            flow_config_schema_version: resolved.payload[:flow_config_schema_version],
            flow_version: resolved.payload[:flow_version],
            project: project,
            container: container,
            goal: goal,
            runtime: resolved.payload[:runtime],
            source_type: :slack,
            source_link: slack_message_link
          )

          result = adapter.trigger(bundle)

          if result.success?
            track_internal_event(
              'trigger_slack_duo',
              user: gitlab_user,
              project: project,
              namespace: container.is_a?(::Namespace) ? container : project.namespace
            )
            return
          end

          track_block_event(gitlab_user, 'flow_trigger_failed')

          ::Gitlab::IntegrationsLogger.info(
            message: 'Duo Messaging: flow trigger failed',
            failure_reason: result.reason,
            error_message: result.message,
            slack_workspace_id: slack_workspace_id
          )
        end

        def build_goal(preamble)
          messages = fetch_thread_messages
          if messages.nil? || messages.empty?
            messages = [{ 'user' => slack_user_id, 'text' => slack_event[:text].to_s }]
          end

          channel_messages = fetch_channel_messages # Ordered newest first
          user_map = build_user_map(messages.reverse + channel_messages.reverse, first: USER_MAP_AUTHOR_LIMIT)

          conversation = ::Ai::Messaging::Conversation.new(
            messages: messages.map { |m| render_message(m, user_map) },
            marker: method(:omitted_marker)
          )

          # Nil when even the newest message cannot fit alone, or on overflow.
          goal, thread_block = conversation.render_within(
            SLACK_GOAL_MAX, on_overflow: method(:log_goal_overflow)
          ) { |text| assemble_goal(preamble, text) }

          return if goal.nil?

          insert_channel_context_that_fits(preamble, goal, thread_block, channel_messages, user_map)
        end

        def insert_channel_context_that_fits(preamble, goal, thread_block, channel_messages, user_map)
          return goal if channel_messages.blank?

          conversation = ::Ai::Messaging::Conversation.new(
            messages: channel_messages.reverse.map { |m| render_message(m, user_map) },
            marker: ->(_dropped) {}
          )

          with_channel_context, = conversation.render_within(
            SLACK_GOAL_MAX, on_overflow: method(:log_goal_overflow)
          ) { |text| assemble_goal(preamble, thread_block, text) }

          with_channel_context || goal
        end

        def fetch_channel_messages
          parsed = slack_api.conversation_history(
            channel: channel_id, limit: CHANNEL_CONTEXT_FETCH_LIMIT, latest: thread_ts
          )
          return [] unless parsed['ok']

          messages = parsed['messages'] || []
          messages.select { |m| CHANNEL_CONTEXT_SUBTYPES.include?(m['subtype']) && m['text'].present? }
            .first(CHANNEL_CONTEXT_MESSAGE_LIMIT)
        end

        # Fires only if assembly ever stops being exactly additive (fail closed).
        def log_goal_overflow(goal_length, _overhead)
          ::Gitlab::IntegrationsLogger.error(
            message: 'Duo Messaging: assembled goal exceeded the limit',
            goal_length: goal_length,
            slack_workspace_id: slack_workspace_id
          )
        end

        def resolve_flow_reference(gitlab_user)
          namespace = gitlab_user.default_duo_namespace&.root_ancestor

          return API_FLOW_REFERENCE if ::Feature.enabled?(:slack_duo_api_flow, namespace)

          FOUNDATIONAL_FLOW_REFERENCE
        end

        def resolve_flow(flow_reference, gitlab_user)
          resolver = ::Ai::Messaging::DefaultProjectFlowResolver.new(
            flow_reference: flow_reference, current_user: gitlab_user
          )

          resolver.runtime == :workhorse ? resolver.resolve_namespace : resolver.execute
        end

        def preamble_for(flow_reference)
          return if flow_reference == API_FLOW_REFERENCE

          SLACK_CONTEXT_PREAMBLE
        end

        def assemble_goal(preamble, conversation_block, channel_block = nil)
          sections = [preamble].compact

          # '' is a special case for the default empty state to measure the default size, so we can't use .present?
          unless channel_block.nil?
            sections << "<channel_context>\n#{CHANNEL_CONTEXT_NOTE}\n#{channel_block}\n</channel_context>"
          end

          sections << "<conversation>\n#{conversation_block}\n</conversation>"
          sections.join("\n\n")
        end

        def omitted_marker(count)
          return if count == 0

          "<!-- #{count} earlier #{'message'.pluralize(count)} omitted due to length -->"
        end

        def render_message(message, user_map)
          author_id = message['user'] || message['bot_id']
          gitlab_attr = user_map[author_id] ? " gitlab=\"@#{user_map[author_id]}\"" : ''
          text = CGI.escapeHTML(message['text'].to_s)
          "<message author=\"#{author_id}\"#{gitlab_attr}>\n#{text}\n</message>"
        end

        def fetch_thread_messages
          parsed = slack_api.get('conversations.replies', channel: channel_id, ts: thread_ts).parsed_response

          if parsed.is_a?(Hash) && parsed['ok']
            parsed['messages'] || []
          else
            log_slack_error('Slack API error when fetching thread', parsed)
            nil
          end
        rescue *::Gitlab::HTTP::HTTP_ERRORS => e
          ::Gitlab::ErrorTracking.track_exception(e, slack_workspace_id: slack_workspace_id)
          nil
        end

        # Returns a mapping of Slack user IDs to GitLab usernames:
        #   { 'U0001' => 'alice', 'U0002' => nil }
        # Unlinked Slack users map to nil.
        def build_user_map(messages, first:)
          author_ids = messages.filter_map { |m| m['user'] }.uniq.first(first)
          gitlab_map = ChatName.for_team_and_chat_ids(slack_workspace_id, author_ids).with_user
            .each_with_object({}) { |cn, h| h[cn.chat_id] = cn.user.username }

          author_ids.index_with { |id| gitlab_map[id] }
        rescue ::ActiveRecord::ActiveRecordError => e
          ::Gitlab::ErrorTracking.track_exception(e, slack_workspace_id: slack_workspace_id)
          {}
        end

        def log_slack_error(message, response)
          ::Gitlab::IntegrationsLogger.error(
            message: message,
            slack_workspace_id: slack_workspace_id,
            slack_user_id: slack_user_id,
            channel_id: channel_id,
            response: response.respond_to?(:to_h) ? response.to_h : response.to_s
          )
        end

        def slack_message_link
          response = slack_api.get_permalink(channel: channel_id, message_ts: message_ts)
          response['permalink'] if response['ok']
        end

        def build_adapter
          ::Ai::Messaging::Adapters::Slack.new(
            team_id: slack_workspace_id,
            channel_id: channel_id,
            thread_ts: thread_ts,
            message_ts: message_ts,
            user_id: slack_user_id
          )
        end
      end
    end
  end
end
