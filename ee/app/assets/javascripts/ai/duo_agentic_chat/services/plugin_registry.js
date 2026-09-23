/* eslint-disable @gitlab/require-i18n-strings */
import { captureExceptionForDuoChat } from '../observability/sentry_utils';
import { CAPABILITIES } from './plugin_capabilities';

/**
 * @typedef {Object} DuoChatPlugin
 * @property {string} name - Identifies the contributing feature in validation and
 *   error reports. Conventionally the plugin's directory name, e.g. `start_flow`.
 * @property {import('./plugin_capabilities/message_widgets').MessageWidget[]} [messageWidgets]
 * @property {import('./plugin_capabilities/message_transformers').MessageTransformer[]} [messageTransformers]
 * @property {import('./plugin_capabilities/slash_commands').SlashCommandsProvider[]} [slashCommands]
 */

// `name` identifies the plugin rather than contributing behaviour, so it is skipped
// when matching the remaining fields against capabilities.
const NAME_KEY = 'name';

const hasName = (plugin) => typeof plugin?.name === 'string' && plugin.name.trim() !== '';

// Generic over CAPABILITIES: the engine never names a capability, it only asks each
// one whether the entries filed under its key are well formed.
function pluginErrors(plugin) {
  if (typeof plugin !== 'object' || plugin === null) {
    return ['plugin must be an object'];
  }

  const nameErrors = hasName(plugin) ? [] : ['`name` must be a non-empty string'];

  const capabilityErrors = Object.keys(plugin)
    .filter((key) => key !== NAME_KEY)
    .flatMap((key) => {
      const capability = CAPABILITIES.find((candidate) => candidate.key === key);

      if (!capability) {
        return [`unknown capability \`${key}\``];
      }

      const entries = plugin[key];

      if (!Array.isArray(entries)) {
        return [`\`${key}\` must be an array`];
      }

      return entries.flatMap((entry, index) =>
        capability.validate(entry).map((error) => `${key}[${index}] ${error}`),
      );
    });

  return [...nameErrors, ...capabilityErrors];
}

export class DuoChatPluginRegistry {
  #plugins = [];

  /** @param {DuoChatPlugin} plugin */
  registerPlugin(plugin) {
    const errors = pluginErrors(plugin);

    if (errors.length) {
      // Dropped, not thrown: one malformed contribution must not stop the panel from
      // initializing. In development the Sentry wrapper logs to the console, so the
      // author still sees it.
      // Naming the plugin is the difference between a report a reviewer can act on
      // and one that only says some field somewhere is wrong.
      const label = hasName(plugin) ? ` "${plugin.name}"` : '';

      captureExceptionForDuoChat(
        new Error(`Invalid Duo Chat plugin${label}: ${errors.join('; ')}`),
      );
      return;
    }

    this.#plugins.push(plugin);
  }

  /** @returns {DuoChatPlugin[]} */
  get plugins() {
    return [...this.#plugins];
  }
}
