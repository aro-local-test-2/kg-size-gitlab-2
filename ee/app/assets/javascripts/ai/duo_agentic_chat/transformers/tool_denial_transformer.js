import { CHAT_MESSAGE_TYPES } from 'ee/ai/constants';
import { isToolApprovalRequest } from '../utils/messages_utils';

// Mirrors the backend ToolStatus enum value consumed by duo-ui's MessageToolApproval card.
const TOOL_STATUS_CANCELLED = 'cancelled';

const isExecutedTool = (msg) =>
  msg.message_type === CHAT_MESSAGE_TYPES.tool && Boolean(msg.tool_info);

/**
 * Determines the index where the trailing run of pending approval requests begins.
 * These are the consecutive request+tool_info messages at the very end of the log
 * that are still awaiting the user's decision. They must be left untouched so the
 * interactive approval widget keeps rendering (mirrors duo-ui's pendingToolApprovals).
 */
const pendingApprovalStartIndex = (messages) => {
  let index = messages.length;
  while (index > 0 && isToolApprovalRequest(messages[index - 1])) {
    index -= 1;
  }
  return index;
};

/**
 * Rewrites denied tool approval requests into finalized "cancelled" request cards.
 *
 * The backend never emits a tool message for a denied request, so without this the
 * chat log would only keep the "Tool X requires approval..." text and drop the card
 * entirely. An approved request, by contrast, is followed by an executed tool message
 * sharing the same tool_info.name. We use that to tell the two apart:
 *
 *   - pending  → request is in the trailing approval run            → leave as-is
 *   - approved → a later, unclaimed tool message matches its name   → leave as-is
 *   - denied   → neither of the above                               → set status to
 *                'cancelled' so duo-ui's MessageToolApproval renders the finalized card
 *
 * Since duo-ui routes request-type messages directly to MessageToolApproval (as of
 * @gitlab/duo-ui v15.41), the message_type stays 'request' — only the status changes.
 *
 * Matching by name (correlation_id is always null) and skipping requests already
 * claimed by another tool resolves repeated same-name tools in order, the same
 * approach used by the clarificationQuestionTransformer. So each executed tool
 * claims the nearest preceding unclaimed request of its name; if the agent asks
 * for the same tool twice and both are approved, the two tools claim the two
 * requests one-to-one instead of both landing on the nearer request.
 */
export const toolDenialTransformer = (messages) => {
  const pendingStart = pendingApprovalStartIndex(messages);
  const approvedRequestIndices = new Set();

  for (let toolIndex = messages.length - 1; toolIndex >= 0; toolIndex -= 1) {
    const toolMessage = messages[toolIndex];

    if (!isExecutedTool(toolMessage)) {
      continue;
    }

    for (let requestIndex = toolIndex - 1; requestIndex >= 0; requestIndex -= 1) {
      const request = messages[requestIndex];

      if (
        requestIndex >= pendingStart ||
        !isToolApprovalRequest(request) ||
        approvedRequestIndices.has(requestIndex) ||
        request.tool_info.name !== toolMessage.tool_info.name
      ) {
        continue;
      }

      approvedRequestIndices.add(requestIndex);
      break;
    }
  }

  return messages.map((msg, index) => {
    if (index >= pendingStart || !isToolApprovalRequest(msg)) {
      return msg;
    }

    if (approvedRequestIndices.has(index)) {
      return msg;
    }

    return {
      ...msg,
      status: TOOL_STATUS_CANCELLED,
    };
  });
};
