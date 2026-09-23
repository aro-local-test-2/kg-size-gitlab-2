import { CHAT_MESSAGE_TYPES, GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';

// Loaded messages carry `id`, streamed ones only `message_id`, and a locally added
// prompt only `requestId`; all three derive from the same executor-assigned id.
const messageKey = (message) => message?.id ?? message?.message_id ?? message?.requestId ?? null;

/**
 * Ids of the messages a retry replaces: the resubmitted user message and everything
 * after it. Retrying the same turn again adds the next attempt's ids, so an
 * accumulated set describes every attempt the forked run leaves behind.
 */
export const collectSupersededAttemptIds = (messages = [], promptMessage) => {
  const key = messageKey(promptMessage);
  if (!key) return [];

  const attemptStart = messages.findIndex((msg) => messageKey(msg) === key);
  if (attemptStart === -1) return [];

  return messages.slice(attemptStart).map(messageKey).filter(Boolean);
};

/**
 * The conversation the resumed run actually replays: the flat message log minus
 * the attempts a retry superseded.
 */
export const excludeSupersededMessages = (messages = [], supersededIds) => {
  if (!supersededIds?.size) return messages;

  return messages.filter((msg) => !supersededIds.has(messageKey(msg)));
};

export const getMessagesToProcess = (messages, lastProcessedMessageId) => {
  if (!messages || messages.length === 0) {
    return {
      toProcess: [],
      lastProcessedMessageId: null,
    };
  }

  // First run or log shrank (truncate / reset): process everything.
  const isFirstRunOrReset = lastProcessedMessageId === null;
  let startIndex;
  if (isFirstRunOrReset) {
    startIndex = 0;
  } else {
    startIndex = messages.findIndex((msg) => msg.message_id === lastProcessedMessageId);
    if (startIndex === -1) {
      startIndex = 0;
    }
  }

  const toProcess = messages.slice(startIndex);

  return {
    toProcess,
    lastProcessedMessageId: messages.at(-1).message_id,
  };
};

// Mirrors duo-ui's own isUserMessage, down to the lowercasing, which the package does
// not export: a caller that disagrees with duo-ui about which messages are the user's
// silently fails to override the bubble duo-ui renders for them.
export const isUserMessage = (message) =>
  message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user ||
  message?.message_type?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user;

// A tool call the agent has put to the user, which duo-ui routes to its
// MessageToolApproval card. Whether the card is still actionable depends on where
// the message sits in the log, so that part is left to the caller.
export const isToolApprovalRequest = (message) =>
  message?.message_type === CHAT_MESSAGE_TYPES.request && Boolean(message?.tool_info);

// Anchored so an ordinary prompt like `/compaction of the log` is not mistaken for the
// command, tolerant of a trailing argument because `shouldSubmit: false` leaves the
// token in the composer, and case-insensitive to match how `commandsIn` in
// `services/user_prompt/user_prompt_builder.js` recognises the same token.
const COMPACT_PROMPT = /^\/compact(\s|$)/i;

/**
 * The prompt that asks for a compaction. Shared by the compact plugin, which renders a
 * loading indicator in its place and drops it once it has settled, and by the state
 * manager, which hides duo-ui's generic response loader while it is on screen.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isCompactPromptMessage = (message) =>
  isUserMessage(message) &&
  typeof message.content === 'string' &&
  COMPACT_PROMPT.test(message.content.trim());
