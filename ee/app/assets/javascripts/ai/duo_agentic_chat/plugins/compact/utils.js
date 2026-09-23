/**
 * A compaction message, whether or not anything was actually summarized. Shared by the
 * widget that renders the divider and the transformer that drops the no-op ones, so the
 * two cannot drift apart on what counts as a compaction.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isCompactionMessage = (message) => message?.message_sub_type === 'compaction';
