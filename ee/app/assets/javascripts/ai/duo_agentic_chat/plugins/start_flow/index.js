import MessageToolStartFlow from './components/message_tool_start_flow.vue';

const REQUIRED_RESPONSE_KEYS = ['flow_name', 'status', 'workflow_id'];

const isStartFlowToolMessage = (message) => {
  if (message.message_sub_type !== 'start_flow') return false;

  try {
    const parsed = JSON.parse(message.tool_info?.tool_response?.content);

    return (
      parsed !== null &&
      typeof parsed === 'object' &&
      REQUIRED_RESPONSE_KEYS.every((key) => key in parsed)
    );
  } catch {
    return false;
  }
};

/** @type {import('../../services/plugin_registry').DuoChatPlugin} */
export const startFlowPlugin = {
  name: 'start_flow',
  messageWidgets: [{ matchMessage: isStartFlowToolMessage, component: MessageToolStartFlow }],
};
