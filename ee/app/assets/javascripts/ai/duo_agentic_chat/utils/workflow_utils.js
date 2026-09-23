import { CHAT_MESSAGE_TYPES, GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import {
  DASHBOARD_CONTEXT_CATEGORY,
  PERMISSIONS_FORM_CONTEXT_CATEGORY,
} from '../context/external_context_store';
import { SLASH_COMMAND_CONTEXT_CATEGORY } from '../context/slash_commands_context';

export const WorkflowUtils = {
  parseWorkflowData(response) {
    const [workflow] = response.duoWorkflowWorkflows.nodes ?? [];
    return workflow?.latestCheckpoint ?? null;
  },

  parseWorkflowStatus(response) {
    const [workflow] = response?.duoWorkflowWorkflows?.nodes ?? [];
    return workflow?.status ?? null;
  },

  normalizeDuoMessages(duoMessages) {
    return duoMessages.map(
      ({
        messageType,
        messageSubType,
        toolInfo,
        messageId,
        correlationId,
        additionalContext,
        threadTs,
        parentTs,
        alternativeCount,
        ...rest
      }) => ({
        ...rest,
        message_type: messageType,
        message_sub_type: messageSubType,
        tool_info: toolInfo ? JSON.parse(toolInfo) : toolInfo,
        message_id: messageId,
        correlation_id: correlationId,
        additional_context: additionalContext,
        thread_ts: threadTs,
        parent_ts: parentTs,
        alternative_count: alternativeCount,
      }),
    );
  },

  findLatestTodoToolInfo(messages) {
    for (let i = messages.length - 1; i >= 0; i -= 1) {
      const { tool_info: toolInfo } = messages[i];
      if (toolInfo?.name === 'todo_write' && toolInfo?.args?.todos?.length) {
        return toolInfo;
      }
    }
    return null;
  },

  /**
   * Find the parent_ts of a message, which is the checkpoint a run resumes from to
   * regenerate that message. Returns null when the session stores no incremental
   * checkpoints, in which case the run continues from the latest checkpoint instead.
   */
  findParentTs(messages, messageId) {
    if (!messageId) return null;

    return messages.find((msg) => msg.message_id === messageId)?.parent_ts ?? null;
  },

  /**
   * The reloaded checkpoint is authoritative unless the pending snapshot continues it:
   * the checkpoint's last message also appears in the snapshot, followed by a freshly
   * streamed tail the checkpoint has not persisted yet. Only then keep that tail, so
   * returning to a thread right after a response does not drop that response.
   *
   * Anchoring on the checkpoint's last message (instead of requiring the snapshot to
   * repeat the whole checkpoint) matters because the snapshot is a bounded window of
   * the newest messages: on long threads it starts mid-conversation.
   */
  reconcileLoadedMessages(loaded, pending = []) {
    if (!loaded.length) {
      return pending.length ? [...pending] : loaded;
    }

    const anchorId = loaded.at(-1).message_id;
    if (!anchorId) return loaded;

    const anchorIndex = pending.findIndex((msg) => msg.message_id === anchorId);
    if (anchorIndex === -1) return loaded;

    const tail = pending.slice(anchorIndex + 1);
    return tail.length ? [...loaded, ...tail] : loaded;
  },

  transformChatMessages(uiChatLog) {
    return uiChatLog.map((msg) => {
      const role = [CHAT_MESSAGE_TYPES.agent, CHAT_MESSAGE_TYPES.request].includes(msg.message_type)
        ? GENIE_CHAT_MODEL_ROLES.assistant
        : msg.message_type;

      // Only add extras if user message has additionalContext
      // ref: https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/blob/main/packages/lib_webview_agentic_chat/src/app/chat/utils/chat_message_helpers.js#L80-82
      if (msg.message_type === 'user' && msg.additional_context) {
        const INTERNAL_CATEGORIES = new Set([
          'orbit_context',
          DASHBOARD_CONTEXT_CATEGORY,
          PERMISSIONS_FORM_CONTEXT_CATEGORY,
          SLASH_COMMAND_CONTEXT_CATEGORY,
        ]);
        // eslint-disable-next-line no-param-reassign
        msg.extras = {
          contextItems: msg.additional_context.filter((c) => !INTERNAL_CATEGORIES.has(c.category)),
        };
      }

      return {
        ...msg,
        id: msg.message_id,
        role,
        requestId: msg.message_id,
        message_type: msg.message_type,
      };
    });
  },
};
