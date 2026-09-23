# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class WorkflowCheckpointEventPresenter < Gitlab::View::Presenter::Delegated
      include Gitlab::Utils::StrongMemoize

      presents ::Ai::DuoWorkflows::Checkpoint, as: :event

      DuoMessage = Struct.new(:content, :message_type, :message_sub_type, :status, :tool_info,
        :timestamp, :correlation_id, :role, :message_id, :additional_context,
        :component_name, :subsession_id, :thread_ts, :parent_ts, :alternative_count, keyword_init: true)

      # Categories that are internal metadata envelopes, not user-visible context
      # items, and therefore not registered in AiAdditionalContextCategory enum.
      INTERNAL_CONTEXT_CATEGORIES = %w[orbit_context permissions_form_context duo_chat_command
        dashboard_context].freeze

      # thread_ts/parent_ts/alternative_count are stamped during blob reconstruction,
      # so they are nil on the header path -- it holds no per-message lineage to
      # attribute. alternative_count is also nil on messages that anchor no turn.
      MESSAGE_KEYS = %w[
        content message_type message_sub_type status tool_info timestamp
        correlation_id role message_id additional_context component_name subsession_id
        thread_ts parent_ts alternative_count
      ].freeze

      # Resolves #duo_messages for a page of events, yielding each with its
      # messages, from three page-level queries instead of several per row.
      def self.batch_duo_messages(presenters)
        # Splitting the page below reads each workflow's newest header; load them all at once.
        ::Ai::DuoWorkflows::Workflow.prime_latest_checkpoint_headers(
          presenters.map(&:workflow).uniq(&:object_id)
        )

        from_blobs, legacy = presenters.partition do |presenter|
          presenter.workflow.incremental_blob_gate.for_graphql?
        end
        legacy.each { |presenter| yield presenter, presenter.duo_messages }
        return if from_blobs.empty?

        workflows = from_blobs.map(&:workflow).uniq(&:object_id)
        ::Ai::DuoWorkflows::Workflow.prime_message_history_context(workflows)

        chain_thread_ts = from_blobs.flat_map do |presenter|
          presenter.workflow.full_ancestor_thread_ts(presenter)
        end.uniq
        blobs_by_workflow_id = ::Ai::DuoWorkflows::Workflow
          .history_blobs_for_workflows(workflows, chain_thread_ts, 'ui_chat_log')

        from_blobs.each do |presenter|
          blobs_by_thread_ts = (blobs_by_workflow_id[presenter.workflow_id] || []).group_by(&:thread_ts)
          yield presenter, presenter.duo_messages_from(blobs_by_thread_ts)
        end
      end

      def self.build_duo_message(message)
        msg = message.slice(*MESSAGE_KEYS)

        if msg['additional_context'].is_a?(Array)
          msg['additional_context'] = msg['additional_context'].reject do |ctx|
            INTERNAL_CONTEXT_CATEGORIES.include?(ctx['category'])
          end
        end

        DuoMessage.new(**msg.symbolize_keys)
      end

      def workflow_status
        event.workflow.status
      end

      def workflow_goal
        event.workflow.goal
      end

      def workflow_definition
        event.workflow.workflow_definition
      end

      def workflow_summary
        event.workflow.summary
      end

      def execution_status
        graph_state = checkpoint_status
        return graph_state unless graph_state.nil? || graph_state == 'Not Started'

        event.workflow.human_status_name.titleize
      end

      # The raw checkpoint served by the `checkpoint` (deprecated 18.7) and
      # `compressedCheckpoint` fields. When the workflow reconstructs from blobs
      # its channel_values are no longer fully embedded in the header, so overlay
      # the reconstructed channels onto the header. Otherwise return the header
      # verbatim. Gated by read_checkpoints_from_blobs? like duoMessages.
      # Overrides the delegated Checkpoint#checkpoint attribute.
      delegator_override :checkpoint
      def checkpoint
        raw = event.checkpoint
        return raw unless raw && read_checkpoints_from_blobs?

        raw.merge('channel_values' => event.workflow.reconstructed_channel_values(event))
      end
      strong_memoize_attr :checkpoint

      def duo_messages
        build_duo_messages(checkpoint_ui_chat_log)
      end

      # #duo_messages against blobs the page loader already fetched.
      def duo_messages_from(blobs_by_thread_ts)
        build_duo_messages(
          event.workflow.channel_message_history_from(event, 'ui_chat_log', blobs_by_thread_ts)
        )
      end

      # The most recent chat message only, for list previews -- reads the newest
      # ui_chat_log blob instead of folding the channel (Workflow#latest_channel_message).
      def last_duo_message
        message = latest_ui_chat_log_message
        return unless message.is_a?(Hash)

        self.class.build_duo_message(message)
      end

      private

      def build_duo_messages(ui_chat_log)
        return [] unless ui_chat_log.is_a?(Array)

        ui_chat_log.filter_map { |message| self.class.build_duo_message(message) if message.is_a?(Hash) }
      end

      def read_checkpoints_from_blobs?
        event.workflow.incremental_blob_gate.for_graphql?
      end

      # ui_chat_log only: on the blob path, the full message history across every
      # compaction group; on the header path, the current checkpoint's embedded
      # array (post-compaction only -- the header cannot span groups). Scoping to
      # one channel avoids decoding the other (often much larger) channels.
      def checkpoint_ui_chat_log
        return event.workflow.channel_message_history(event, 'ui_chat_log') if read_checkpoints_from_blobs?

        event.checkpoint&.dig('channel_values', 'ui_chat_log')
      end

      # status channel only: unlike ui_chat_log, status is a scalar (replace)
      # channel, so Workflow#reconstructed_channel folds its blobs to the latest
      # value and falls back to the header when the workflow wrote no status blobs.
      # Gated by read_checkpoints_from_blobs? like the message channels
      # above; execution_status keeps the nil/'Not Started' fallback to the
      # workflow's own status either way.
      def checkpoint_status
        return event.workflow.reconstructed_channel(event, 'status') if read_checkpoints_from_blobs?

        event.checkpoint&.dig('channel_values', 'status')
      end

      # Newest ui_chat_log entry only: the tail of the latest conversation blob on
      # the blob path, or the tail of the embedded array on the header path.
      def latest_ui_chat_log_message
        delta =
          if read_checkpoints_from_blobs?
            event.workflow.latest_channel_message(event, 'ui_chat_log')
          else
            event.checkpoint&.dig('channel_values', 'ui_chat_log')
          end

        delta.last if delta.is_a?(Array)
      end
    end
  end
end
