import { initializePlugins } from 'ee/ai/duo_agentic_chat/plugins';
import { startFlowPlugin } from 'ee/ai/duo_agentic_chat/plugins/start_flow';
import { basicChatCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/basic_chat_commands';
import { compactPlugin } from 'ee/ai/duo_agentic_chat/plugins/compact';
import { tierAccessDeniedPlugin } from 'ee/ai/duo_agentic_chat/plugins/tier_access_denied';
import { flowCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/flow_commands';
import { goalPlugin } from 'ee/ai/duo_agentic_chat/plugins/goal';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';

describe('initializePlugins', () => {
  const BUNDLED = [startFlowPlugin, basicChatCommandsPlugin, compactPlugin, tierAccessDeniedPlugin];

  const registerWith = (features = {}) => {
    window.gon = { features };
    const registry = new DuoChatPluginRegistry();

    initializePlugins(registry);

    return registry.plugins;
  };

  it('registers every bundled plugin into the given registry', () => {
    expect(registerWith()).toEqual(BUNDLED);
  });

  describe('a plugin behind a feature flag', () => {
    it('is registered when its flag is on', () => {
      expect(registerWith({ duoChatFlowCommands: true })).toEqual([...BUNDLED, flowCommandsPlugin]);
    });

    it('is left out when its flag is off', () => {
      expect(registerWith({ duoChatFlowCommands: false })).not.toContain(flowCommandsPlugin);
    });

    it('registers the goal command behind its own flag', () => {
      expect(registerWith({ duoChatGoalCommand: true })).toEqual([...BUNDLED, goalPlugin]);
      expect(registerWith({ duoChatGoalCommand: false })).not.toContain(goalPlugin);
    });

    it('is left out when there are no flags at all', () => {
      window.gon = undefined;
      const registry = new DuoChatPluginRegistry();

      initializePlugins(registry);

      expect(registry.plugins).toEqual(BUNDLED);
    });
  });
});
