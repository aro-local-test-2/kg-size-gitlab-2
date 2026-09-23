import { isCompactPromptMessage } from '../../../utils/messages_utils';

/**
 * Drops the `/compact` prompt from the log.
 *
 * The command asks for work rather than saying anything, and the transcript already
 * reports the outcome: the divider once a compaction lands, nothing when it does not.
 * Progress is reported outside the log by `compacting_indicator.vue`, which the view
 * shows while the turn runs, so the prompt has no state left to stand in for.
 *
 * @param {Object[]} messages
 * @returns {Object[]}
 */
export const dropCompactPrompt = (messages) => messages.filter((m) => !isCompactPromptMessage(m));
