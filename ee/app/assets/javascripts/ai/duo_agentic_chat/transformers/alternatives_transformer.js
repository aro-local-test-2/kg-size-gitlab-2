import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import { MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER } from '../constants';
import { WorkflowUtils } from '../utils/workflow_utils';

const isUserMessage = (message) => message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user;
const isAssistantMessage = (message) =>
  message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.assistant;

// A clarification answer is a user-authored message, but it does not start a new
// turn (it continues the one that asked the question), so it must not be treated
// as a retry/alternatives anchor.
const isClarificationAnswerMessage = (message) => {
  if (typeof message?.content !== 'string') return false;
  try {
    return JSON.parse(message.content)?.message_sub_type === MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER;
  } catch {
    return false;
  }
};

// The turn's terminator is the last assistant-role message before the next user
// message (or the end of the transcript), mirroring how duo-ui itself picks the
// message it attaches the action bar/pager to.
function findTurnTerminatorIndex(messages, userMessageIndex) {
  let terminatorIndex = -1;

  for (let i = userMessageIndex + 1; i < messages.length; i += 1) {
    const msg = messages[i];
    if (isUserMessage(msg) && !isClarificationAnswerMessage(msg)) break;
    if (isAssistantMessage(msg)) terminatorIndex = i;
  }

  return terminatorIndex;
}

/**
 * Transforms `DuoWorkflowBranch[]` (from the `duoWorkflowBranches` query) into the
 * `{ user_message, agent_responses }[]` shape duo-ui's pager/message components
 * already expect (see duo-ui's duo_chat_message.vue `selectedAlternativeContent`).
 * A branch's `messages` are oldest-first: the first is the resent user message,
 * the rest are its agent response(s).
 */
export function transformBranchesToAlternatives(branches) {
  if (!branches?.length) return [];

  return branches.map((branch) => {
    const [userMessage, ...agentResponses] = WorkflowUtils.transformChatMessages(
      WorkflowUtils.normalizeDuoMessages(branch.messages || []),
    );

    return {
      user_message: userMessage ?? null,
      agent_responses: agentResponses,
    };
  });
}

// Splits `messages` into turns: each turn starts at a non-clarification-answer user
// message and runs up to (excluding) the next one. Any leading messages before the
// first such user message (not expected in practice) are not part of any turn.
function splitIntoTurns(messages) {
  const starts = [];

  messages.forEach((msg, index) => {
    if (isUserMessage(msg) && !isClarificationAnswerMessage(msg)) {
      starts.push(index);
    }
  });

  return starts.map((start, i) => {
    const end = starts[i + 1] ?? messages.length;
    const terminatorIndex = findTurnTerminatorIndex(messages, start);

    return { start, end, userMessage: messages[start], terminatorIndex };
  });
}

// Groups a retry turn with the turn it retries. The resent prompt is stamped
// `is_retry` when the send appends it, and a retry can only ever be appended
// immediately after the turn it retries (retrying is only offered on the latest
// turn, and a new prompt cannot be sent while one is in flight). Content equality
// alone would not be enough: a user re-asking the same question verbatim starts a
// new turn, not another attempt at the previous one.
function groupConsecutiveRetries(turns) {
  const groups = [];

  turns.forEach((turn) => {
    const previousGroup = groups[groups.length - 1];
    const previousTurn = previousGroup?.[previousGroup.length - 1];

    if (
      previousTurn &&
      turn.userMessage.is_retry &&
      turn.userMessage.content &&
      turn.userMessage.content === previousTurn.userMessage.content
    ) {
      previousGroup.push(turn);
    } else {
      groups.push([turn]);
    }
  });

  return groups;
}

function buildAlternativesForGroup(messages, group, branchesByThreadTs) {
  const latestTurn = group[group.length - 1];

  // A retry's turn is appended before any reply arrives, so this runs while it
  // is in flight (or failed without a reply). Collapsing now would drop the
  // previous attempt with no terminator left to reattach it to as an
  // `alternative`, deleting the very message that `retryingMessageId`/
  // `retryFailedMessageId` target for the pending/failed retry-state badge.
  // Treat the in-flight turn as not part of the group yet, so the previous
  // attempt (with its own badge) keeps rendering until a reply lands.
  if (latestTurn.terminatorIndex === -1) {
    const priorTurns = group.slice(0, -1);
    return priorTurns.length
      ? buildAlternativesForGroup(messages, priorTurns, branchesByThreadTs)
      : messages.slice(latestTurn.start, latestTurn.end);
  }

  const olderTurns = group.slice(0, -1);
  // A live retry is always appended after the turn it retries, so only the
  // oldest turn in the group can be the one a GraphQL reload actually loaded
  // (and therefore the only one that can carry `alternative_count`/`thread_ts`).
  const oldestTurn = group[0];

  // Alternatives from attempts made before this session (or before the last reload):
  // only a count is known until `duoWorkflowBranches` has been fetched for this turn.
  const serverCount = oldestTurn.userMessage.alternative_count ?? 0;
  const fetchedBranches = oldestTurn.userMessage.thread_ts
    ? branchesByThreadTs[oldestTurn.userMessage.thread_ts]
    : undefined;
  const historicalAlternatives = fetchedBranches
    ? transformBranchesToAlternatives(fetchedBranches)
    : Array.from({ length: serverCount }, () => ({ user_message: null, agent_responses: [] }));

  // Alternatives from retries made in this live session: their full content is
  // already in `messages`, so no fetch is needed for these. Reversed so the
  // most recent retry comes first, matching the pager's paging direction
  // (index 0 is the current response, higher indices are further in the past).
  const localAlternatives = [...olderTurns].reverse().map((turn) => ({
    user_message: turn.userMessage,
    agent_responses: messages.slice(turn.start + 1, turn.end),
  }));

  // Historical alternatives predate every local turn, so they belong at the
  // end (furthest from the current response).
  const alternatives = [...localAlternatives, ...historicalAlternatives];
  const latestMessages = messages.slice(latestTurn.start, latestTurn.end);

  if (!alternatives.length) {
    return latestMessages;
  }

  // Stamped on the terminator so `onSelectAlternative` can fetch the right
  // branches without having to re-derive the anchor: the turn remaining in
  // `messages` after a live retry is `latestTurn`, but the thread_ts a
  // historical placeholder needs belongs to `oldestTurn`.
  const alternativesThreadTs = oldestTurn.userMessage.thread_ts;
  const relativeTerminatorIndex = latestTurn.terminatorIndex - latestTurn.start;
  return latestMessages.map((msg, i) =>
    i === relativeTerminatorIndex ? { ...msg, alternatives, alternativesThreadTs } : msg,
  );
}

/**
 * Collapses same-question retry turns and attaches an `alternatives` array (in the
 * shape duo-ui already renders) to the terminator message of the turn that remains,
 * so a manual retry's previous attempts become pager entries instead of separate,
 * stacked turns. See the two alternative sources above: `branchesByThreadTs`
 * (lazily fetched, pre-session/pre-reload attempts) and turns already present in
 * `messages` (retries made in the current live session).
 *
 * A factory rather than a bare transformer because the fetched branches live in the
 * host's state; it must also run last in the pipeline, since finding each turn's
 * terminator requires the log every other transformer has already rewritten.
 */
export const alternativesTransformer =
  ({ branchesByThreadTs = {} } = {}) =>
  (messages) => {
    if (!messages?.length) return messages;

    const turns = splitIntoTurns(messages);
    if (!turns.length) return messages;

    const prefix = messages.slice(0, turns[0].start);
    const groups = groupConsecutiveRetries(turns);
    const body = groups.flatMap((group) =>
      buildAlternativesForGroup(messages, group, branchesByThreadTs),
    );

    return [...prefix, ...body];
  };
