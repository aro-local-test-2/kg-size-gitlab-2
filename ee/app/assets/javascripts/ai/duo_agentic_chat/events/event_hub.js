import { CHAT_MESSAGE_TYPES } from 'ee/ai/constants';
import { processWorkflowMessage } from '../websocket/workflow_utils';
import eventHub from './event_hub_instance';

export const DUO_CHAT_TOOL_REQUESTED_EVENT = 'duo:tool-requested';
export const DUO_CHAT_TOOL_COMPLETED_EVENT = 'duo:tool-completed';
export const DUO_CHAT_TOOL_FAILURE_EVENT = 'duo:tool-failure';

let lastProcessedMessageId = null;

export function subscribeToEvent(event, handler) {
  eventHub.$on(event, handler);
  return {
    dispose() {
      eventHub.$off(event, handler);
    },
  };
}

export function initDuoAgenticChatEventHub(streamManager) {
  const openSubscription = streamManager.subscribe('open', () => {
    lastProcessedMessageId = null;
  });

  const messageSubscription = streamManager.subscribe('message', (event) => {
    const workflowData = processWorkflowMessage(event, lastProcessedMessageId);
    if (!workflowData) return;

    lastProcessedMessageId = workflowData.lastProcessedMessageId;

    workflowData.messages.forEach((msg) => {
      // A failed tool call carries no tool_response at all, so the outcome has to
      // come off the message rather than out of tool_info.
      const {
        message_id: messageId,
        message_type: messageType,
        tool_info: toolInfo,
        status,
        content,
      } = msg || {};

      if (!toolInfo?.name) return;

      const toolName = toolInfo.name;

      if (messageType === CHAT_MESSAGE_TYPES.request) {
        eventHub.$emit(DUO_CHAT_TOOL_REQUESTED_EVENT, { messageId, name: toolName });
        return;
      }

      if (messageType !== CHAT_MESSAGE_TYPES.tool) return;

      if (status === 'success') {
        eventHub.$emit(DUO_CHAT_TOOL_COMPLETED_EVENT, {
          messageId,
          name: toolName,
          args: toolInfo.args,
        });
      } else if (status === 'failure') {
        eventHub.$emit(DUO_CHAT_TOOL_FAILURE_EVENT, {
          messageId,
          name: toolName,
          content,
        });
      }
    });
  });

  return {
    dispose() {
      openSubscription.dispose();
      messageSubscription.dispose();
      lastProcessedMessageId = null;
    },
  };
}
