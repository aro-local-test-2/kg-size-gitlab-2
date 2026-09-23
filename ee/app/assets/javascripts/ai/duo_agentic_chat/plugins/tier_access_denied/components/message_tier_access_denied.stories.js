import MessageTierAccessDenied from './message_tier_access_denied.vue';

const baseMessage = {
  message_type: 'agent',
  role: 'assistant',
  message_sub_type: 'tier_access_denied',
  content:
    'Listing epics requires a **GitLab Premium** subscription (or higher).\n\n[Learn more](https://docs.gitlab.com/user/duo_agent_platform/)',
  required_plan: 'premium',
};

const render = (_, { argTypes }) => ({
  components: { MessageTierAccessDenied },
  props: Object.keys(argTypes),
  template: '<message-tier-access-denied v-bind="$props" />',
});

const owner = {
  canBuyAddon: true,
  tierUpgradePath: '/-/subscriptions/upgrade_base_plan?namespace_id=42',
};
const freeAddonCreditsOwner = { canBuyAddon: true, isHandRaiseLeadAvailable: true };
const nonOwner = { canBuyAddon: false };

export default {
  component: MessageTierAccessDenied,
  title: 'ee/ai/duo_agentic_chat/message_tier_access_denied',
};

export const Owner = render.bind({});
Owner.args = { message: baseMessage, ...owner };

export const FreeAddonCreditsOwner = render.bind({});
FreeAddonCreditsOwner.args = { message: baseMessage, ...freeAddonCreditsOwner };

export const NonOwner = render.bind({});
NonOwner.args = { message: baseMessage, ...nonOwner };

export const MissingRequiredPlan = render.bind({});
MissingRequiredPlan.args = {
  message: { ...baseMessage, required_plan: undefined },
  ...owner,
};
