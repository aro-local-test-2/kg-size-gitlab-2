import { s__ } from '~/locale';
import { PROMPT_COMPOSER_ACTIONS } from '../../constants';
import { getGoalFlow } from '../../services/goal_flow';

/* eslint-disable-next-line @gitlab/no-hardcoded-urls -- a slash command, not a URL */
export const GOAL_COMMAND = '/goal';

/**
 * Exported so the toolbar's Goal row dispatches this same command rather than declaring
 * a second copy of it.
 */
export const goalSlashCommand = {
  label: s__('DuoAgenticChat|Goal'),
  value: GOAL_COMMAND,
  description: s__('DuoAgenticChat|Work towards a goal until it is achieved'),
  startOnly: true,
  action: PROMPT_COMPOSER_ACTIONS.START_GOAL,
};

/**
 * `/goal` puts the composer in goal mode, where the prompt is a condition to work
 * towards rather than a question to answer.
 *
 * Hardcoded rather than read off the AI Catalog like `flow_commands` does, since goal is
 * one flow in one configuration. It is still only offered where that flow can run.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const goalPlugin = {
  name: 'goal',
  slashCommands: [
    {
      async getCommands({ apollo, duoChatContext } = {}) {
        const goalFlow = await getGoalFlow({ apollo, projectId: duoChatContext?.projectId });

        return goalFlow ? [goalSlashCommand] : [];
      },
    },
  ],
};
