import { basicChatCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/basic_chat_commands';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';

describe('basicChatCommandsPlugin', () => {
  // The registry drops anything malformed, so a broken descriptor would otherwise only
  // show up as a menu with no commands in it.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(basicChatCommandsPlugin);

    expect(registry.plugins).toEqual([basicChatCommandsPlugin]);
  });

  it('is named after its plugin directory', () => {
    expect(basicChatCommandsPlugin.name).toBe('basic_chat_commands');
  });

  it('offers the commands the chat handles itself', async () => {
    const commands = await basicChatCommandsPlugin.slashCommands[0].getCommands({});

    expect(commands).toEqual([
      {
        value: '/new',
        description: 'Start a new conversation',
        startOnly: true,
        action: 'insert',
      },
    ]);
  });
});
