/* eslint-disable @gitlab/require-i18n-strings */
import isObject from 'lodash-es/isObject';
import { PROMPT_COMPOSER_ACTIONS } from '../../constants';
import { captureExceptionForDuoChat } from '../../observability/sentry_utils';

/**
 * @typedef {Object} SlashCommand
 * @property {string} value - What replaces the typed token in the composer, leading
 *   slash included, e.g. `/compact`. The typed token matches it as a prefix.
 * @property {string} [label] - Shown in the suggestion menu in place of `value`, for
 *   commands whose wording reads better than the token they insert. Defaults to `value`.
 *   Searched as well as `value`: the query matches the start of any word in it, so
 *   `/conv` finds "Compact conversation". The token ends at the first space, so only
 *   one word of a label can be searched at a time.
 * @property {string} description - Rendered under the label in the suggestion menu.
 * @property {boolean} [startOnly] - `true` ties the command to the start of the prompt,
 *   for commands that act on the whole conversation. The menu offers it only there, and
 *   a token found later in the text is read as the user talking about the command
 *   rather than invoking it, so it is left off the prompt.
 * @property {string} [action] - Names what picking the command does, for a command that
 *   changes the composer rather than the text. A value of `PROMPT_COMPOSER_ACTIONS` in
 *   `../../constants`; omitted means `INSERT`, where `value` replaces the typed token
 *   and the user keeps writing. Anything else is dropped here, so it never reaches the
 *   menu.
 *
 *   The actions themselves live in prompt_composer.vue, which is the only thing that
 *   owns the draft they act on -- so this is a name from a fixed set, not a callback a
 *   plugin brings.
 */

const KNOWN_ACTIONS = Object.values(PROMPT_COMPOSER_ACTIONS);

/**
 * @typedef {Object} SlashCommandGroup
 * @property {string} label - Heading the section renders under, and the section's
 *   identity: groups from different plugins that share a label merge into one section.
 *   Translate it once and reuse the same string. Searched like a command label, and a
 *   section whose label matches offers every command in it -- so a label sharing a
 *   word-start with an unrelated command, say "Comments" against `/compact`, surfaces
 *   the whole section on that prefix. Blank or missing drops the whole group, items
 *   included, and reports the omission.
 * @property {SlashCommand[]} items - The commands the section holds. A group with
 *   nothing left in it, because the items were malformed or already taken, is dropped
 *   rather than rendered empty.
 * @property {number} [order] - Where the section sits relative to the other groups,
 *   ascending. Defaults to `0`; ties keep the order the plugins were asked in. When
 *   two plugins merge into one section, the first one's order fixes its position.
 */

/**
 * What a provider hands back: a bare command sits outside every section, a group holds
 * its own. Ungrouped commands render first, above every section.
 *
 * @typedef {SlashCommand|SlashCommandGroup} SlashCommandEntry
 */

/**
 * @typedef {Object} SlashCommandsProvider
 * @property {(dependencies: Object) => Promise<SlashCommandEntry[]>|SlashCommandEntry[]} getCommands -
 *   Awaited, so a provider with nothing to fetch can answer synchronously. Asked for
 *   its commands the first time the user types a `/`, and again whenever the chat
 *   context changes. Receives `{ apollo, duoChatContext }`; both are best-effort, so
 *   guard them: `duoChatContext` is `{}` in mounts that have no state manager above
 *   them, and `apollo` is unusable outside a component tree with an Apollo provider.
 */

/**
 * Tells the two entry shapes apart. `items` is the discriminator, so a group is a
 * group even before its label has been checked.
 *
 * @param {unknown} entry
 * @returns {boolean}
 */
export const isSlashCommandGroup = (entry) => Array.isArray(entry?.items);

/**
 * Every command the entries offer, whichever group it arrived in. For the callers that
 * ask *whether* a command exists rather than where it renders.
 *
 * @param {SlashCommandEntry[]} [entries]
 * @returns {SlashCommand[]}
 */
export const flattenSlashCommands = (entries = []) =>
  entries.flatMap((entry) => (isSlashCommandGroup(entry) ? entry.items : [entry]));

const report = (message) => captureExceptionForDuoChat(new Error(message));

// The same rule the menu applies to a label it is handed directly: a non-blank
// string, or nothing. Kept in step with `labelText` in slash_commands_menu.vue.
const labelText = (label) => (typeof label === 'string' ? label.trim() : '');

const providersOf = (plugins) =>
  plugins.flatMap(({ name, slashCommands: providers = [] }) =>
    providers.map((provider) => ({ plugin: name, provider })),
  );

function isRenderableCommand(command, plugin) {
  // The menu lowercases `value` while filtering, so a valueless command throws
  // inside a computed rather than merely failing to render.
  if (typeof command?.value !== 'string') {
    report(`Duo Chat plugin "${plugin}" contributed a slash command without a value`);
    return false;
  }

  // An action is a name the composer dispatches on, so one it does not implement would
  // leave the command looking like it does something and then doing nothing. Dropped
  // here rather than at the pick, where the menu has already closed over it.
  if (command.action !== undefined && !KNOWN_ACTIONS.includes(command.action)) {
    report(
      `Duo Chat plugin "${plugin}" contributed slash command \`${command.value}\` with an unknown action \`${command.action}\``,
    );
    return false;
  }

  return true;
}

function checkedEntry(entry, plugin) {
  if (!isSlashCommandGroup(entry)) {
    return isRenderableCommand(entry, plugin) ? [entry] : [];
  }

  // Without a label there is no heading to render and no identity to merge on,
  // so this is not a section. Dropped whole rather than dissolved into the
  // ungrouped commands: a group is the unit the plugin declared, and quietly
  // rehoming its commands would paper over the mistake this report exists to
  // surface. Checked before the items, so one report names the actual problem.
  if (!labelText(entry.label)) {
    report(`Duo Chat plugin "${plugin}" contributed a slash command group without a label`);
    return [];
  }

  const items = entry.items.filter((item) => isRenderableCommand(item, plugin));

  return items.length ? [{ ...entry, items }] : [];
}

async function entriesFrom({ plugin, provider }, dependencies) {
  try {
    const entries = await provider.getCommands(dependencies);

    if (!Array.isArray(entries)) {
      report(`Duo Chat plugin "${plugin}" did not return an array of slash commands`);
      return [];
    }

    return entries.flatMap((entry) => checkedEntry(entry, plugin));
  } catch (error) {
    // Reported and dropped: one provider failing must not empty the whole menu.
    captureExceptionForDuoChat(error);
    return [];
  }
}

// First contribution wins, matching the precedence rule the other capabilities follow.
// Left to itself a collision would surface as a Vue duplicate-key warning, because the
// menu keys its options on the command value.
function dedupeByValue(entries) {
  const seen = new Set();

  const keep = ({ value }) => {
    if (!seen.has(value)) {
      seen.add(value);
      return true;
    }

    report(`Duplicate Duo Chat slash command \`${value}\` dropped`);
    return false;
  };

  return entries.flatMap((entry) => {
    if (!isSlashCommandGroup(entry)) return keep(entry) ? [entry] : [];

    const items = entry.items.filter(keep);

    return items.length ? [{ ...entry, items }] : [];
  });
}

export const slashCommands = {
  key: 'slashCommands',

  /**
   * Validates if a slash commands provider is valid.
   *
   * @param {unknown} provider
   * @returns {string[]} One message per contract violation; empty when valid.
   */
  validate(provider) {
    if (!isObject(provider)) {
      return ['must be an object'];
    }

    return typeof provider.getCommands === 'function' ? [] : ['`getCommands` must be a function'];
  },

  /**
   * Asks every plugin for the commands it offers and concatenates the answers into the
   * list the suggestion menu renders. Groups are left standing: merging same-labelled
   * ones and ordering the sections is the menu's job, since both are about layout. One
   * pass per call: callers that ask repeatedly are expected to hold the result themselves.
   *
   * @param {import('../plugin_registry').DuoChatPlugin[]} plugins
   * @param {Object} [dependencies] - Handed to each provider unread. `apollo` is the
   *   caller's vue-apollo wrapper; `duoChatContext` carries the ids the chat is
   *   pointed at.
   * @returns {Promise<SlashCommandEntry[]>}
   */
  async resolve(plugins, dependencies = {}) {
    const perProvider = await Promise.all(
      providersOf(plugins).map((entry) => entriesFrom(entry, dependencies)),
    );

    return dedupeByValue(perProvider.flat());
  },
};
