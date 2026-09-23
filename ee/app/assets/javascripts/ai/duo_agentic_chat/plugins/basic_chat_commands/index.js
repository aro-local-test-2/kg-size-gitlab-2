import { s__ } from '~/locale';
import { GENIE_CHAT_NEW_MESSAGE } from 'ee/ai/constants';
import { PROMPT_COMPOSER_ACTIONS } from '../../constants';

/**
 * The commands the chat answers itself, without a feature behind them.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const basicChatCommandsPlugin = {
  name: 'basic_chat_commands',
  slashCommands: [
    {
      getCommands: () => [
        {
          value: GENIE_CHAT_NEW_MESSAGE,
          description: s__('DuoAgenticChat|Start a new conversation'),
          startOnly: true,
          action: PROMPT_COMPOSER_ACTIONS.INSERT,
        },
      ],
    },
  ],
};
