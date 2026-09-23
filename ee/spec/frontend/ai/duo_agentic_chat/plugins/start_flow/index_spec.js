import { startFlowPlugin } from 'ee/ai/duo_agentic_chat/plugins/start_flow';
import MessageToolStartFlow from 'ee/ai/duo_agentic_chat/plugins/start_flow/components/message_tool_start_flow.vue';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { MOCK_START_FLOW_TOOL_MESSAGE } from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

describe('startFlowPlugin', () => {
  const [{ matchMessage }] = startFlowPlugin.messageWidgets;

  const startFlowMessage = (content) => ({
    message_sub_type: 'start_flow',
    tool_info: { tool_response: { content } },
  });

  // Guards the shipped plugin against its own contract: the registry drops anything
  // malformed, so a broken descriptor would otherwise only show up as a missing widget.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(startFlowPlugin);

    expect(registry.plugins).toEqual([startFlowPlugin]);
  });

  it('is named after its plugin directory', () => {
    expect(startFlowPlugin.name).toBe('start_flow');
  });

  it('renders start_flow messages with MessageToolStartFlow', () => {
    expect(startFlowPlugin.messageWidgets).toEqual([
      { matchMessage: expect.any(Function), component: MessageToolStartFlow },
    ]);
  });

  describe('matchMessage', () => {
    it('returns true when content is a JSON object with flow_name, status, and workflow_id', () => {
      expect(matchMessage(MOCK_START_FLOW_TOOL_MESSAGE)).toBe(true);
    });

    it('returns false when message_sub_type is not start_flow', () => {
      expect(matchMessage({ message_sub_type: 'other' })).toBe(false);
      expect(matchMessage({ message_sub_type: undefined })).toBe(false);
    });

    it('returns false when content is null', () => {
      expect(matchMessage(startFlowMessage(null))).toBe(false);
    });

    it('returns false when content is not valid JSON', () => {
      expect(matchMessage(startFlowMessage('not json'))).toBe(false);
    });

    it('returns false when content is a JSON primitive, not an object', () => {
      expect(matchMessage(startFlowMessage('"a string"'))).toBe(false);
      expect(matchMessage(startFlowMessage('42'))).toBe(false);
    });

    it('returns false when content is missing flow_name', () => {
      expect(
        matchMessage(startFlowMessage(JSON.stringify({ status: 'started', workflow_id: 1 }))),
      ).toBe(false);
    });

    it('returns false when content is missing status', () => {
      expect(
        matchMessage(startFlowMessage(JSON.stringify({ flow_name: 'fix/v1', workflow_id: 1 }))),
      ).toBe(false);
    });

    it('returns false when content is missing workflow_id', () => {
      expect(
        matchMessage(startFlowMessage(JSON.stringify({ flow_name: 'fix/v1', status: 'started' }))),
      ).toBe(false);
    });

    it('returns false when tool_info is absent', () => {
      expect(matchMessage({ message_sub_type: 'start_flow' })).toBe(false);
    });
  });
});
