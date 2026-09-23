/*
Additional context contributed by the slash command a prompt invokes.

A slash command is offered by a plugin, but what it adds to the turn is sent by the chat
core, so that translation lives here rather than in the plugin, which keeps the core free
of imports from individual plugins. A holding place: once extending the turn's context is
a plugin capability, each command's contribution moves back to the plugin offering it.

Flow commands and goal mode are the only contributors today. Both start a flow, so both
produce the same envelope; they differ only in where the flow and the goal come from.
*/
import { GOAL_FLOW_MODE } from '../services/goal_flow';

/**
 * Category of the additional context item that tells the Duo Workflow Service to run a
 * flow instead of asking the model what to do.
 *
 * It rides additional context because a dedicated field on the start request would not
 * survive Workhorse, which drops proto fields it does not know. Internal envelopes must
 * also be listed in `INTERNAL_CONTEXT_CATEGORIES` on the Rails side, or reading the
 * checkpoint back fails on the non-null `AiAdditionalContextCategory` enum.
 */
export const SLASH_COMMAND_CONTEXT_CATEGORY = 'duo_chat_command';

/**
 * The envelope that starts a flow. Addressed by `consumerId`, so the model is never
 * asked which flow was meant.
 *
 * @param {Object} flow
 * @param {number} flow.consumerId
 * @param {string} [flow.goal] - What to work towards.
 * @param {string} [flow.mode] - A configuration the flow declares.
 * @returns {Object} One context item.
 */
const flowContextItem = ({ consumerId, goal, mode }) => ({
  category: SLASH_COMMAND_CONTEXT_CATEGORY,
  content: JSON.stringify({
    command: 'flow',
    ai_catalog_item_consumer_id: consumerId,
    goal: goal || null,
    // Left out rather than sent as null: Rails rejects a mode the flow does not declare.
    ...(mode ? { mode } : {}),
  }),
  metadata: '{}',
});

/**
 * What a goal prompt or a flow command adds to the turn it starts.
 *
 * The prompt builder has already matched the command and handed back the whole object,
 * `consumerId` and all, so this only has to say what that means for the request. The
 * flow is addressed by that id, which is what keeps the command deterministic: the model
 * is never asked which flow was meant.
 *
 * A flow command is identified by `consumerId` rather than by the `/flow:` prefix, so it
 * survives flows being given author-supplied command names, which is the intended fix
 * for two flows slugifying alike.
 *
 * @param {import('../services/user_prompt/user_prompt').UserPrompt} userPrompt
 * @returns {Object[]} One context item, or none.
 */
export const slashCommandContextFor = ({ text = '', slashCommands = [], goalFlow = null } = {}) => {
  // The action took the token out, so the whole prompt is the goal, and the mode is what
  // picks the config that works towards it.
  if (goalFlow) {
    return [
      flowContextItem({ consumerId: goalFlow.consumerId, goal: text.trim(), mode: GOAL_FLOW_MODE }),
    ];
  }

  const command = slashCommands.find(({ consumerId }) => consumerId);
  if (!command) return [];

  const trimmed = text.trim();
  if (!trimmed.toLowerCase().startsWith(command.value.toLowerCase())) return [];

  // No mode: a flow reached this way runs whatever config it declares by default.
  return [
    flowContextItem({
      consumerId: command.consumerId,
      goal: trimmed.slice(command.value.length).trim(),
    }),
  ];
};
