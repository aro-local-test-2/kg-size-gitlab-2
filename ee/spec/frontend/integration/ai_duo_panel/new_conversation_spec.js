import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { waitFor, screen } from '@testing-library/vue';
import { duoChatGlobalState, CHAT_MODES } from 'ee/ai/state';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import AiPanel from 'ee/ai/components/ai_panel.vue';
import { createApolloProvider } from 'ee/ai/graphql';
import { createRouter } from 'ee/ai/duo_agents_platform/router/ai_panel_router';
import createStore from 'ee/ai/tanuki_bot/store';
import { fullMount, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  getConfiguredAgents,
  getWorkflowLatestCheckpoint,
  installDuoAIPanelHandlers,
} from './test_support/api_handlers';

Vue.use(VueApollo);

const chatConfiguration = {
  agenticTitle: 'GitLab Duo Agentic Chat',
  classicTitle: 'GitLab Duo Chat',
  autoExpand: true,
  defaultProps: {
    isAgenticAvailable: true,
    isClassicAvailable: false,
    namespaceId: 'gid://gitlab/Namespace/1',
    defaultNamespaceSelected: true,
  },
};

const targetAgent = getConfiguredAgents.agents()[1].item;

// Marks the hydrated conversation on screen. The last user message is used
// rather than the first, because the first doubles as the workflow title and so
// also renders in the panel header.
const { content: loadedMessage } = getWorkflowLatestCheckpoint
  .messages()
  .filter(({ messageType }) => messageType === 'user')
  .at(-1);
const targetAgentId = targetAgent.id;

describe('Starting a new conversation while a chat thread is loaded', () => {
  let router;
  let store;

  const findNewAgentToggle = () => screen.queryByTestId('add-new-agent-toggle');
  const findTargetAgentItem = () => screen.queryByTestId(`listbox-item-${targetAgentId}`);
  const findChatMessages = () => screen.queryByTestId('chat-messages');

  const seedActiveWorkflow = () => {
    sessionStorage.setItem(
      DUO_CURRENT_WORKFLOW_STORAGE_KEY,
      JSON.stringify({ workflowId: getWorkflowLatestCheckpoint.workflow().id }),
    );
  };

  const mountPanel = () => {
    router = createRouter('/', 'user', chatConfiguration);
    const apolloProvider = createApolloProvider({ autoExpand: true });
    store = createStore();

    fullMount(AiPanel, {
      store,
      router,
      apolloProvider,
      propsData: {
        chatDisabledReason: '',
        shouldShowBlockedState: false,
      },
      provide: {
        isSidePanelView: true,
        chatConfiguration,
        badgeType: 'beta',
      },
    });
  };

  const clearPanelStorage = () => {
    window.localStorage.clear();
    window.sessionStorage.clear();
    duoChatGlobalState.chatMode = CHAT_MODES.AGENTIC;
  };

  beforeEach(() => {
    clearPanelStorage();
    installDuoAIPanelHandlers();
  });

  afterEach(() => {
    clearPanelStorage();
  });

  describe('when an agent is selected from an existing conversation', () => {
    beforeEach(async () => {
      seedActiveWorkflow();
      mountPanel();

      await waitFor(() => {
        expect(findChatMessages().textContent).toContain(loadedMessage);
      });

      expect(screen.queryByTestId('gl-duo-chat-empty-state')).toBe(null);

      const toggle = await waitForElement(findNewAgentToggle);
      await waitForElement(() => screen.queryByTestId('chat-subheader'));

      expect(screen.queryByTestId('chat-subheader').innerHTML).not.toContain(targetAgent.name);

      toggle.querySelector('button').click();

      const item = await waitForElement(findTargetAgentItem);
      item.click();
    });

    it('clears the old messages and shows the empty state', async () => {
      await waitFor(() => {
        expect(screen.queryByTestId('gl-duo-chat-empty-state')).not.toBe(null);
        expect(findChatMessages().textContent).not.toContain(loadedMessage);
      });
    });

    it('switches to the selected agent', async () => {
      await waitFor(() => {
        expect(screen.queryByTestId('chat-subheader').innerHTML).toContain(targetAgent.name);
      });
    });
  });
});
