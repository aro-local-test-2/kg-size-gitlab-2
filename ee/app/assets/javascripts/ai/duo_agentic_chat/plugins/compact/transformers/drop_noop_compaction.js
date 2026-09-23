import { isCompactionMessage } from '../utils';

// A compaction that summarized nothing marks no boundary, so the divider would announce a
// change that never happened. A missing count is read the same as zero: the question is
// whether anything was summarized.
const isNoopCompaction = (message) =>
  isCompactionMessage(message) && !(message.tool_info?.args?.messages_summarized > 0);

/**
 * Drops compactions that summarized nothing.
 *
 * Dropped rather than hidden at render time: duo-ui wraps every message in its own flex
 * item, so a widget that renders nothing still leaves that wrapper behind and doubles the
 * gap between the messages either side of it.
 *
 * @param {Object[]} messages
 * @returns {Object[]}
 */
export const dropNoopCompaction = (messages) => messages.filter((m) => !isNoopCompaction(m));
