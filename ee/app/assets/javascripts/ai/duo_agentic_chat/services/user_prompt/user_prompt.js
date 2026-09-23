/**
 * @typedef {import('../plugin_capabilities/slash_commands').SlashCommand} SlashCommand
 */

/**
 * @typedef {Object} PromptAttachment
 * @property {string} id
 * @property {string} filename
 * @property {string} mimeType
 * @property {number} byteSize
 * @property {string} data - base64 payload, without the data URL prefix
 * @property {string} previewUrl - data URL, for the composer's thumbnail only
 */

/**
 * A plain, JSON-serializable object rather than a class instance: prompt_queue.vue
 * persists queued prompts to sessionStorage, and a class instance would not survive
 * that round trip.
 *
 * @typedef {Object} UserPrompt
 * @property {string} text
 * @property {SlashCommand[]} slashCommands
 * @property {{ consumerId: number }|null} goalFlow - Set once `START_GOAL` has run,
 *   making `text` a goal to work towards rather than a prompt to answer, and naming the
 *   flow that works towards it. Composer state rather than a command, since the menu and
 *   the toolbar both run that action.
 * @property {PromptAttachment[]} attachments - Mapped to `additional_context` items by
 *   the state manager. A queued prompt never carries any: sessionStorage cannot hold
 *   the payloads, so the composer refuses to queue a draft that has them.
 */

/**
 * @param {Partial<UserPrompt>} [parts]
 * @returns {UserPrompt}
 */
export function createUserPrompt({
  text = '',
  slashCommands = [],
  goalFlow = null,
  attachments = [],
} = {}) {
  return Object.freeze({
    text,
    // Copied, so a caller mutating its own array afterwards cannot reach into this prompt.
    slashCommands: Object.freeze([...slashCommands]),
    goalFlow,
    attachments: Object.freeze([...attachments]),
  });
}

export const EMPTY_USER_PROMPT = createUserPrompt();
