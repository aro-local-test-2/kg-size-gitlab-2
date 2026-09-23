import { startFlowPlugin } from './start_flow';
import { basicChatCommandsPlugin } from './basic_chat_commands';
import { compactPlugin } from './compact';
import { tierAccessDeniedPlugin } from './tier_access_denied';
import { flowCommandsPlugin } from './flow_commands';
import { goalPlugin } from './goal';

const PLUGINS = [startFlowPlugin, basicChatCommandsPlugin, compactPlugin, tierAccessDeniedPlugin];

// Kept out of the plugins themselves so a plugin stays a plain description of what it
// contributes, with nothing to stub when testing one.
const FLAGGED_PLUGINS = [
  { plugin: flowCommandsPlugin, flag: 'duoChatFlowCommands' },
  { plugin: goalPlugin, flag: 'duoChatGoalCommand' },
];

/**
 * Registers every plugin bundled with the chat. Must run before the panel mounts:
 * the registry is not reactive, so anything registered later is not picked up.
 *
 * @param {import('../services/plugin_registry').DuoChatPluginRegistry} registry
 */
export function initializePlugins(registry) {
  const enabled = FLAGGED_PLUGINS.filter(({ flag }) => window.gon?.features?.[flag]).map(
    ({ plugin }) => plugin,
  );

  [...PLUGINS, ...enabled].forEach((plugin) => registry.registerPlugin(plugin));
}
