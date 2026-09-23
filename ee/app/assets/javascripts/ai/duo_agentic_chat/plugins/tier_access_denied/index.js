import { MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED } from '../../constants';
import MessageTierAccessDenied from './components/message_tier_access_denied.vue';

const isTierAccessDeniedMessage = (message) =>
  message.message_sub_type === MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED;

// duo-ui replaces the default { message, workingDirectory } props with whatever this
// returns, so `message` must be forwarded explicitly. The rest is the widget's whole
// configuration: it arrives here rather than through inject so the component has one
// source for it.
const tierAccessDeniedProps = (message, _workingDirectory, { duoChatState = {} } = {}) => {
  const {
    canBuyAddon = false,
    tierUpgradePath = '',
    isHandRaiseLeadAvailable = false,
  } = duoChatState;

  return { message, canBuyAddon, tierUpgradePath, isHandRaiseLeadAvailable };
};

/**
 * Telling the user which subscription tier the action they asked for needs.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const tierAccessDeniedPlugin = {
  name: 'tier_access_denied',
  messageWidgets: [
    {
      matchMessage: isTierAccessDeniedMessage,
      component: MessageTierAccessDenied,
      defaultProps: tierAccessDeniedProps,
    },
  ],
};
