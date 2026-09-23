# frozen_string_literal: true

module Integrations
  module SlackInteractions
    # Builds the Block Kit modal a session owner sees after clicking Review on
    # a Duo tool approval message. Lists every pending tool call with its
    # arguments and collects one approve/deny decision for the whole batch.
    # `workflow_id:fingerprint` travels in `private_metadata` so the
    # `view_submission` payload is self-contained.
    class DuoToolApprovalModal
      CALLBACK_ID = 'duo_tool_approval_modal'
      DECISION_BLOCK_ID = 'duo_approval_decision'
      DECISION_ACTION_ID = 'decision'
      DECISION_APPROVE = 'approve'
      DECISION_DENY = 'deny'

      # Slack caps a modal at 100 blocks and a section at 3000 characters.
      MAX_CALLS = 20
      SUMMARY_MAX_LENGTH = 500
      ARG_VALUE_MAX_LENGTH = 400
      CALL_TEXT_MAX_LENGTH = 2900
      CODE_FENCE_OVERHEAD = "\n```\n\n```".length

      def self.not_owner_view
        notice_view(s_('DuoSlack|Only the person who started this session can respond to this request.'))
      end

      def self.stale_view
        notice_view(s_('DuoSlack|This approval request has already been answered.'))
      end

      def self.account_not_linked_view
        notice_view(s_('DuoSlack|Your Slack account is not connected to a GitLab account, ' \
          'so you cannot respond to this request.'))
      end

      def self.notice_view(text)
        {
          type: 'modal',
          title: title,
          close: { type: 'plain_text', text: s_('DuoSlack|Close') },
          blocks: [section(text)]
        }
      end
      private_class_method :notice_view

      def self.title
        { type: 'plain_text', text: s_('DuoSlack|Review Duo actions') }
      end

      def self.section(text)
        { type: 'section', text: { type: 'mrkdwn', text: text } }
      end

      def initialize(workflow_id, pending)
        @workflow_id = workflow_id
        @pending = pending
      end

      def build
        {
          type: 'modal',
          callback_id: CALLBACK_ID,
          private_metadata: "#{workflow_id}:#{pending.fingerprint}",
          title: self.class.title,
          submit: { type: 'plain_text', text: s_('DuoSlack|Submit') },
          close: { type: 'plain_text', text: s_('DuoSlack|Cancel') },
          blocks: [intro_block, *call_blocks, decision_block]
        }
      end

      private

      attr_reader :workflow_id, :pending

      def intro_block
        count = pending.calls.size
        text = ns_(
          'DuoSlack|GitLab Duo wants to run %{count} action. Review it and choose whether to continue.',
          'DuoSlack|GitLab Duo wants to run %{count} actions. Review them and choose whether to continue.',
          count
        )

        self.class.section(format(text, count: count))
      end

      def call_blocks
        calls = pending.calls
        blocks = calls.first(MAX_CALLS).flat_map { |call| [{ type: 'divider' }, self.class.section(call_text(call))] }
        return blocks if calls.size <= MAX_CALLS

        blocks << {
          type: 'context',
          elements: [{
            type: 'plain_text',
            text: format(s_('DuoSlack|%{count} more actions are not shown here.'), count: calls.size - MAX_CALLS)
          }]
        }
      end

      def call_text(call)
        summary = call_summary(call)
        return summary if call[:args].blank?

        args = Gitlab::Json.pretty_generate(display_args(call[:args]))
        budget = CALL_TEXT_MAX_LENGTH - summary.length - CODE_FENCE_OVERHEAD
        args = args.truncate(budget, separator: "\n", omission: "\n…") if args.length > budget

        "#{summary}\n```\n#{args}\n```"
      end

      def call_summary(call)
        summary = call[:content].presence ||
          format(s_('DuoSlack|GitLab Duo wants to run the %{tool_name} tool.'), tool_name: call[:name])

        summary.truncate(SUMMARY_MAX_LENGTH, separator: ' ')
      end

      # Truncated per value so every key stays visible: a long first value must
      # not hide a `force: true` further down the hash.
      def display_args(args)
        args.transform_values do |value|
          text = value.is_a?(String) ? value : Gitlab::Json.dump(value)
          next value if text.length <= ARG_VALUE_MAX_LENGTH

          text.truncate(ARG_VALUE_MAX_LENGTH)
        end
      end

      def decision_block
        {
          type: 'input',
          block_id: DECISION_BLOCK_ID,
          label: { type: 'plain_text', text: s_('DuoSlack|Your decision') },
          element: {
            type: 'radio_buttons',
            action_id: DECISION_ACTION_ID,
            options: [
              decision_option(DECISION_APPROVE, s_('DuoSlack|Approve and continue')),
              decision_option(DECISION_DENY, s_('DuoSlack|Deny and continue without running these actions'))
            ]
          }
        }
      end

      def decision_option(value, text)
        { value: value, text: { type: 'plain_text', text: text } }
      end
    end
  end
end
