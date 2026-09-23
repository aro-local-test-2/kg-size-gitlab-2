import Vue from 'vue';
import VueApollo from 'vue-apollo';
import DuoAgenticStateManager from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_state_manager.vue';
import { createRouter } from 'ee/ai/duo_agents_platform/router/ai_panel_router';
import { AGENT_PLATFORM_SIDE_PANEL_PAGE } from 'ee/ai/duo_agents_platform/constants';
import DuoChat from 'ee/ai/tanuki_bot/components/duo_chat_state_manager.vue';
import { activeWorkItemIds } from '~/work_items/utils';
import { initLazyHandRaiseLeadModal } from 'ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal';
import { setAgenticMode } from 'ee/ai/utils';
import { parseChatPanelConfig, buildChatConfiguration } from 'ee/ai/utils/chat_panel_config';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat';
import { initializePlugins } from 'ee/ai/duo_agentic_chat/plugins';
import store from './tanuki_bot/store';
import { createApolloProvider } from './graphql';
import AIPanel from './components/ai_panel.vue';

export function initDuoPanel() {
  const el = document.getElementById('duo-chat-panel');

  if (!el) {
    return false;
  }

  const isHandRaiseLeadAvailable = initLazyHandRaiseLeadModal(el);

  const config = parseChatPanelConfig(el, { isHandRaiseLeadAvailable });
  const { scope, shouldShowBlockedState } = config;

  if (config.forceAgenticModeForCoreDuoUsers) {
    setAgenticMode({ agenticMode: true, saveCookie: true });
  }

  // Registered before the panel mounts: the registry is not reactive, so a plugin
  // added after this point would not be picked up.
  const duoChatPluginRegistry = new DuoChatPluginRegistry();
  initializePlugins(duoChatPluginRegistry);

  Vue.use(VueApollo);

  const apolloProvider = createApolloProvider();

  // Configure chat-specific values in a single configuration object
  const chatConfiguration = {
    agenticComponent: DuoAgenticStateManager,
    classicComponent: DuoChat,
    ...buildChatConfiguration(config),
  };

  const router = createRouter('/', AGENT_PLATFORM_SIDE_PANEL_PAGE, {
    ...chatConfiguration,
    autoExpand: config.autoExpand,
  });

  return new Vue({
    el,
    name: 'DuoPanel',
    store: store(),
    router,
    apolloProvider,
    provide: {
      isSidePanelView: true,
      webSearchAllowedForGroup: config.webSearchAllowedForGroup,
      // Inject chat configuration directly to components that need it
      chatConfiguration,
      duoChatPluginRegistry,
    },
    render(createElement) {
      const latestActiveWorkItemId = activeWorkItemIds.value[activeWorkItemIds.value.length - 1];
      return createElement(AIPanel, {
        props: {
          name: 'AiPanel',
          userId: scope.userId,
          projectId: scope.projectId,
          namespaceId: scope.namespaceId,
          rootNamespaceId: scope.rootNamespaceId,
          resourceId: latestActiveWorkItemId ?? scope.resourceId,
          metadata: scope.metadata,
          userModelSelectionEnabled: scope.userModelSelectionEnabled,
          chatDisabledReason: scope.chatDisabledReason,
          shouldShowBlockedState,
        },
      });
    },
  });
}
