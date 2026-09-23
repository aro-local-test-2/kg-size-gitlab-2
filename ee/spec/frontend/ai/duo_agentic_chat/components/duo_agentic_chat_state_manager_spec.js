import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import VueApollo from 'vue-apollo';
import { parseDocument } from 'yaml';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import ChatLoadingState from 'ee/ai/components/chat_loading_state.vue';
import {
  getInstanceSlots,
  mountExtended,
  shallowMountExtended,
} from 'helpers/vue_test_utils_helper';
import { setAgenticMode } from 'ee/ai/utils';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import setWindowLocation from 'helpers/set_window_location_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { duoChatGlobalState } from 'ee/ai/state';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import storeMutations from 'ee/ai/tanuki_bot/store/mutations';
import * as storeActions from 'ee/ai/tanuki_bot/store/actions';
import getAiChatContextPresets from 'ee/ai/graphql/get_ai_chat_context_presets.query.graphql';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import getConfiguredAgents from 'ee/ai/graphql/get_configured_agents.query.graphql';
import getAgentFlowConfig from 'ee/ai/graphql/get_agent_flow_config.query.graphql';
import getFoundationalChatAgents from 'ee/ai/graphql/get_foundational_chat_agents.graphql';
import getFlowStatus from 'ee/ai/graphql/get_flow_status.query.graphql';
import duoWorkflowMutation from 'ee/ai/graphql/duo_workflow.mutation.graphql';
import updateWebSearchMutation from 'ee/ai/graphql/update_duo_workflow_web_search.mutation.graphql';
import getWorkflowLatestCheckpointQuery from 'ee/ai/graphql/get_workflow_latest_checkpoint.query.graphql';
import getWorkflowBranchesQuery from 'ee/ai/graphql/get_workflow_branches.query.graphql';
import getGitlabCreditsStatusQuery from 'ee/ai/graphql/get_gitlab_credits_status.query.graphql';
import AgenticModeToggle from 'ee/ai/duo_agentic_chat/components/agentic_mode_toggle.vue';
import ChatModelSelector from 'ee/ai/duo_agentic_chat/components/model_selection/chat_model_selector.vue';
import PromptInputActions from 'ee/ai/duo_agentic_chat/components/prompt_input_actions.vue';
import TurnProgress from 'ee/ai/duo_agentic_chat/components/turn_progress.vue';
import DuoAgenticChatHeader from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_header.vue';
import DuoAgenticChatStateManager from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_state_manager.vue';
import DuoAgenticChatView from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_view.vue';
import NoNamespaceEmptyState from 'ee/ai/duo_agentic_chat/components/no_namespace_empty_state.vue';
import NoCreditsEmptyState from 'ee/ai/duo_agentic_chat/components/no_credits_empty_state.vue';
import ActiveTrialOrSubscriptionEmptyState from 'ee/ai/duo_agentic_chat/components/active_trial_or_subscription_empty_state.vue';
import ThreadLoadErrorEmptyState from 'ee/ai/duo_agentic_chat/components/thread_load_error_empty_state.vue';
import ThreadLoadingEmptyState from 'ee/ai/duo_agentic_chat/components/thread_loading_empty_state.vue';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import { SystemContextManager } from 'ee/ai/duo_agentic_chat/context/system_context_manager';
import { registerExternalContextProvider } from 'ee/ai/duo_agentic_chat/context/external_context_store';
import { runMessageTransformers } from 'ee/ai/duo_agentic_chat/transformers/index';
import {
  getCurrentModel,
  getDefaultModel,
  getModel,
  saveModel,
  isModelSelectionDisabled as checkModelSelectionDisabled,
} from 'ee/ai/duo_agentic_chat/utils/model_selection_utils';
import * as WorkflowSocketUtils from 'ee/ai/duo_agentic_chat/websocket/workflow_utils';
import {
  loadThreadSnapshot,
  clearThreadSnapshot,
} from 'ee/ai/duo_agentic_chat/utils/chat_thread_snapshot';
import {
  loadWebSearchPreference,
  saveWebSearchPreference,
} from 'ee/ai/duo_agentic_chat/utils/web_search_preference';
import CreditsExhaustedAlert from 'ee/ai/duo_agentic_chat/components/credits_exhausted_alert.vue';
import ConnectionErrorAlert from 'ee/ai/duo_agentic_chat/components/connection_error_alert.vue';
import { getSessionStorageValue, saveSessionStorageValue } from '~/lib/utils/local_storage';
import ModelSelectDropdown from 'ee/ai/shared/feature_settings/model_select_dropdown.vue';
import PromptQueue from 'ee/ai/duo_agentic_chat/components/prompt_queue.vue';
import { createUserPrompt, EMPTY_USER_PROMPT } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import {
  GENIE_CHAT_RESET_MESSAGE,
  GENIE_CHAT_CLEAR_MESSAGE,
  GENIE_CHAT_NEW_MESSAGE,
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_WORKFLOW_STATUS_STOPPED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
  DUO_WORKFLOW_ADDITIONAL_CONTEXT_REPOSITORY,
  DUO_CURRENT_WORKFLOW_STORAGE_KEY,
  DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY,
  DUO_WORKFLOW_STATUS_RUNNING,
  DUO_WORKFLOW_STATUS_FINISHED,
  DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
  DUO_WORKFLOW_CHAT_DEFINITION,
  DUO_WORKFLOW_NEW_CHAT_DEFINITION,
} from 'ee/ai/constants';
import {
  AGENTIC_CHAT_SHOW_ROUTE,
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_HISTORY_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { workflowStreamFactory } from 'ee/ai/duo_agentic_chat/websocket/workflow_stream_factory';
import { getCookie } from '~/lib/utils/common_utils';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  FEEDBACK_TRACKING_EVENT,
  CHAT_TRACKING_EVENT,
  TRIGGER_SOURCE_WEB_CHAT,
  TRIGGER_SOURCE_WEB_UI,
  NO_RESOURCE_PERMISSIONS,
  RETRY_STATE,
} from 'ee/ai/duo_agentic_chat/constants';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
import { catalogAgentsFromResponse } from 'ee/ai/duo_agentic_chat/utils/agent_utils';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import {
  MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE,
  MOCK_MODEL_LIST_ITEMS,
  MOCK_NEW_MODEL_SELECTION_LIST_ITEMS,
  MOCK_GITLAB_DEFAULT_MODEL_ITEM,
  MOCK_CONFIGURED_AGENTS_RESPONSE,
  MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE,
  MOCK_FLOW_CONFIG_RESPONSE,
  MOCK_FETCHED_FOUNDATIONAL_AGENT,
  MOCK_FLOW_AGENT_CONFIG,
  DUO_CHAT_AGENT_MOCK,
  DUO_FOUNDATIONAL_AGENT_MOCK,
} from './mock_data';

jest.mock('~/behaviors/markdown/render_gfm', () => {
  const actual = jest.requireActual('~/behaviors/markdown/render_gfm');
  return { ...actual, renderGFM: jest.fn() };
});

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

jest.mock('ee/ai/duo_agentic_chat/utils/agent_utils', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/utils/agent_utils'),
  catalogAgentsFromResponse: jest.fn(
    jest.requireActual('ee/ai/duo_agentic_chat/utils/agent_utils').catalogAgentsFromResponse,
  ),
}));

Vue.config.ignoredElements = ['fe-island-duo-next'];

jest.mock('ee/ai/duo_agentic_chat/websocket/workflow_stream_factory', () => ({
  workflowStreamFactory: {
    getWorkflowStream: jest.fn().mockReturnValue({
      connect: jest.fn(),
      disconnect: jest.fn(),
      send: jest.fn(),
      subscribe: jest.fn().mockImplementation(() => ({ dispose: jest.fn() })),
      getStatus: jest.fn().mockReturnValue({ connected: false, bufferedCount: 0 }),
      terminate: jest.fn(),
      retry: jest.fn(),
    }),
  },
}));

jest.mock('ee/ai/duo_agentic_chat/events/event_hub', () => ({
  initDuoAgenticChatEventHub: jest.fn().mockReturnValue({ dispose: jest.fn() }),
  subscribeToEvent: jest.fn().mockReturnValue({ dispose: jest.fn() }),
}));

jest.mock('fe_islands/duo_next/dist/main', () => ({}), {
  virtual: true,
});

jest.mock('yaml');

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  refreshCurrentPage: jest.fn(),
}));

jest.mock('ee/ai/duo_agentic_chat/utils/workflow_utils', () => ({
  WorkflowUtils: {
    transformChatMessages: jest.fn(),
    parseWorkflowData: jest.fn(),
    normalizeDuoMessages: jest.fn(),
    findParentTs: jest.fn(),
    // Real implementation so thread reloads exercise snapshot reconciliation end to end.
    reconcileLoadedMessages: jest.requireActual('ee/ai/duo_agentic_chat/utils/workflow_utils')
      .WorkflowUtils.reconcileLoadedMessages,
  },
}));

jest.mock('ee/ai/duo_agentic_chat/utils/model_selection_utils', () => ({
  getCurrentModel: jest.fn(),
  getDefaultModel: jest.fn(),
  getModel: jest.fn(),
  saveModel: jest.fn(),
  isModelSelectionDisabled: jest.fn(),
}));

jest.mock('ee/ai/duo_agentic_chat/utils/chat_thread_snapshot', () => ({
  saveThreadSnapshot: jest.fn(),
  loadThreadSnapshot: jest.fn(),
  clearThreadSnapshot: jest.fn(),
}));

// Partial: isWebSearchAvailable stays real so the flag/group gate is exercised here
// rather than stubbed out.
jest.mock('ee/ai/duo_agentic_chat/utils/web_search_preference', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/utils/web_search_preference'),
  loadWebSearchPreference: jest.fn(),
  saveWebSearchPreference: jest.fn(),
}));

// Applies the pipeline for real (mirroring the module it replaces) so the transformers
// the state manager wires in still run, while keeping the call spy for pipeline assertions.
jest.mock('ee/ai/duo_agentic_chat/transformers/index', () => ({
  runMessageTransformers: jest.fn((messages, transformers) =>
    transformers.reduce((msgs, transformer) => transformer(msgs), messages),
  ),
}));

jest.mock('ee/ai/duo_agentic_chat/observability/events_tracker', () => ({
  EventsTracker: {
    updateContext: jest.fn(),
    trackApproveTool: jest.fn(),
    trackDenyTool: jest.fn(),
    trackClickThroughFlowWidget: jest.fn(),
    trackRetryMessage: jest.fn(),
    trackRetrySucceeded: jest.fn(),
    trackRetryFailed: jest.fn(),
    trackNavigateRetryAlternative: jest.fn(),
    reset: jest.fn(),
  },
}));

const MOCK_PROJECT_ID = 'gid://gitlab/Project/123';
const MOCK_NAMESPACE_ID = 'gid://gitlab/Group/456';
const MOCK_RESOURCE_ID = 'gid://gitlab/Resource/789';
const MOCK_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/456';
const MOCK_USER_MESSAGE = {
  content: 'How can I optimize my CI pipeline?',
  role: 'user',
  requestId: `${MOCK_WORKFLOW_ID}-0-user`,
};
const MOCK_CONTEXT_PRESETS_RESPONSE = {
  data: {
    aiChatContextPresets: {
      questions: [
        'How can I optimize my CI pipeline?',
        'What are best practices for merge requests?',
        'How do I set up a workflow for my project?',
        'What are the advantages of using GitLab CI/CD?',
      ],
    },
  },
};
const MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE = {
  data: {
    aiDuoWorkflowCreate: {
      workflow: { id: MOCK_WORKFLOW_ID },
      errors: [],
    },
  },
};
const MOCK_UPDATE_WEB_SEARCH_MUTATION_RESPONSE = {
  data: {
    updateDuoWorkflowWebSearch: {
      workflow: { id: MOCK_WORKFLOW_ID },
      errors: [],
    },
  },
};

const MOCK_WORKFLOW_EVENTS_RESPONSE = {
  duoWorkflowWorkflows: {
    nodes: [
      {
        id: 'workflow-1',
        status: 'completed',
        aiCatalogItemVersionId: '',
        workflowDefinition: null,
        archived: false,
        stalled: false,
        webSearchEnabled: false,
        latestCheckpoint: {
          workflowGoal: '',
          workflowStatus: 'completed',
          errors: null,
          duoMessages: [],
        },
      },
    ],
  },
};

const MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE = {
  duoWorkflowWorkflows: {
    nodes: [
      {
        ...MOCK_WORKFLOW_EVENTS_RESPONSE.duoWorkflowWorkflows.nodes[0],
        archived: true,
        stalled: false,
      },
    ],
  },
};

const MOCK_WORKFLOW_EVENTS_EMPTY_RESPONSE = {
  duoWorkflowWorkflows: {
    nodes: [],
  },
};

const MOCK_WORKFLOW_EVENTS_RESPONSE_WITH_FOUNDATIONAL_AGENT = {
  duoWorkflowWorkflows: {
    nodes: [
      {
        id: 'workflow-1',
        status: 'completed',
        aiCatalogItemVersionId: '',
        workflowDefinition: MOCK_FETCHED_FOUNDATIONAL_AGENT.referenceWithVersion,
        archived: false,
        stalled: false,
        webSearchEnabled: false,
        latestCheckpoint: {
          workflowGoal: '',
          workflowStatus: 'completed',
          errors: null,
          duoMessages: [],
        },
      },
    ],
  },
};

const MOCK_TRANSFORMED_MESSAGES = [
  {
    content: 'Hello, how can I help?',
    role: 'assistant',
    requestId: '456-1-agent',
    message_type: 'agent',
  },
];

const MOCK_PARSED_FLOW_CONFIG = { components: [{ name: 'test', type: 'agent' }] };

const MOCK_UTILS_SETUP = () => {
  WorkflowUtils.transformChatMessages.mockReturnValue(MOCK_TRANSFORMED_MESSAGES);
  WorkflowUtils.normalizeDuoMessages.mockReturnValue([]);
  WorkflowUtils.parseWorkflowData.mockReturnValue({
    workflowGoal: '',
    workflowStatus: 'completed',
    errors: null,
    duoMessages: [],
  });
  parseDocument.mockReturnValue(MOCK_PARSED_FLOW_CONFIG);

  getCurrentModel.mockReturnValue(MOCK_GITLAB_DEFAULT_MODEL_ITEM);
  getDefaultModel.mockReturnValue(MOCK_GITLAB_DEFAULT_MODEL_ITEM);
  // getModel needs to search arrays by value, simple Array.find helper
  getModel.mockImplementation((models, value) => models?.find((m) => m.value === value));
  saveModel.mockReturnValue(true);
  checkModelSelectionDisabled.mockReturnValue(false);

  jest
    .spyOn(WorkflowSocketUtils, 'buildWebsocketUrl')
    .mockReturnValue('/api/v4/ai/duo_workflows/ws');
  jest.spyOn(WorkflowSocketUtils, 'buildStartRequest').mockReturnValue({
    startRequest: {
      workflowID: '456',
      clientVersion: '1.0',
      workflowDefinition: 'chat',
      goal: '',
      approval: {},
    },
  });
  jest.spyOn(WorkflowSocketUtils, 'processWorkflowMessage');
};

const expectedPageContextItem = {
  id: 'page-context',
  content: `<current_gitlab_page_url>http://test.host/</current_gitlab_page_url>
<current_gitlab_page_title></current_gitlab_page_title>`,
  category: DUO_WORKFLOW_ADDITIONAL_CONTEXT_REPOSITORY,
  metadata: JSON.stringify({
    title: 'Current page',
    enabled: true,
    icon: 'link',
    secondaryText: 'Page context /',
    subType: 'open_tab',
    subTypeLabel: 'Current page',
    projectPath: '',
    pagePath: '/',
  }),
};

const orbitContextEnvelope = (orbitEnabled = false) => ({
  category: 'orbit_context',
  content: JSON.stringify({ orbit_enabled: orbitEnabled }),
  metadata: '{}',
});

const expectedAdditionalContext = [expectedPageContextItem];

Vue.use(Vuex);
Vue.use(VueApollo);

jest.mock('~/lib/utils/common_utils', () => ({
  getCookie: jest.fn(),
}));

jest.mock('~/lib/utils/local_storage', () => ({
  getStorageValue: jest.fn(() => ({ exists: false })),
  saveStorageValue: jest.fn(),
  removeStorageValue: jest.fn(),
  getSessionStorageValue: jest.fn(() => ({ exists: false })),
  saveSessionStorageValue: jest.fn(),
  removeSessionStorageValue: jest.fn(),
}));

jest.mock('ee/ai/utils', () => {
  const actualUtils = jest.requireActual('ee/ai/utils');

  return {
    __esModule: true,
    ...actualUtils,
    setAgenticMode: jest.fn(),
  };
});

describe('Duo Agentic Chat State Manager', () => {
  let wrapper;
  let store;

  const actionSpies = {
    addDuoChatMessage: jest.fn((context, message) => {
      // Use the real action implementation
      storeActions.addDuoChatMessage(context, message);
    }),
    setMessages: jest.fn((context, messages = []) => {
      // Directly commit to store instead of async dispatches to avoid timing issues
      context.commit('CLEAN_MESSAGES');
      messages?.forEach((msg) => {
        storeActions.addDuoChatMessage(context, msg);
      });
    }),
    setCurrentAgent: jest.fn((context, agent) => {
      storeActions.setCurrentAgent(context, agent);
    }),
  };

  let mockRouter;
  let mockRoute;
  const docsUrlHost = 'docs.gitlab.com';
  const contextPresetsQueryHandlerMock = jest.fn().mockResolvedValue(MOCK_CONTEXT_PRESETS_RESPONSE);
  const availableModelsQueryHandlerMock = jest
    .fn()
    .mockResolvedValue(MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE);
  const configuredAgentsQueryMock = jest.fn().mockResolvedValue(MOCK_CONFIGURED_AGENTS_RESPONSE);
  const aiFoundationalChatAgentsQueryMock = jest
    .fn()
    .mockResolvedValue(MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE);
  const agentFlowConfigQueryMock = jest.fn().mockResolvedValue(MOCK_FLOW_CONFIG_RESPONSE);
  const flowStatusResponse = (status) => ({
    data: {
      duoWorkflowWorkflows: {
        edges: [
          {
            node: {
              id: '1',
              status,
            },
          },
        ],
      },
    },
  });
  const DEFAULT_FLOW_STATUS_RESPONSE = flowStatusResponse(DUO_WORKFLOW_STATUS_FINISHED);
  const flowStatusQueryMock = jest.fn().mockResolvedValue(DEFAULT_FLOW_STATUS_RESPONSE);
  const createWorkflowMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
  const updateWebSearchMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_UPDATE_WEB_SEARCH_MUTATION_RESPONSE);
  const workflowEventsQueryMock = jest
    .fn()
    .mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
  const workflowBranchesQueryMock = jest
    .fn()
    .mockResolvedValue({ data: { duoWorkflowBranches: [] } });
  const creditsAvailableQueryMock = jest.fn().mockResolvedValue({
    data: { gitlabCreditsAvailable: true, gitlabCreditsUnavailableReason: null },
  });

  const findDuoChat = () => wrapper.findComponent(DuoAgenticChatView);
  const findPromptInputActions = () => wrapper.findComponent(PromptInputActions);
  const findDuoNext = () => wrapper.find('fe-island-duo-next');
  const findChatLoadingState = () => wrapper.findComponent(ChatLoadingState);
  const findCreditsExhaustedAlert = () => wrapper.findComponent(CreditsExhaustedAlert);
  const findConnectionErrorAlert = () => wrapper.findComponent(ConnectionErrorAlert);

  const triggerStreamEvent = (eventType, data) => {
    const subscribeCalls = workflowStreamFactory.getWorkflowStream().subscribe.mock.calls;
    const uniqueCallbacks = [
      ...new Set(subscribeCalls.filter(([type]) => type === eventType).map(([, cb]) => cb)),
    ];
    uniqueCallbacks.forEach((callback) => callback(data));
  };
  const snapshotMessages = [
    { role: 'user', content: 'Cached user message', ts: 1000 },
    { role: 'assistant', content: 'Cached assistant reply', ts: 2000 },
  ];
  const threadSnapshotWithMessages = {
    v: 1,
    convoId: '456',
    lastTs: 2000,
    messages: snapshotMessages,
  };
  const threadSnapshotEmpty = null;

  const createComponent = ({
    initialState = {},
    propsData = {},
    data = {},
    apolloHandlers = [[getAiChatAvailableModels, availableModelsQueryHandlerMock]],
    provide = {},
    stubs = {},
    mountFn = shallowMountExtended,
    routeName = AGENTIC_CHAT_SHOW_ROUTE,
  } = {}) => {
    store = new Vuex.Store({
      mutations: storeMutations,
      actions: actionSpies,
      state: {
        messages: [],
        toolMessage: '',
        currentAgent: null,
        ...initialState,
      },
    });

    const apolloProvider = createMockApollo([
      [getAiChatContextPresets, contextPresetsQueryHandlerMock],
      [getConfiguredAgents, configuredAgentsQueryMock],
      [getFoundationalChatAgents, aiFoundationalChatAgentsQueryMock],
      [getAgentFlowConfig, agentFlowConfigQueryMock],
      [getFlowStatus, flowStatusQueryMock],
      [duoWorkflowMutation, createWorkflowMutationMock],
      [updateWebSearchMutation, updateWebSearchMutationMock],
      [getWorkflowLatestCheckpointQuery, workflowEventsQueryMock],
      [getWorkflowBranchesQuery, workflowBranchesQueryMock],
      [getGitlabCreditsStatusQuery, creditsAvailableQueryMock],
      ...apolloHandlers,
    ]);

    // Mirror real Vue Router: pushing a named location updates the reactive
    // $route so the route-derived multithreadedView computed re-evaluates.
    // eslint-disable-next-line no-restricted-properties
    mockRoute = Vue.observable({ name: routeName });
    mockRouter = {
      push: jest.fn((location) => {
        if (location?.name) {
          mockRoute.name = location.name;
        }
      }),
    };

    const defaultProvide = {
      chatConfiguration: {
        title: 'GitLab Duo Agentic Chat',
        isClassicAvailable: false,
        defaultProps: {
          defaultNamespaceSelected: true,
        },
      },
      activeTabData: {
        props: {
          isClassicAvailable: false,
        },
      },
      duoUiNext: false,
      ...provide,
    };

    wrapper = mountFn(DuoAgenticChatStateManager, {
      store,
      apolloProvider,
      propsData: {
        userId: 'gid://gitlab/User/1',
        exploreAiCatalogPath: '/-/ai/catalog',
        ...propsData,
      },
      provide: defaultProvide,
      mocks: {
        $router: mockRouter,
        $route: mockRoute,
      },
      // PromptQueue renders nothing and owns the queued-prompt logic under test,
      // so it is always rendered for real rather than stubbed out.
      stubs: { PromptQueue, ...stubs },
      data() {
        return data;
      },
    });
  };

  beforeEach(() => {
    loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);
    loadWebSearchPreference.mockReturnValue(false);
    MOCK_UTILS_SETUP();
    // Reset Apollo handler mocks to default values
    createWorkflowMutationMock.mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
    workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
    workflowBranchesQueryMock.mockClear();
    workflowBranchesQueryMock.mockResolvedValue({ data: { duoWorkflowBranches: [] } });
    creditsAvailableQueryMock.mockResolvedValue({
      data: { gitlabCreditsAvailable: true, gitlabCreditsUnavailableReason: null },
    });
    // In the default state, there isn't workflowId registered in session storage
    getSessionStorageValue.mockReturnValue({ exists: false, value: null });
  });

  afterEach(() => {
    if (wrapper) {
      wrapper = null;
    }
  });

  describe('clearActiveWorkflow', () => {
    it('clears the thread and resets lastProcessedMessageId', async () => {
      createComponent({
        data: {
          lastProcessedMessageId: 'message-5',
        },
      });
      await waitForPromises();

      wrapper.vm.clearActiveWorkflow();
      expect(findDuoChat().props('messages')).toEqual([]);
      expect(wrapper.vm.lastProcessedMessageId).toBe(null);
    });

    it('clears selectedAlternatives so stale selections do not leak into a new thread', async () => {
      createComponent({
        data: {
          selectedAlternatives: { 'msg-1': 1 },
        },
      });
      await waitForPromises();

      wrapper.vm.clearActiveWorkflow();
      expect(wrapper.vm.selectedAlternatives).toEqual({});
    });
  });

  describe('beforeDestroy', () => {
    it('clears the active thread when destroyed', () => {
      createComponent();

      const clearActiveWorkflowSpy = jest.spyOn(wrapper.vm, 'clearActiveWorkflow');
      wrapper.destroy();

      // Verify clearActiveWorkflow was called (which resets lastProcessedMessageId)
      expect(clearActiveWorkflowSpy).toHaveBeenCalled();
    });

    it('resets the tracker context when destroyed', () => {
      createComponent();

      const resetSpy = jest.spyOn(EventsTracker, 'reset');
      wrapper.destroy();

      expect(resetSpy).toHaveBeenCalled();
    });
  });

  describe('provide', () => {
    // The real DuoChatMessage from duo-ui injects renderGFM and calls it
    // after rendering, which is what hydrates GLQL/Mermaid code blocks
    // into live views. If the state manager stops providing renderGFM, the
    // inject falls back to a duo-ui stub and the hydrate pipeline never runs.
    it('hydrates assistant chat messages via renderGFM', async () => {
      renderGFM.mockClear();
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      store.dispatch('addDuoChatMessage', {
        role: 'assistant',
        content: 'hello',
        status: 'success',
      });
      await waitForPromises();

      expect(renderGFM).toHaveBeenCalled();
    });
  });

  describe('rendering', () => {
    describe('when Duo Chat is shown', () => {
      beforeEach(() => {
        createComponent({
          propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
        });
        createComponent();
      });

      it('renders the AgenticDuoChat component', () => {
        expect(findDuoChat().exists()).toBe(true);
      });

      it('does not render the loading state if we have an active thread with a snapshot', async () => {
        loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        let resolvePromise = null;
        const pendingPromise = new Promise((resolve) => {
          resolvePromise = resolve;
        });
        workflowEventsQueryMock.mockReturnValueOnce(pendingPromise);

        createComponent();
        await waitForPromises();

        expect(findChatLoadingState().exists()).toBe(false);
        resolvePromise('');
      });

      it('does not render the loading state when isLoading is true but messages exist', async () => {
        // Set up initial messages
        const existingMessages = [
          { role: 'user', content: 'Hello', requestId: '1' },
          { role: 'assistant', content: 'Hi there!', requestId: '2' },
        ];

        createComponent({
          initialState: {
            messages: existingMessages,
          },
          data: {
            isLoading: true,
          },
        });

        await nextTick();

        // Loading state should not be shown because messages exist
        expect(findChatLoadingState().exists()).toBe(false);
        expect(findDuoChat().exists()).toBe(true);
      });

      it('passes isToolApprovalProcessing prop to AgenticDuoChat component', () => {
        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      });

      it('calls the context presets GraphQL query', () => {
        expect(contextPresetsQueryHandlerMock).toHaveBeenCalledWith({
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          namespaceId: null,
          url: 'http://test.host/',
          questionCount: 4,
          foundationalAgentReference: null,
        });
      });

      it('refetches the context presets with the reference of the selected agent', async () => {
        // The agent picker lives in the trial/subscription empty state, so render
        // it and drive the refetch through its `new-chat` event rather than the
        // component's internals.
        createComponent({ propsData: { trialActive: true } });

        await wrapper.findComponent(ActiveTrialOrSubscriptionEmptyState).vm.$emit('new-chat', {
          id: 'gid://gitlab/Ai::FoundationalChatAgent/security_analyst_agent-v1',
          name: 'Security Analyst',
          reference: 'security_analyst_agent',
          referenceWithVersion: 'security_analyst_agent/v1',
          foundational: true,
        });
        await waitForPromises();

        expect(contextPresetsQueryHandlerMock).toHaveBeenCalledWith(
          expect.objectContaining({ foundationalAgentReference: 'security_analyst_agent' }),
        );
      });

      it('passes context presets to WebAgenticDuoChat component as predefinedPrompts', async () => {
        await waitForPromises();
        expect(findDuoChat().props('predefinedPrompts')).toEqual(
          MOCK_CONTEXT_PRESETS_RESPONSE.data.aiChatContextPresets.questions,
        );
      });

      describe('duoChatContext', () => {
        // Prop-drilled down to the slash-command menu, which is several components below
        // and behind a slot.
        it('hands the chat view the ids a plugin needs to scope itself', () => {
          createComponent({
            propsData: {
              projectId: 'gid://gitlab/Project/1',
              projectPath: 'group/project',
              namespaceId: 'gid://gitlab/Group/1',
              resourceId: 'gid://gitlab/WorkItem/1',
              isHandRaiseLeadAvailable: true,
            },
          });

          // The slash-command menu reloads whenever this object changes identity, so it
          // holds the ids only: chat state travels as duoChatState instead.
          expect(findDuoChat().props('duoChatContext')).toEqual({
            projectId: 'gid://gitlab/Project/1',
            projectPath: 'group/project',
            namespaceId: 'gid://gitlab/Group/1',
            resourceId: 'gid://gitlab/WorkItem/1',
          });
        });
      });

      describe('transformedMessages', () => {
        const appendedMessage = { id: 'from-a-plugin', message_type: 'agent' };

        // Asserts the pipeline the state manager hands to runMessageTransformers.
        // Applying it is the capability's own spec.
        const pipeline = () => runMessageTransformers.mock.calls.at(-1)[1];

        it('appends transformers contributed by plugins after the built-in ones', () => {
          const duoChatPluginRegistry = new DuoChatPluginRegistry();
          duoChatPluginRegistry.registerPlugin({
            name: 'a_plugin',
            messageTransformers: [
              { transformMessages: (messages) => [...messages, appendedMessage] },
            ],
          });
          createComponent({ provide: { duoChatPluginRegistry } });

          // Second to last, since the alternatives transformer always closes the pipeline.
          expect(pipeline().at(-2)([])).toEqual([appendedMessage]);
        });

        it('passes only the built-in transformers when no plugin contributes one', () => {
          createComponent();

          expect(pipeline()).toEqual([
            expect.any(Function),
            expect.any(Function),
            expect.any(Function),
          ]);
        });
      });

      // TurnProgress decides what to report; its own spec covers that. What matters
      // here is that it is handed the inputs it needs to decide correctly.
      describe('turnProgress wiring', () => {
        const findTurnProgress = () => wrapper.findComponent(TurnProgress);

        it('reports nothing while no turn is in flight', () => {
          createComponent();

          expect(findTurnProgress().props('isLoading')).toBe(false);
        });

        describe('once a prompt is in flight', () => {
          beforeEach(async () => {
            createComponent({ data: { isInititalLoad: false } });
            await waitForPromises();

            findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: '/compact' }));
            await waitForPromises();
          });

          it('marks the turn as live', () => {
            expect(findTurnProgress().props('isLoading')).toBe(true);
          });

          // TurnProgress reads the prompt to tell a compaction apart from any other
          // turn, so it has to arrive. That this is the *raw* log rather than the
          // transcript the plugin strips it from is proven end-to-end in
          // integration/ai_duo_panel/duo_agentic_chat/compaction_spec.js -- the
          // transformers are a pass-through here, so the two are indistinguishable.
          it('hands over the log including the prompt just sent', () => {
            expect(findTurnProgress().props('messages')).toContainEqual(
              expect.objectContaining({ content: '/compact', role: 'user' }),
            );
          });

          it('stops marking the turn as live once it is cancelled', async () => {
            findDuoChat().vm.$emit('chat-cancel');
            await waitForPromises();

            expect(findTurnProgress().props('isLoading')).toBe(false);
          });
        });
      });

      describe('messageRenderers', () => {
        const pluginWidget = {
          matchMessage: (message) => message.message_sub_type === 'from_a_plugin',
          component: { name: 'PluginWidget' },
        };

        it('passes the widgets contributed by registered plugins', () => {
          const duoChatPluginRegistry = new DuoChatPluginRegistry();
          duoChatPluginRegistry.registerPlugin({
            name: 'a_plugin',
            messageWidgets: [pluginWidget],
          });
          createComponent({ provide: { duoChatPluginRegistry } });

          expect(findDuoChat().props('messageRenderers')).toEqual([pluginWidget]);
        });

        it('passes no renderers when no plugin is registered', () => {
          expect(findDuoChat().props('messageRenderers')).toEqual([]);
        });

        // A plugin descriptor is module-level, so the resolver is the only place the
        // chat's own state can reach a widget's props.
        it('resolves widget defaultProps against the chat context', () => {
          const duoChatPluginRegistry = new DuoChatPluginRegistry();
          duoChatPluginRegistry.registerPlugin({
            name: 'a_plugin',
            messageWidgets: [
              { ...pluginWidget, defaultProps: (message, _dir, dependencies) => dependencies },
            ],
          });
          createComponent({
            propsData: {
              projectId: MOCK_PROJECT_ID,
              isHandRaiseLeadAvailable: true,
              canBuyAddon: true,
              tierUpgradePath: '/-/subscriptions/new',
            },
            provide: { duoChatPluginRegistry },
          });

          const [{ defaultProps }] = findDuoChat().props('messageRenderers');

          expect(defaultProps({}, '/work/dir')).toMatchObject({
            duoChatContext: expect.objectContaining({ projectId: MOCK_PROJECT_ID }),
            duoChatState: {
              canBuyAddon: true,
              tierUpgradePath: '/-/subscriptions/new',
              isHandRaiseLeadAvailable: true,
            },
          });
        });
      });
    });
  });

  describe('chat mode on mount', () => {
    let hydrateActiveWorkflowSpy;
    let onNewChatSpy;

    beforeEach(() => {
      hydrateActiveWorkflowSpy = jest.spyOn(
        DuoAgenticChatStateManager.methods,
        'hydrateActiveWorkflow',
      );
      onNewChatSpy = jest.spyOn(DuoAgenticChatStateManager.methods, 'onNewChat');
    });

    describe('when mounted on the new-chat route', () => {
      beforeEach(async () => {
        createComponent({
          routeName: AGENTIC_CHAT_NEW_ROUTE,
          data: { workflowId: MOCK_WORKFLOW_ID },
        });
        await waitForPromises();
      });

      it('starts a new chat even when a stored workflow exists', () => {
        expect(onNewChatSpy).toHaveBeenCalled();
        expect(hydrateActiveWorkflowSpy).not.toHaveBeenCalled();
      });
    });

    describe('when there is no active thread', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('loads the new chat', () => {
        expect(onNewChatSpy).toHaveBeenCalled();
      });

      it('does not hydrate the active thread', () => {
        expect(hydrateActiveWorkflowSpy).not.toHaveBeenCalled();
      });

      it('does not display old thread messages', () => {
        expect(findDuoChat().props('messages')).toEqual([]);
      });
    });

    describe('when there is an active thread', () => {
      beforeEach(async () => {
        WorkflowUtils.transformChatMessages.mockReturnValue(MOCK_TRANSFORMED_MESSAGES);
        createComponent({
          data: {
            workflowId: MOCK_WORKFLOW_ID,
          },
        });
        await waitForPromises();
      });

      it('hydrates the active thread', () => {
        expect(hydrateActiveWorkflowSpy).toHaveBeenCalled();
      });

      it('does not load a new chat', () => {
        expect(onNewChatSpy).not.toHaveBeenCalled();
      });

      it('sets the last processed message id based on the thread messages', () => {
        expect(wrapper.vm.lastProcessedMessageId).toBe(
          MOCK_TRANSFORMED_MESSAGES[MOCK_TRANSFORMED_MESSAGES.length - 1].message_id,
        );
      });
    });
  });

  describe('Workflow deletion handling', () => {
    it('shows error when sending message to workflow deleted in different instance', async () => {
      createComponent({
        initialState: { messages: [{ role: 'user', content: 'test' }] },
        data: { isInititalLoad: false },
      });
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(wrapper.vm.workflowId).toBe(MOCK_WORKFLOW_ID);

      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Follow-up question' }));
      await waitForPromises();
      expect(findDuoChat().props('isChatAvailable')).toBe(false);
      expect(findDuoChat().props('error')).toBe('This chat was deleted.');
    });

    it('shows the tailored permission message without wiping the transcript when sending into an existing thread hits a permission error', async () => {
      createComponent({
        initialState: { messages: [{ role: 'user', content: 'Earlier question' }] },
      });
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(wrapper.vm.workflowId).toBe(MOCK_WORKFLOW_ID);

      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [{ message: 'Forbidden', extensions: { code: NO_RESOURCE_PERMISSIONS } }],
      });

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Follow-up question' }));
      await waitForPromises();

      expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);
      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          errors: [
            "I don't have access to that resource at the moment. Is there something else I can help you with?",
          ],
        }),
      );
      expect(captureExceptionForDuoChat).toHaveBeenCalled();
    });

    it('starts new chat when loading with deleted workflow after page reload', async () => {
      getSessionStorageValue.mockReturnValueOnce({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });

      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      createComponent();
      await waitForPromises();

      expect(findDuoChat().props('messages')).toHaveLength(0);
    });

    it('shows error when navigating to deleted workflow from history in same instance', async () => {
      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      expect(findDuoChat().props('messages')).toHaveLength(0);
    });

    describe('when loading the active workflow fails with a generic (non-deletion) error', () => {
      const errorText = 'Network timeout occurred';
      const RETRY_DELAY_MS = 10000;

      it('shows a loading state while retrying, then a dedicated error state instead of a chat message', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent();
        await waitForPromises();

        expect(workflowEventsQueryMock).toHaveBeenCalledTimes(1);
        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);

        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(workflowEventsQueryMock).toHaveBeenCalledTimes(2);
        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);

        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(workflowEventsQueryMock).toHaveBeenCalledTimes(3);
        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(false);
        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);
        expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ errors: [`Error: ${errorText}`] }),
        );
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          expect.objectContaining({ message: errorText }),
        );
      });

      it('loads messages once a retry succeeds, hiding the loading state', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock
          .mockRejectedValueOnce(new Error(errorText))
          .mockResolvedValueOnce({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });

        createComponent();
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);

        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(workflowEventsQueryMock).toHaveBeenCalledTimes(2);
        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(false);
        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);
      });

      it('takes priority over a cached snapshot and the trial/subscription empty state', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent({ propsData: { trialActive: true } });
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);

        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);
      });

      it('retries loading the workflow when the user clicks retry', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent();
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);

        workflowEventsQueryMock.mockResolvedValueOnce({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
        wrapper.findComponent(ThreadLoadErrorEmptyState).vm.$emit('retry-thread-load');
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);
      });

      it('clears the error state when starting a new chat', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent();
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);

        wrapper.findComponent(ThreadLoadErrorEmptyState).vm.$emit('new-chat');
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(false);
      });
    });

    it('clears the workflow thread snapshot when workflow is deleted', async () => {
      getSessionStorageValue.mockReturnValueOnce({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });

      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      createComponent();
      await waitForPromises();

      expect(clearThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
    });

    it('shows the deleted-chat error immediately, without retrying, when a cached snapshot exists for a deleted workflow', async () => {
      getSessionStorageValue.mockReturnValueOnce({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });
      loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);
      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      createComponent();
      await waitForPromises();

      expect(workflowEventsQueryMock).toHaveBeenCalledTimes(1);
      expect(findDuoChat().props('isChatAvailable')).toBe(false);
      expect(findDuoChat().props('error')).toBe('This chat was deleted.');
    });

    it('shows no namespace empty state when NO_DEFAULT_NAMESPACE error is returned', async () => {
      workflowEventsQueryMock.mockRejectedValue({
        graphQLErrors: [
          {
            message:
              "You don't have permission to access this workflow. Please select a default namespace.",
            extensions: { code: 'NO_DEFAULT_NAMESPACE' },
          },
        ],
      });

      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      expect(wrapper.findComponent(NoNamespaceEmptyState).exists()).toBe(true);
    });
  });

  describe('events handling', () => {
    beforeEach(() => {
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });
    });

    describe('@send-chat-prompt', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it.each([GENIE_CHAT_NEW_MESSAGE, GENIE_CHAT_RESET_MESSAGE, GENIE_CHAT_CLEAR_MESSAGE])(
        'resets chat state when "%s" command is sent',
        async (command) => {
          createComponent();
          wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

          findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: command }));
          await nextTick();

          expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);
          expect(findChatLoadingState().exists()).toBe(false);
          expect(findDuoChat().props('isLoading')).toBe(false);
        },
      );

      describe('a flow command in the prompt', () => {
        const SCAN = {
          value: '/flow:security-scan',
          label: 'Security Scan',
          startOnly: true,
          consumerId: 42,
        };

        const send = async (text, slashCommands = [SCAN]) => {
          findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text, slashCommands }));
          await waitForPromises();
        };

        const sentContext = () =>
          WorkflowSocketUtils.buildStartRequest.mock.calls.at(-1)[0].additionalContext;

        it('asks the service to start the flow, alongside the usual context', async () => {
          await send('/flow:security-scan check the auth module');

          expect(sentContext()).toEqual([
            ...expectedAdditionalContext,
            expect.objectContaining({ category: 'duo_chat_command' }),
          ]);
        });

        it('sends nothing extra for a prompt that invokes no command', async () => {
          await send('what does this project do?', []);

          expect(sentContext()).toEqual(expectedAdditionalContext);
        });
      });

      it('creates a new workflow when sending a prompt for the first time with projectId', async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({
            projectId: MOCK_PROJECT_ID,
            goal: MOCK_USER_MESSAGE.content,
          }),
        );

        expect(WorkflowSocketUtils.buildWebsocketUrl).toHaveBeenCalledWith({
          rootNamespaceId: null,
          namespaceId: null,
          projectId: MOCK_PROJECT_ID,
          userModelSelectionEnabled: false,
          currentModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          defaultModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          aiCatalogItemVersionId: '',
          workflowDefinition: undefined,
          workflowId: '456',
        });

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalledWith(
          '/api/v4/ai/duo_workflows/ws',
          expect.any(Object),
        );

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith({
          workflowId: '456',
          workflowDefinition: undefined,
          userPrompt: createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          approval: {},
          additionalContext: expectedAdditionalContext,
          agentConfig: null,
          flowConfig: null,
          metadata: null,
          clientCapabilities: ['incremental_streaming', 'web_search'],
          orbitEnabled: false,
          resumeCheckpointTs: null,
        });

        expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({
            content: MOCK_USER_MESSAGE.content,
            role: 'user',
            requestId: DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
          }),
        );
      });

      it.each([true, false])(
        'creates the workflow with the web search preference the user selected (%s)',
        async (webSearchEnabled) => {
          findPromptInputActions().vm.$emit('update:web-search-enabled', webSearchEnabled);
          await waitForPromises();

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(createWorkflowMutationMock).toHaveBeenCalledWith(
            expect.objectContaining({ webSearchEnabled }),
          );
        },
      );

      it('includes orbit_context envelope with orbit_enabled: true when a foundational agent is selected and orbitEnabled is true', async () => {
        createComponent({
          data: { orbitEnabled: true, selectedFoundationalAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
          initialState: { currentAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
        });

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
          expect.objectContaining({
            additionalContext: expect.arrayContaining([
              {
                category: 'orbit_context',
                content: JSON.stringify({ orbit_enabled: true }),
                metadata: '{}',
              },
            ]),
          }),
        );
      });

      it('does not include orbit_context envelope when no foundational agent is selected', async () => {
        createComponent({ data: { orbitEnabled: true } });

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
        const { additionalContext } = call[0];

        expect(additionalContext.filter((c) => c.category === 'orbit_context')).toHaveLength(0);
      });

      it('replaces a caller-supplied orbit_context envelope with the authoritative value when a foundational agent is selected', async () => {
        createComponent({
          data: { orbitEnabled: true, selectedFoundationalAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
          initialState: { currentAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
        });
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        wrapper.vm.startWorkflow({
          userPrompt: createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          approval: {},
          additionalContext: [orbitContextEnvelope(false)],
        });
        await waitForPromises();

        const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
        const { additionalContext } = call[0];
        const orbitEnvelopes = additionalContext.filter((c) => c.category === 'orbit_context');

        expect(orbitEnvelopes).toHaveLength(1);
        expect(orbitEnvelopes[0].content).toBe(JSON.stringify({ orbit_enabled: true }));
      });

      it('includes commandAdditionalContext envelopes (e.g. form_context) from openDuoChatWithAgent', async () => {
        const formContextEnvelope = {
          category: 'form_context',
          content: JSON.stringify({ form_id: 'ask-duo-pat' }),
          metadata: '{}',
        };
        duoChatGlobalState.commands = [
          {
            agent: { name: 'Permissions Assistant' },
            resourceId: '1',
            autoSend: false,
            additionalContext: [formContextEnvelope],
          },
        ];
        await waitForPromises();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
        const { additionalContext } = call[0];

        expect(additionalContext).toEqual(expect.arrayContaining([formContextEnvelope]));
      });

      it('commandAdditionalContext takes precedence over caller-supplied envelopes with the same category', async () => {
        const sessionFormContext = {
          category: 'form_context',
          content: JSON.stringify({ form_id: 'session-form' }),
          metadata: '{}',
        };
        const perMessageFormContext = {
          category: 'form_context',
          content: JSON.stringify({ form_id: 'per-message-form' }),
          metadata: '{}',
        };
        // Per-message context is gathered from the system context providers on each send.
        jest
          .spyOn(SystemContextManager.prototype, 'getSystemContextItems')
          .mockResolvedValue([perMessageFormContext]);
        duoChatGlobalState.commands = [
          {
            agent: { name: 'Permissions Assistant' },
            resourceId: '1',
            autoSend: false,
            additionalContext: [sessionFormContext],
          },
        ];
        await waitForPromises();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
        const { additionalContext } = call[0];
        const formEnvelopes = additionalContext.filter((c) => c.category === 'form_context');

        expect(formEnvelopes).toEqual([sessionFormContext]);
      });

      describe('attachments', () => {
        const attachment = {
          id: 'att-1',
          filename: 'diagram.png',
          mimeType: 'image/png',
          byteSize: 2048,
          data: 'aGVsbG8=',
          previewUrl: 'data:image/png;base64,aGVsbG8=',
        };

        const sendWithAttachments = async (attachments) => {
          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content, attachments }),
          );
          await waitForPromises();
        };

        it('sends one attachments envelope per file alongside the other context', async () => {
          await sendWithAttachments([attachment]);

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
          const envelopes = call[0].additionalContext.filter((c) => c.category === 'attachments');

          expect(envelopes).toEqual([
            {
              category: 'attachments',
              content: JSON.stringify({
                mime_type: 'image/png',
                data: 'aGVsbG8=',
                filename: 'diagram.png',
              }),
              metadata: '{}',
            },
          ]);
        });

        it('preserves the non-attachment context envelopes', async () => {
          await sendWithAttachments([attachment]);

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

          expect(call[0].additionalContext).toEqual(
            expect.arrayContaining(expectedAdditionalContext),
          );
        });

        // The reference token comes from the payload-free envelope the flow service
        // echoes on the turn's UiChatLog. Pinning it on the pending message here would
        // be dropped anyway: ADD_MESSAGE merges shallowly, so the round-tripped
        // message's own `extras` replaces it wholesale.
        it('pins no extras on the sent user message', async () => {
          await sendWithAttachments([attachment]);

          expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
            expect.anything(),
            expect.not.objectContaining({ extras: expect.anything() }),
          );
        });

        // An image on its own is a user turn, not an approval resume, so it keeps the
        // context that only a user turn carries.
        it('carries the foundational agent context when only images are sent', async () => {
          createComponent({
            data: {
              orbitEnabled: true,
              selectedFoundationalAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT,
            },
            initialState: { currentAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
          });

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: '', attachments: [attachment] }),
          );
          await waitForPromises();

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

          expect(call[0].additionalContext).toEqual(
            expect.arrayContaining([orbitContextEnvelope(true)]),
          );
        });

        it('adds no attachments envelope when nothing is attached', async () => {
          await sendWithAttachments([]);

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

          expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([]);
        });

        it('does not break when the event omits the attachments argument', async () => {
          findDuoChat().vm.$emit('send-chat-prompt', MOCK_USER_MESSAGE.content);
          await waitForPromises();

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

          expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([]);
        });
      });

      describe('external context providers', () => {
        const EXTERNAL_CATEGORY = 'permissions_form_context';
        let disposeProvider;

        afterEach(() => {
          disposeProvider?.();
        });

        it('injects registered external context, read fresh on each send', async () => {
          let contentObj = { namespace: ['read_project'] };
          disposeProvider = registerExternalContextProvider(EXTERNAL_CATEGORY, () => contentObj);

          createComponent({
            initialState: { currentAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT },
          });

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              additionalContext: expect.arrayContaining([
                {
                  category: EXTERNAL_CATEGORY,
                  content: JSON.stringify(contentObj),
                  metadata: '{}',
                },
              ]),
            }),
          );

          // A later send must reflect the updated state, not the first snapshot.
          contentObj = { namespace: ['read_project', 'write_project'] };
          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          const lastCall = WorkflowSocketUtils.buildStartRequest.mock.calls.at(-1)[0];
          const injected = lastCall.additionalContext.find((c) => c.category === EXTERNAL_CATEGORY);

          expect(injected.content).toBe(JSON.stringify(contentObj));
        });
      });

      describe('agenticChatFlowRegistryMigration feature flag', () => {
        it('passes flowConfig with agentic_chat registry values when flag is enabled', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: true },
            },
          });

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              flowConfig: {
                flowConfigId: 'agentic_chat',
                flowVersion: '1.0.0',
                flowConfigSchemaVersion: 'v1',
              },
            }),
          );
        });

        it('passes flowConfig as null when flag is disabled', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: false },
            },
          });

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({ flowConfig: null }),
          );
        });

        it('passes flowConfig as null when flag is enabled but agentConfig is set', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: true },
            },
          });
          await waitForPromises();

          wrapper.vm.agentConfig = 'version: v1\nflowConfigId: custom_agent\nflowVersion: 1.0.0';

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({ flowConfig: null }),
          );
        });

        it('passes the selected agent flowConfig when the migration flag is disabled', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: false },
            },
          });
          await waitForPromises();

          wrapper.vm.selectedFoundationalAgent = {
            ...DUO_CHAT_AGENT_MOCK,
            flowConfig: {
              flowConfigId: 'chat',
              flowConfigSchemaVersion: null,
              flowVersion: '^1.0.0',
            },
          };

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              flowConfig: {
                flowConfigId: 'chat',
                flowConfigSchemaVersion: null,
                flowVersion: '^1.0.0',
              },
            }),
          );
        });

        it('does not overwrite a non-chat foundational agent flowConfig when the migration flag is enabled', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: true },
            },
          });
          await waitForPromises();

          wrapper.vm.selectedFoundationalAgent = {
            id: 'gid://gitlab/Ai::FoundationalChatAgent/duo_permissions_assistant-v1',
            name: 'Permissions Assistant',
            referenceWithVersion: 'duo_permissions_assistant/v1',
            flowConfig: {
              flowConfigId: 'duo_permissions_assistant',
              flowConfigSchemaVersion: 'v1',
              flowVersion: '^1.0.0',
            },
          };

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              flowConfig: {
                flowConfigId: 'duo_permissions_assistant',
                flowConfigSchemaVersion: 'v1',
                flowVersion: '^1.0.0',
              },
            }),
          );
        });

        it('keeps an explicitly selected chat agent on its own flow when the migration flag is enabled', async () => {
          createComponent({
            provide: {
              glFeatures: { agenticChatFlowRegistryMigration: true },
            },
          });
          await waitForPromises();

          wrapper.vm.selectedFoundationalAgent = {
            ...DUO_CHAT_AGENT_MOCK,
            flowConfig: {
              flowConfigId: 'chat',
              flowConfigSchemaVersion: null,
              flowVersion: '^1.0.0',
            },
          };

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              flowConfig: {
                flowConfigId: 'chat',
                flowConfigSchemaVersion: null,
                flowVersion: '^1.0.0',
              },
            }),
          );
        });
      });

      it('creates a new workflow when sending a prompt for the first time with namespaceId', async () => {
        createComponent({
          propsData: { namespaceId: MOCK_NAMESPACE_ID, resourceId: MOCK_RESOURCE_ID },
        });

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({
            namespaceId: MOCK_NAMESPACE_ID,
            goal: MOCK_USER_MESSAGE.content,
          }),
        );

        expect(WorkflowSocketUtils.buildWebsocketUrl).toHaveBeenCalledWith({
          rootNamespaceId: null,
          namespaceId: MOCK_NAMESPACE_ID,
          projectId: null,
          userModelSelectionEnabled: false,
          currentModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          defaultModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          aiCatalogItemVersionId: '',
          workflowDefinition: undefined,
          workflowId: '456',
        });

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalledWith(
          '/api/v4/ai/duo_workflows/ws',
          expect.any(Object),
        );

        expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({
            content: MOCK_USER_MESSAGE.content,
            role: 'user',
            requestId: DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
          }),
        );
      });

      it('creates a new workflow when sending a prompt for the first time with both projectId and namespaceId', async () => {
        createComponent({
          propsData: {
            projectId: MOCK_PROJECT_ID,
            namespaceId: MOCK_NAMESPACE_ID,
            resourceId: MOCK_RESOURCE_ID,
          },
        });

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({
            projectId: MOCK_PROJECT_ID,
            namespaceId: MOCK_NAMESPACE_ID,
            goal: MOCK_USER_MESSAGE.content,
          }),
        );
      });

      it('creates a new workflow when sending a prompt for the first time without projectId or namespaceId', async () => {
        createComponent({
          propsData: { resourceId: MOCK_RESOURCE_ID },
        });

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({
            goal: MOCK_USER_MESSAGE.content,
          }),
        );
        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.not.objectContaining({ projectId: expect.anything() }),
        );
      });

      it('creates a new workflow with aiCatalogItemVersionId when catalog agent is selected', async () => {
        const mockCatalogItemVersionId = 'gid://gitlab/Ai::Catalog::ItemVersion/100';
        createComponent({
          propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
        });
        wrapper.vm.aiCatalogItemVersionId = mockCatalogItemVersionId;

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({
            projectId: MOCK_PROJECT_ID,
            goal: MOCK_USER_MESSAGE.content,
            aiCatalogItemVersionId: mockCatalogItemVersionId,
          }),
        );

        expect(WorkflowSocketUtils.buildWebsocketUrl).toHaveBeenCalledWith({
          rootNamespaceId: null,
          namespaceId: null,
          projectId: MOCK_PROJECT_ID,
          userModelSelectionEnabled: false,
          currentModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          defaultModel: MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          aiCatalogItemVersionId: mockCatalogItemVersionId,
          workflowDefinition: undefined,
          workflowId: '456',
        });
      });

      it('sets waiting on prompt to true when sending a prompt', async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await nextTick();

        expect(findDuoChat().props('isLoading')).toBe(true);
      });

      it('does not create a new workflow if one already exists', async () => {
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        createWorkflowMutationMock.mockClear();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('connects to WebSocket and sends start request', async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('adds user message with pending requestId immediately before async operations', async () => {
        findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Test question' }));
        await nextTick();

        expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({
            content: 'Test question',
            role: 'user',
            requestId: DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
          }),
        );
      });

      it('tracks submit message event with trial label when on trial', async () => {
        createComponent({
          propsData: { trialActive: true, isTrial: true },
        });
        await waitForPromises();

        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Test question' }));
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'submit_dap_trial_or_paid_empty_state_message',
          { label: 'trial' },
          undefined,
        );
      });

      it('tracks submit message event with paid label when on paid subscription', async () => {
        createComponent({
          propsData: { subscriptionActive: true, isTrial: false },
        });
        await waitForPromises();

        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Test question' }));
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'submit_dap_trial_or_paid_empty_state_message',
          { label: 'paid' },
          undefined,
        );
      });

      it('does not track submit message event when shouldShowActiveTrialOrSubscriptionEmptyState is false', async () => {
        createComponent({
          propsData: { trialActive: false },
        });
        await waitForPromises();

        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Test question' }));
        await waitForPromises();

        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'submit_dap_trial_or_paid_empty_state_message',
        );
      });

      describe('tracks event with the correct properties', () => {
        let trackEventSpy;

        beforeEach(() => {
          createComponent({
            propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
          });
          ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
        });

        it('tracks event with foundational agent properties when foundational agent is selected', async () => {
          const mockFoundationalAgent = {
            id: 'gid://gitlab/Ai::FoundationalChatAgent/security_analyst',
            name: 'Security Analyst',
            reference: 'security_analyst',
            referenceWithVersion: 'security_analyst/v1',
            version: 'v1',
            foundational: true,
            tools: [{ name: 'create_issue' }, { name: 'get_merge_request' }],
            flowConfig: { flowVersion: '1.2.0' },
          };

          await wrapper.vm.onNewChat(mockFoundationalAgent);
          await waitForPromises();

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(trackEventSpy).toHaveBeenCalledWith(
            CHAT_TRACKING_EVENT,
            {
              label: 'foundational_agent',
              property: 'chat',
              value: null,
              foundational_item_ref: 'security_analyst',
              item_type: 'foundational_agent',
              item_version: '1.2.0',
              item_schema_version: 'v1',
              flow_name: 'chat',
              component_name: 'security_analyst',
              tools: 'create_issue,get_merge_request',
            },
            undefined,
          );
        });

        it('tracks event with catalog agent properties when catalog agent is selected', async () => {
          const mockCatalogAgent = {
            id: 'gid://gitlab/Ai::Catalog::Item/1',
            name: 'Test Catalog Agent',
            itemType: 'AGENT',
            foundational: false,
            latestVersion: { versionName: '1.0.0' },
            pinnedItemVersionId: 'gid://gitlab/Ai::Catalog::ItemVersion/100',
            pinnedItemVersion: {
              versionName: '2.0.0',
              tools: { nodes: [{ name: 'read_file' }, { name: 'grep' }] },
              mcpTools: ['search'],
            },
          };

          await wrapper.vm.onNewChat(mockCatalogAgent);
          await waitForPromises();

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(trackEventSpy).toHaveBeenCalledWith(
            CHAT_TRACKING_EVENT,
            {
              label: 'agent',
              property: 'chat',
              value: 100,
              foundational_item_ref: null,
              item_type: 'custom_agent',
              custom_item_id: 1,
              item_version: '2.0.0',
              item_schema_version: 'v1',
              tools: 'read_file,grep',
              mcp_tools: 'search',
            },
            undefined,
          );
        });

        it('does not track event when neither foundational nor catalog agent is selected', async () => {
          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          expect(trackEventSpy).not.toHaveBeenCalled();
        });
      });
    });

    describe('WebSocket message handling', () => {
      beforeEach(async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        actionSpies.addDuoChatMessage.mockClear();
      });

      it('processes messages from the WebSocket and updates the UI', async () => {
        const checkpointData = {
          requestID: 'request-id-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  { content: 'Hello, how can I help?', message_type: 'agent' },
                  {
                    content: 'I can assist with optimizing your CI pipeline.',
                    message_type: 'agent',
                  },
                ],
              },
            },
            status: 'completed',
            goal: 'Test goal for activeThread',
          },
        };
        const mockEvent = { type: 'message', data: checkpointData };

        triggerStreamEvent('message', mockEvent);
        await waitForPromises();

        expect(WorkflowSocketUtils.processWorkflowMessage).toHaveBeenCalledWith(mockEvent, null);

        expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
          expect.any(Object),
          MOCK_TRANSFORMED_MESSAGES.at(-1),
        );
      });

      it('handles tool approval flow', async () => {
        const mockCheckpointData = {
          requestID: 'request-id-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'I need to run a command.',
                    message_type: 'assistant',
                    tool_info: {
                      name: 'run_command',
                      args: { command: 'ls -la' },
                    },
                  },
                ],
              },
            },
            status: 'TOOL_CALL_APPROVAL_REQUIRED',
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockCheckpointData,
        });
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      });

      it('sets waiting on prompt to false when workflow status is INPUT_REQUIRED', async () => {
        const mockCheckpointData = {
          requestID: 'request-id-4',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'Please provide more information',
                    message_type: 'agent',
                  },
                ],
              },
            },
            status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockCheckpointData,
        });
        await waitForPromises();

        expect(findDuoChat().props('isLoading')).toBe(false);
      });

      it('handles errors from WebSocket', () => {
        triggerStreamEvent('error', { type: 'error', origin: 'decode', message: 'read failed' });

        expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({
            errors: ['Error: Unable to connect to workflow service. Please try again.'],
          }),
        );
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'Unable to connect to workflow service. Please try again.',
          }),
          { extra: { type: 'error', origin: 'decode', message: 'read failed' } },
        );
      });
    });

    describe('Race condition prevention in message processing', () => {
      beforeEach(async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        actionSpies.addDuoChatMessage.mockClear();
      });

      it('prevents concurrent processing of messages', async () => {
        const createMockEvent = (messageContent) => ({
          type: 'message',
          data: {
            requestID: 'request-id-race',
            newCheckpoint: {
              checkpoint: {
                channel_values: {
                  ui_chat_log: [{ content: messageContent, message_type: 'agent' }],
                },
              },
              status: 'running',
            },
          },
        });

        // Set up processWorkflowMessage to return proper data
        WorkflowSocketUtils.processWorkflowMessage
          .mockReturnValueOnce({
            messages: [MOCK_TRANSFORMED_MESSAGES[0]],
            status: 'running',
            lastProcessedMessageId: 'message-0',
          })
          .mockReturnValueOnce({
            messages: [MOCK_TRANSFORMED_MESSAGES[0]],
            status: 'running',
            lastProcessedMessageId: 'message-1',
          });

        // Fire two events rapidly (simulating race condition)
        triggerStreamEvent('message', createMockEvent('First message'));
        triggerStreamEvent('message', createMockEvent('Second message'));

        // Wait for all processing to complete
        await waitForPromises();
        await nextTick();

        // Verify processWorkflowMessage was called sequentially, not concurrently
        // First call should have null, second should have updated message id
        expect(WorkflowSocketUtils.processWorkflowMessage).toHaveBeenNthCalledWith(
          1,
          expect.anything(),
          null,
        );
        expect(WorkflowSocketUtils.processWorkflowMessage).toHaveBeenNthCalledWith(
          2,
          expect.anything(),
          'message-0', // Uses updated lastProcessedMessageId from first call
        );
      });

      it('processes the final event when multiple events arrive rapidly', async () => {
        const createMockEvent = (id, messageContent) => ({
          type: 'message',
          data: {
            requestID: `request-id-${id}`,
            newCheckpoint: {
              checkpoint: {
                channel_values: {
                  ui_chat_log: [{ content: messageContent, message_type: 'agent' }],
                },
              },
              status: 'running',
            },
          },
        });

        // Mock processWorkflowMessage to return data
        WorkflowSocketUtils.processWorkflowMessage.mockImplementation(() => ({
          messages: [MOCK_TRANSFORMED_MESSAGES[0]],
          status: 'running',
          lastProcessedMessageId: 'message-0',
        }));

        // Fire multiple events rapidly - only first and last should be processed
        triggerStreamEvent('message', createMockEvent(1, 'Message 1'));
        triggerStreamEvent('message', createMockEvent(2, 'Message 2'));
        triggerStreamEvent('message', createMockEvent(3, 'Message 3'));
        triggerStreamEvent('message', createMockEvent(4, 'Final message'));

        await waitForPromises();
        await nextTick();

        // Should process at least 2 messages: first one that started immediately,
        // and the last one that was pending
        expect(WorkflowSocketUtils.processWorkflowMessage).toHaveBeenCalled();
        // The final event should have been processed
        const lastCall =
          WorkflowSocketUtils.processWorkflowMessage.mock.calls[
            WorkflowSocketUtils.processWorkflowMessage.mock.calls.length - 1
          ];
        // Verify the last event was processed (request-id-4)
        expect(lastCall[0].data).toBeDefined();
      });

      it('maintains correct lastProcessedMessageId across sequential processing', async () => {
        const createMockEvent = (index) => ({
          type: 'message',
          data: {
            requestID: `request-id-${index}`,
            newCheckpoint: {
              checkpoint: {
                channel_values: {
                  ui_chat_log: [
                    {
                      content: `Message ${index}`,
                      message_type: 'agent',
                      message_id: `message-${index}`,
                    },
                  ],
                },
              },
              status: 'running',
            },
          },
        });

        // Mock to return incrementing lastProcessedMessageId
        WorkflowSocketUtils.processWorkflowMessage
          .mockReturnValueOnce({
            messages: [MOCK_TRANSFORMED_MESSAGES[0]],
            status: 'running',
            lastProcessedMessageId: 'message-0',
          })
          .mockReturnValueOnce({
            messages: [MOCK_TRANSFORMED_MESSAGES[0]],
            status: 'running',
            lastProcessedMessageId: 'message-1',
          });

        // Send two events
        triggerStreamEvent('message', createMockEvent(1));
        await waitForPromises();

        triggerStreamEvent('message', createMockEvent(2));
        await waitForPromises();

        // Verify the message id was properly updated and passed
        expect(wrapper.vm.lastProcessedMessageId).toBe('message-1');
      });

      it('clears processing state when cleanupState is called', () => {
        const mockEvent = {
          type: 'message',
          data: {
            requestID: 'request-id-cleanup',
            newCheckpoint: {
              checkpoint: {
                channel_values: { ui_chat_log: [] },
              },
              status: 'running',
            },
          },
        };

        // Simulate in-flight processing state (processWorkflowMessage is synchronous,
        // so we set the state directly to mimic what happens during async processing)
        wrapper.vm.isProcessingMessage = true;
        wrapper.vm.pendingEvent = mockEvent;

        expect(wrapper.vm.isProcessingMessage).toBe(true);

        // Call cleanup
        wrapper.vm.cleanupState();

        expect(wrapper.vm.isProcessingMessage).toBe(false);
        expect(wrapper.vm.pendingEvent).toBe(null);
      });
    });

    describe('@chat-cancel', () => {
      it('cancels the active connection, does not reset the workflowID', async () => {
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        findDuoChat().vm.$emit('chat-cancel');
        await nextTick();

        expect(workflowStreamFactory.getWorkflowStream().disconnect).toHaveBeenCalled();

        expect(findChatLoadingState().exists()).toBe(false);
        expect(findDuoChat().props('isLoading')).toBe(false);
        expect(wrapper.vm.workflowId).toBe(MOCK_WORKFLOW_ID);
      });
    });

    describe('onNewChat', () => {
      it('resets chat state for new conversation', async () => {
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        wrapper.vm.onNewChat();
        await nextTick();

        expect(wrapper.vm.workflowId).toBe(null);
        expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);
        expect(findChatLoadingState().exists()).toBe(false);
        expect(findDuoChat().props('isLoading')).toBe(false);
        expect(workflowStreamFactory.getWorkflowStream().disconnect).toHaveBeenCalled();
      });
      it('clears the active thread', async () => {
        const clearActiveWorkflowSpy = jest.spyOn(wrapper.vm, 'clearActiveWorkflow');

        wrapper.vm.onNewChat();
        await nextTick();

        expect(clearActiveWorkflowSpy).toHaveBeenCalled();
      });
      it('clears archived thread state when starting a new chat', async () => {
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE });
        createComponent();
        await waitForPromises();

        expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']({})).toBeDefined();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: GENIE_CHAT_NEW_MESSAGE }),
        );
        await nextTick();

        expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']).toBeUndefined();
      });
    });

    describe('@approve-tool', () => {
      beforeEach(() => {
        createComponent();
      });

      it('handles tool approval via chat component event and updates processing state through workflow', async () => {
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);

        findDuoChat().vm.$emit('approve-tool');
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith({
          workflowId: '456',
          workflowDefinition: undefined,
          userPrompt: EMPTY_USER_PROMPT,
          approval: { approval: {} },
          additionalContext: [],
          agentConfig: null,
          flowConfig: null,
          metadata: null,
          clientCapabilities: ['incremental_streaming', 'web_search'],
          orbitEnabled: false,
          resumeCheckpointTs: null,
        });

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();

        const mockApprovalRequiredData = {
          requestID: 'request-id-approval-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'I need approval to execute this tool',
                    message_type: 'assistant',
                    tool_info: {
                      name: 'some_tool',
                      args: { param: 'value' },
                    },
                  },
                ],
              },
            },
            status: 'TOOL_CALL_APPROVAL_REQUIRED',
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockApprovalRequiredData,
        });
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);

        const mockCompletedData = {
          requestID: 'request-id-approval-2',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'Tool execution completed',
                    message_type: 'agent',
                  },
                ],
              },
            },
            status: 'completed',
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockCompletedData,
        });
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      });

      it('calls EventsTracker.trackApproveTool with tool name from last message', async () => {
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        store.commit('ADD_MESSAGE', {
          message_type: 'request',
          role: 'assistant',
          requestId: 'req-tracking-1',
          tool_info: { name: 'some_tool', args: {} },
          content: 'Tool requires approval',
        });

        findDuoChat().vm.$emit('approve-tool');
        await nextTick();

        expect(EventsTracker.trackApproveTool).toHaveBeenCalledWith({
          toolName: 'some_tool',
        });
      });
    });

    describe('@deny-tool', () => {
      beforeEach(() => {
        createComponent();
      });

      it('handles tool denial via chat component event with message and updates processing state', async () => {
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        const denyMessage = 'I do not approve this action';

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);

        findDuoChat().vm.$emit('deny-tool', denyMessage);
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith({
          workflowId: '456',
          workflowDefinition: undefined,
          userPrompt: EMPTY_USER_PROMPT,
          approval: {
            approval: undefined,
            rejection: { message: denyMessage },
          },
          additionalContext: [],
          agentConfig: null,
          flowConfig: null,
          metadata: null,
          clientCapabilities: ['incremental_streaming', 'web_search'],
          orbitEnabled: false,
          resumeCheckpointTs: null,
        });

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();

        const mockApprovalRequiredData = {
          requestID: 'request-id-denial-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'Tool approval was required',
                    message_type: 'assistant',
                    tool_info: {
                      name: 'some_tool',
                      args: { param: 'value' },
                    },
                  },
                ],
              },
            },
            status: 'TOOL_CALL_APPROVAL_REQUIRED',
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockApprovalRequiredData,
        });
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);

        const mockDenialProcessedData = {
          requestID: 'request-id-denial-2',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [
                  {
                    content: 'Tool execution denied, proceeding with alternative approach',
                    message_type: 'agent',
                  },
                ],
              },
            },
            status: 'processing',
          },
        };

        triggerStreamEvent('message', {
          type: 'message',
          data: mockDenialProcessedData,
        });
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      });

      it('handles tool denial via chat component event with event object and updates processing state', async () => {
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        const eventObject = { message: 'I do not approve this action' };

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);

        findDuoChat().vm.$emit('deny-tool', eventObject);
        await nextTick();

        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('calls EventsTracker.trackDenyTool with tool name from last message', async () => {
        await waitForPromises();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        store.commit('ADD_MESSAGE', {
          message_type: 'request',
          role: 'assistant',
          requestId: 'req-tracking-2',
          tool_info: { name: 'some_tool', args: {} },
          content: 'Tool requires approval',
        });

        findDuoChat().vm.$emit('deny-tool', 'I do not approve');
        await nextTick();

        expect(EventsTracker.trackDenyTool).toHaveBeenCalledWith({
          toolName: 'some_tool',
        });
      });
    });

    describe('@retry-message', () => {
      const retryUserPrompt = 'What is GitLab?';
      const seedRetryMessages = (messages) => {
        messages.forEach((m) => store.commit('ADD_MESSAGE', m));
        // The component mount calls setMessages([]) via onNewChat, so reset
        // the spy after seeding so per-test assertions start from zero calls.
        actionSpies.addDuoChatMessage.mockClear();
        createWorkflowMutationMock.mockClear();
      };
      const baseRetryMessages = [
        { id: 'user-1', role: 'user', content: retryUserPrompt },
        { id: 'assistant-1', role: 'assistant', content: 'Original (failed) response' },
      ];

      describe('when the feature flag is enabled', () => {
        beforeEach(async () => {
          createComponent({
            provide: {
              glFeatures: {
                agenticManualRetryForDuoChatResponses: true,
              },
            },
          });
          await waitForPromises();
        });

        it('forwards is-retry-enabled=true to the chat view', () => {
          expect(findDuoChat().props('isRetryEnabled')).toBe(true);
        });

        it('resubmits the preceding user prompt when retry-message is emitted', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
            expect.anything(),
            expect.objectContaining({
              content: retryUserPrompt,
              role: 'user',
            }),
          );
          expect(createWorkflowMutationMock).toHaveBeenCalledWith(
            expect.objectContaining({ goal: retryUserPrompt }),
          );
        });

        it('forks from the parent checkpoint of the resubmitted user message', async () => {
          seedRetryMessages([
            { ...baseRetryMessages[0], parent_ts: 'ts-parent-1' },
            baseRetryMessages[1],
          ]);
          WorkflowSocketUtils.buildStartRequest.mockClear();

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              userPrompt: createUserPrompt({ text: retryUserPrompt }),
              resumeCheckpointTs: 'ts-parent-1',
            }),
          );
        });

        it('re-reads the session for the parent checkpoint when the message has none', async () => {
          createComponent({
            data: { workflowId: MOCK_WORKFLOW_ID },
            provide: {
              glFeatures: {
                agenticManualRetryForDuoChatResponses: true,
              },
            },
          });
          await waitForPromises();

          seedRetryMessages([
            { ...baseRetryMessages[0], message_id: 'user-msg-1' },
            baseRetryMessages[1],
          ]);
          WorkflowUtils.findParentTs.mockReturnValue('ts-parent-refetched');
          WorkflowSocketUtils.buildStartRequest.mockClear();

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(WorkflowUtils.findParentTs).toHaveBeenCalledWith(expect.anything(), 'user-msg-1');
          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({
              userPrompt: createUserPrompt({ text: retryUserPrompt }),
              resumeCheckpointTs: 'ts-parent-refetched',
            }),
          );
        });

        it('tracks the retry click with attempt number 1 for a message with no prior alternatives', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(EventsTracker.trackRetryMessage).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        it('tracks the retry click with an incremented attempt number when the message already has alternatives', async () => {
          seedRetryMessages([
            { id: 'user-1', role: 'user', content: retryUserPrompt },
            {
              id: 'assistant-1',
              role: 'assistant',
              content: 'Original (failed) response',
              alternatives: [{ agent_responses: [{ message_id: 'alt-1' }] }],
            },
          ]);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(EventsTracker.trackRetryMessage).toHaveBeenCalledWith({ attemptNumber: 2 });
        });

        it('tracks retry success when the workflow responds with INPUT_REQUIRED after a retry', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          triggerStreamEvent('message', {
            type: 'message',
            data: {
              requestID: 'request-id-retry',
              newCheckpoint: {
                checkpoint: {
                  channel_values: {
                    ui_chat_log: [{ content: 'Retried response', message_type: 'agent' }],
                  },
                },
                status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
              },
            },
          });
          await waitForPromises();

          expect(EventsTracker.trackRetrySucceeded).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        it('tracks retry failure when the workflow socket errors after a retry', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          triggerStreamEvent('error', { type: 'error', origin: 'decode', message: 'read failed' });

          expect(EventsTracker.trackRetryFailed).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        it('tracks retry failure when reconnection is exhausted during a retry', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          triggerStreamEvent('error', { type: 'error', reason: 'max_retries_exceeded' });

          expect(EventsTracker.trackRetryFailed).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        const terminalStatusCheckpoint = (status) => ({
          type: 'message',
          data: {
            requestID: 'request-id-retry',
            newCheckpoint: {
              checkpoint: {
                channel_values: {
                  ui_chat_log: [{ content: 'Agent failed', message_type: 'agent' }],
                },
              },
              status,
            },
          },
        });

        it.each([DUO_WORKFLOW_STATUS_FAILED, DUO_WORKFLOW_STATUS_STOPPED])(
          'tracks retry failure when the workflow streams a %s checkpoint after a retry',
          async (status) => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            triggerStreamEvent('message', terminalStatusCheckpoint(status));
            await waitForPromises();

            expect(EventsTracker.trackRetryFailed).toHaveBeenCalledWith({ attemptNumber: 1 });
          },
        );

        it('clears the pending retry on a failed checkpoint so a later turn is not misattributed', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          triggerStreamEvent('message', terminalStatusCheckpoint(DUO_WORKFLOW_STATUS_FAILED));
          await waitForPromises();

          triggerStreamEvent('message', {
            type: 'message',
            data: {
              requestID: 'request-id-followup',
              newCheckpoint: {
                checkpoint: {
                  channel_values: {
                    ui_chat_log: [{ content: 'Recovered response', message_type: 'agent' }],
                  },
                },
                status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
              },
            },
          });
          await waitForPromises();

          expect(EventsTracker.trackRetrySucceeded).not.toHaveBeenCalled();
        });

        it.each([
          ['policy violation', { code: 1008, reason: 'Insufficient credits: quota exceeded' }],
          ['try again later', { code: 1013 }],
          ['abnormal', { code: 1006 }],
        ])('tracks retry failure when a %s close ends a pending retry', async (_, closeEvent) => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          triggerStreamEvent('close', { type: 'close', ...closeEvent });
          await waitForPromises();

          expect(EventsTracker.trackRetryFailed).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        it('does not attribute an unrelated error to a pending retry', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          // Errors from outside the conversation turn (background queries, thread
          // list refresh, etc.) route through onError but must not resolve the retry.
          wrapper.vm.onError(new Error('unrelated background failure'));

          expect(EventsTracker.trackRetryFailed).not.toHaveBeenCalled();

          triggerStreamEvent('message', {
            type: 'message',
            data: {
              requestID: 'request-id-retry',
              newCheckpoint: {
                checkpoint: {
                  channel_values: {
                    ui_chat_log: [{ content: 'Retried response', message_type: 'agent' }],
                  },
                },
                status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
              },
            },
          });
          await waitForPromises();

          expect(EventsTracker.trackRetrySucceeded).toHaveBeenCalledWith({ attemptNumber: 1 });
        });

        it('does not attribute a later turn outcome to a retry that was cancelled', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          findDuoChat().vm.$emit('chat-cancel');
          await waitForPromises();

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: 'unrelated follow-up question' }),
          );
          await waitForPromises();

          triggerStreamEvent('message', {
            type: 'message',
            data: {
              requestID: 'request-id-post-cancel',
              newCheckpoint: {
                checkpoint: {
                  channel_values: {
                    ui_chat_log: [{ content: 'Follow-up response', message_type: 'agent' }],
                  },
                },
                status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
              },
            },
          });
          await waitForPromises();

          expect(EventsTracker.trackRetrySucceeded).not.toHaveBeenCalled();
          expect(EventsTracker.trackRetryFailed).not.toHaveBeenCalled();
        });

        it('walks past intervening non-user messages to find the most recent user prompt', async () => {
          seedRetryMessages([
            { id: 'user-0', role: 'user', content: 'first prompt' },
            { id: 'assistant-0', role: 'assistant', content: 'first reply' },
            { id: 'user-1', role: 'user', content: retryUserPrompt },
            { id: 'tool-1', role: 'tool', content: 'some tool output' },
            { id: 'assistant-1', role: 'assistant', content: 'failed reply' },
          ]);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
            expect.anything(),
            expect.objectContaining({
              content: retryUserPrompt,
              role: 'user',
            }),
          );
        });

        it('is a no-op when no preceding user message exists', async () => {
          seedRetryMessages([{ id: 'assistant-only', role: 'assistant', content: 'orphan reply' }]);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-only' });
          await waitForPromises();

          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        });

        it('is a no-op when the message id is unknown', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'does-not-exist' });
          await waitForPromises();

          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        });

        it('is a no-op when all preceding user messages are clarification answers', async () => {
          // When all user messages before the target are clarification answers (JSON payloads),
          // the retry should no-op to avoid resubmitting invalid prompts.
          const clarificationAnswerContent = JSON.stringify({
            message_sub_type: 'clarification_answer',
            selected_option: 'option-1',
            message_id: 'orphan-tool-id',
          });

          seedRetryMessages([
            { id: 'user-1', role: 'user', content: clarificationAnswerContent },
            { id: 'assistant-1', role: 'assistant', content: 'failed reply' },
          ]);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        });

        it('is a no-op when target message is not an assistant message', async () => {
          seedRetryMessages([
            { id: 'user-0', role: 'user', content: 'first prompt' },
            { id: 'user-1', role: 'user', content: 'second prompt' },
          ]);

          findDuoChat().vm.$emit('retry-message', { id: 'user-1' });
          await waitForPromises();

          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        });

        describe('additional context', () => {
          const PAGE_A = '/group/project/-/issues/1';
          const PAGE_B = '/group/project/-/merge_requests/2';

          const userMessage = (id, pagePath) => ({
            id,
            requestId: id,
            role: 'user',
            message_type: 'user',
            content: retryUserPrompt,
            additional_context: [{ id: 'page-context', metadata: { pagePath, projectPath: '' } }],
          });
          const assistantMessage = (id) => ({
            id,
            requestId: id,
            role: 'assistant',
            message_type: 'agent',
            content: 'A response',
          });
          const findInjectedPageContext = () => {
            const [{ additionalContext }] = WorkflowSocketUtils.buildStartRequest.mock.calls.at(-1);
            return additionalContext.filter((item) => item.id === 'page-context');
          };
          // Ends the turn so the next retry is not rejected as one already in flight.
          const endTurn = async () => {
            triggerStreamEvent('close', { type: 'close', code: 1000 });
            await waitForPromises();
          };

          // Turn 1 injected page A's context and turn 2 injected page B's. Retrying
          // turn 2 discards it, so the branch the fork replays ends at page A.
          beforeEach(() => {
            seedRetryMessages([
              userMessage('user-1', PAGE_A),
              assistantMessage('assistant-1'),
              userMessage('user-2', PAGE_B),
              assistantMessage('assistant-2'),
            ]);
            WorkflowSocketUtils.buildStartRequest.mockClear();
          });

          afterEach(() => {
            setWindowLocation('http://test.host/');
          });

          describe('when only the discarded attempt carried the current page', () => {
            beforeEach(async () => {
              setWindowLocation(PAGE_B);

              findDuoChat().vm.$emit('retry-message', { id: 'assistant-2' });
              await waitForPromises();
            });

            it('sends the page context again', () => {
              expect(findInjectedPageContext()).toHaveLength(1);
            });
          });

          describe('when a surviving turn already carried the current page', () => {
            beforeEach(async () => {
              setWindowLocation(PAGE_A);

              findDuoChat().vm.$emit('retry-message', { id: 'assistant-2' });
              await waitForPromises();
            });

            it('sends no page context', () => {
              expect(findInjectedPageContext()).toHaveLength(0);
            });
          });

          describe('when the same turn is retried again from another page', () => {
            beforeEach(async () => {
              setWindowLocation(PAGE_B);
              findDuoChat().vm.$emit('retry-message', { id: 'assistant-2' });
              await waitForPromises();
              await endTurn();

              setWindowLocation(PAGE_A);
              findDuoChat().vm.$emit('retry-message', { id: 'assistant-2' });
              await waitForPromises();
            });

            it('stays anchored to the surviving turn and sends no page context', () => {
              expect(findInjectedPageContext()).toHaveLength(0);
            });
          });
        });

        describe('when a retry fails', () => {
          it('forwards retryStates with the message pending while the retry is in flight', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).toEqual({
              'assistant-1': RETRY_STATE.PENDING,
            });
          });

          it('sets retryStates to failed instead of appending a new error message', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            triggerStreamEvent('error', {
              type: 'error',
              origin: 'decode',
              message: 'read failed',
            });
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).toEqual({
              'assistant-1': RETRY_STATE.FAILED,
            });
            // Scoped to this wrapper's own messages (rather than the shared
            // addDuoChatMessage spy) since other specs in this file mount
            // additional component instances that share the same spy.
            expect(findDuoChat().props('messages')).not.toContainEqual(
              expect.objectContaining({ errors: expect.anything() }),
            );
          });

          it('clears the pending retry state so the retry button stops loading', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();
            expect(findDuoChat().props('retryStates')).toEqual({
              'assistant-1': RETRY_STATE.PENDING,
            });

            triggerStreamEvent('error', {
              type: 'error',
              origin: 'decode',
              message: 'read failed',
            });
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).not.toEqual({
              'assistant-1': RETRY_STATE.PENDING,
            });
          });

          it('clears a previous failed retry state when the same message is retried again', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();
            triggerStreamEvent('error', {
              type: 'error',
              origin: 'decode',
              message: 'read failed',
            });
            await waitForPromises();
            expect(findDuoChat().props('retryStates')).toEqual({
              'assistant-1': RETRY_STATE.FAILED,
            });

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await nextTick();

            expect(findDuoChat().props('retryStates')).not.toEqual({
              'assistant-1': RETRY_STATE.FAILED,
            });
          });

          it('sets retryStates to failed when the socket closes abnormally without a prior error event', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            triggerStreamEvent('close', { type: 'close', code: 1006 });
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).toEqual({
              'assistant-1': RETRY_STATE.FAILED,
            });
          });

          it('does not mark the retry as failed on a normal (code 1000) close', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            triggerStreamEvent('close', { type: 'close', code: 1000 });
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).toEqual({});
          });

          it('clears the failed retry state when the chat is cancelled', async () => {
            seedRetryMessages(baseRetryMessages);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();
            triggerStreamEvent('close', { type: 'close', code: 1006 });
            await waitForPromises();

            findDuoChat().vm.$emit('chat-cancel');
            await waitForPromises();

            expect(findDuoChat().props('retryStates')).toEqual({});
          });
        });

        describe('when the conversation was compacted after the last prompt', () => {
          const compactionMessage = {
            id: 'compaction-1',
            role: 'tool',
            message_type: 'tool',
            message_sub_type: 'compaction',
            content: 'Summarized 2 messages',
          };

          it('forwards is-retry-enabled=false to the chat view', async () => {
            seedRetryMessages([...baseRetryMessages, compactionMessage]);
            await nextTick();

            expect(findDuoChat().props('isRetryEnabled')).toBe(false);
          });

          it('does not resubmit when retry-message is emitted', async () => {
            seedRetryMessages([...baseRetryMessages, compactionMessage]);

            findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
            await waitForPromises();

            expect(createWorkflowMutationMock).not.toHaveBeenCalled();
          });

          it('stays disabled when the compaction ran mid-turn, between the prompt and the response', async () => {
            // The distinct requestId stops ADD_MESSAGE from splicing the response
            // in right after its prompt, which would push the compaction last.
            seedRetryMessages([
              baseRetryMessages[0],
              compactionMessage,
              { ...baseRetryMessages[1], requestId: 'req-response' },
            ]);
            await nextTick();

            expect(findDuoChat().props('isRetryEnabled')).toBe(false);
          });

          it('re-enables retry once a new prompt follows the compaction', async () => {
            seedRetryMessages([
              ...baseRetryMessages,
              compactionMessage,
              { id: 'user-2', requestId: 'req-2', role: 'user', content: 'A new prompt' },
              {
                id: 'assistant-2',
                requestId: 'req-2',
                role: 'assistant',
                content: 'A new response',
              },
            ]);
            await nextTick();

            expect(findDuoChat().props('isRetryEnabled')).toBe(true);
          });
        });
      });

      describe('when the feature flag is disabled', () => {
        beforeEach(async () => {
          createComponent();
          await waitForPromises();
        });

        it('forwards is-retry-enabled=false to the chat view', () => {
          expect(findDuoChat().props('isRetryEnabled')).toBe(false);
        });

        it('does not resubmit when retry-message is emitted', async () => {
          seedRetryMessages(baseRetryMessages);

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();

          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        });
      });
    });

    describe('@select-alternative', () => {
      beforeEach(async () => {
        createComponent({
          provide: {
            glFeatures: {
              aiAgenticWorkflows: true,
              duoChatRetry: true,
            },
          },
        });
        await waitForPromises();
      });

      it('passes selectedAlternatives prop to the chat view', () => {
        expect(findDuoChat().props('selectedAlternatives')).toEqual({});
      });

      it('updates selectedAlternatives when select-alternative is emitted', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        await nextTick();

        expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'msg-1': 1 });
      });

      it('tracks navigation when select-alternative is emitted', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        await nextTick();

        expect(EventsTracker.trackNavigateRetryAlternative).toHaveBeenCalledWith({ index: 1 });
      });

      it('does not track when the same index is re-selected', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        await nextTick();
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        await nextTick();

        expect(EventsTracker.trackNavigateRetryAlternative).toHaveBeenCalledTimes(1);
      });

      it('does not track selecting index 0 when nothing was selected before', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 0 });
        await nextTick();

        expect(EventsTracker.trackNavigateRetryAlternative).not.toHaveBeenCalled();
        expect(findDuoChat().props('selectedAlternatives')).toEqual({});
      });

      it('ignores a non-numeric index', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 'some text' });
        await nextTick();

        expect(EventsTracker.trackNavigateRetryAlternative).not.toHaveBeenCalled();
        expect(findDuoChat().props('selectedAlternatives')).toEqual({});
      });

      it('tracks multiple message selections independently', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-2', index: 2 });
        await nextTick();

        expect(findDuoChat().props('selectedAlternatives')).toEqual({
          'msg-1': 1,
          'msg-2': 2,
        });
      });

      it('updates existing selection when same messageId is selected again', async () => {
        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 1 });
        await nextTick();

        findDuoChat().vm.$emit('select-alternative', { messageId: 'msg-1', index: 0 });
        await nextTick();

        expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'msg-1': 0 });
      });

      describe('while a retry is in flight', () => {
        beforeEach(async () => {
          createComponent({
            provide: {
              glFeatures: {
                agenticManualRetryForDuoChatResponses: true,
              },
            },
          });
          await waitForPromises();

          [
            { id: 'user-1', role: 'user', content: 'What is GitLab?' },
            { id: 'assistant-1', role: 'assistant', content: 'Original (failed) response' },
          ].forEach((m) => store.commit('ADD_MESSAGE', m));

          findDuoChat().vm.$emit('retry-message', { id: 'assistant-1' });
          await waitForPromises();
        });

        it('ignores alternative navigation until the retry settles', async () => {
          findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-1', index: 1 });
          await waitForPromises();

          expect(EventsTracker.trackNavigateRetryAlternative).not.toHaveBeenCalled();
          expect(findDuoChat().props('selectedAlternatives')).toEqual({});
        });
      });

      describe('lazily fetching alternative branches', () => {
        const seedMessages = (messages) => {
          messages.forEach((m) => store.commit('ADD_MESSAGE', m));
        };

        it('fetches branches before selecting a not-yet-loaded historical alternative', async () => {
          seedMessages([
            {
              id: 'user-1',
              role: 'user',
              content: 'What is GitLab?',
              alternative_count: 1,
              thread_ts: 'ts-1',
            },
            { id: 'assistant-1', role: 'assistant', content: 'GitLab is a DevSecOps platform.' },
          ]);
          workflowBranchesQueryMock.mockResolvedValue({
            data: {
              duoWorkflowBranches: [{ forkThreadTs: 'ts-fork', messages: [] }],
            },
          });

          findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-1', index: 1 });
          await waitForPromises();

          expect(workflowBranchesQueryMock).toHaveBeenCalledWith(
            expect.objectContaining({ threadTs: 'ts-1' }),
          );
          expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'assistant-1': 1 });
        });

        it('does not fetch branches when selecting an alternative from a live retry in this session', async () => {
          seedMessages([
            { id: 'user-1', role: 'user', content: 'What is GitLab?' },
            { id: 'assistant-1', role: 'assistant', content: 'First (failed) answer' },
            { id: 'user-2', role: 'user', content: 'What is GitLab?', is_retry: true },
            { id: 'assistant-2', role: 'assistant', content: 'Second answer' },
          ]);

          findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-2', index: 1 });
          await waitForPromises();

          expect(workflowBranchesQueryMock).not.toHaveBeenCalled();
          expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'assistant-2': 1 });
        });
      });
    });
  });

  describe('tool approval state management', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('keeps buttons disabled while tool is running after approval', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      findDuoChat().vm.$emit('approve-tool');
      await nextTick();

      expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);

      triggerStreamEvent('message', {
        type: 'message',
        data: {
          requestID: 'request-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [{ content: 'Running', message_type: 'agent' }],
              },
            },
            status: DUO_WORKFLOW_STATUS_RUNNING,
          },
        },
      });
      await waitForPromises();
      await nextTick();

      expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);
    });

    it('re-enables buttons when tool finishes running', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      findDuoChat().vm.$emit('approve-tool');
      await nextTick();

      triggerStreamEvent('message', {
        type: 'message',
        data: {
          requestID: 'request-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: { ui_chat_log: [{ content: 'Done', message_type: 'agent' }] },
            },
            status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
          },
        },
      });
      await waitForPromises();
      await nextTick();

      expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
    });
  });

  describe('workflowId watcher', () => {
    beforeEach(async () => {
      createComponent();

      await waitForPromises();
    });

    it('stores workflowId and active thread when workflowId changes', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(saveSessionStorageValue).toHaveBeenCalledWith(DUO_CURRENT_WORKFLOW_STORAGE_KEY, {
        workflowId: MOCK_WORKFLOW_ID,
      });
    });

    it('emits session-id-changed when workflowId changes', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(wrapper.emitted('session-id-changed')).toBeDefined();
      expect(wrapper.emitted('session-id-changed')[0]).toEqual(['456']);
    });
  });

  describe('route watcher', () => {
    let onNewChatSpy;
    let hydrateActiveWorkflowSpy;

    const bootstrapOnRoute = async (routeName) => {
      hydrateActiveWorkflowSpy = jest.spyOn(
        DuoAgenticChatStateManager.methods,
        'hydrateActiveWorkflow',
      );
      onNewChatSpy = jest.spyOn(DuoAgenticChatStateManager.methods, 'onNewChat');

      createComponent({ routeName });
      await waitForPromises();
      hydrateActiveWorkflowSpy.mockClear();
      onNewChatSpy.mockClear();
    };

    // SHOW and NEW share this component, so an in-place switch only changes the
    // reactive $route - mirror that by mutating the mocked route name.
    const navigateTo = async (routeName) => {
      mockRoute.name = routeName;
      await nextTick();
    };

    it('starts a new chat when switching in place to the new-chat route', async () => {
      await bootstrapOnRoute(AGENTIC_CHAT_SHOW_ROUTE);
      await navigateTo(AGENTIC_CHAT_NEW_ROUTE);

      expect(onNewChatSpy).toHaveBeenCalledTimes(1);
      expect(hydrateActiveWorkflowSpy).not.toHaveBeenCalled();
    });

    it('does not re-initialize when switching to a route it does not own', async () => {
      await bootstrapOnRoute(AGENTIC_CHAT_SHOW_ROUTE);
      await navigateTo(AGENTIC_CHAT_HISTORY_ROUTE);

      expect(onNewChatSpy).not.toHaveBeenCalled();
      expect(hydrateActiveWorkflowSpy).not.toHaveBeenCalled();
    });
  });

  describe('Error conditions', () => {
    const errorText = 'Failed to fetch resources';

    it('handles errors from the context presets query', async () => {
      contextPresetsQueryHandlerMock.mockRejectedValueOnce(new Error(errorText));
      createComponent();
      await waitForPromises();

      expect(findDuoChat().exists()).toBe(true);
      expect(findDuoChat().props('predefinedPrompts')).toEqual([]);
    });

    it('does not surface a context presets failure as a chat message', async () => {
      contextPresetsQueryHandlerMock.mockRejectedValueOnce(new Error(errorText));
      createComponent();
      await waitForPromises();

      expect(findDuoChat().props('messages')).toEqual([]);
    });

    it('handles workflow creation errors', async () => {
      createWorkflowMutationMock.mockRejectedValue(new Error(errorText));
      createComponent();
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          errors: [`Error: ${errorText}`],
        }),
      );
    });
  });

  describe('queued prompts', () => {
    const findPromptQueue = () => wrapper.findComponent(PromptQueue);
    const queuedPrompts = () => findDuoChat().props('queuedPrompts');
    // The only way a prompt gets queued for real: the composer submits while the
    // chat cannot take it, and the queue holds it until canSend says otherwise.
    const queuePrompt = async (text) => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text }));
      await nextTick();
    };
    const queued = (text) => ({ id: expect.any(String), prompt: createUserPrompt({ text }) });

    beforeEach(async () => {
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });
      await waitForPromises();
      jest.clearAllMocks();
    });

    it('enqueues a prompt on queue-chat-prompt without sending it', async () => {
      wrapper.vm.isWaitingOnPrompt = true;
      await queuePrompt('queued text');

      expect(queuedPrompts()).toEqual([queued('queued text')]);
      expect(createWorkflowMutationMock).not.toHaveBeenCalled();
      expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
    });

    it('removes a single queued prompt on remove-queued-prompt', async () => {
      wrapper.vm.isWaitingOnPrompt = true;
      await queuePrompt('first');
      await queuePrompt('second');
      const [{ id }] = queuedPrompts();

      findDuoChat().vm.$emit('remove-queued-prompt', id);
      await nextTick();

      expect(queuedPrompts()).toEqual([queued('second')]);
    });

    it('clears the queue when the turn is cancelled', async () => {
      wrapper.vm.isWaitingOnPrompt = true;
      await queuePrompt('first');

      findDuoChat().vm.$emit('chat-cancel');
      await nextTick();

      expect(queuedPrompts()).toEqual([]);
    });

    // The gates the queue and the composer work from. They agree everywhere except
    // at a tool approval, asserted further down, and between them have to cover
    // every reason a prompt would be dropped rather than sent.
    describe('canSendPrompt', () => {
      it('is true once the chat is idle and interactive', () => {
        expect(findPromptQueue().props('canSend')).toBe(true);
      });

      it('hands the composer the same answer as the queue while the chat is idle', () => {
        expect(findDuoChat().props('canSendPrompt')).toBe(true);
      });

      it('is false for a turn the composer did not start, so the composer queues too', async () => {
        // Regression: the composer used to work this out from its own local
        // state, which only tracks turns it submitted itself, and so sent
        // straight into a turn started by a draining queued prompt.
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({ goal: 'queued text' }),
        );
        expect(findDuoChat().props('canSendPrompt')).toBe(false);
        expect(findPromptQueue().props('canSend')).toBe(false);
      });

      it.each`
        reason                       | state
        ${'a turn is running'}       | ${{ isWaitingOnPrompt: true }}
        ${'a tool call is running'}  | ${{ isProcessingToolApproval: true }}
        ${'the chat is unavailable'} | ${{ isChatAvailable: false }}
        ${'the thread is hydrating'} | ${{ isHydratingThread: true }}
        ${'the flow is locked'}      | ${{ isFlowLocked: true }}
        ${'a socket is attached'}    | ${{ isStreamOpen: true }}
        ${'a tool needs approval'}   | ${{ workflowStatus: DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED }}
      `('is false while $reason', async ({ state }) => {
        Object.assign(wrapper.vm, state);
        await nextTick();

        expect(findPromptQueue().props('canSend')).toBe(false);
      });

      it('is false while the chat state is disabled', async () => {
        wrapper.vm.setChatState({ isEnabled: false, reason: 'nope' });
        await nextTick();

        expect(findPromptQueue().props('canSend')).toBe(false);
      });
    });

    describe('draining on turn completion', () => {
      it('fires the next queued prompt when the turn completes', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        expect(queuedPrompts()).toEqual([]);
        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({ goal: 'queued text' }),
        );
        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('does not fire when the queue is empty', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await nextTick();

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });

      it('does not fire while chat is unavailable, leaving the queue intact', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');
        wrapper.vm.isChatAvailable = false;

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        expect(queuedPrompts()).toEqual([queued('queued text')]);
        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });

      it('keeps draining when a queued prompt does not start a turn (e.g. a reset command)', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt(GENIE_CHAT_RESET_MESSAGE);
        await queuePrompt('real prompt');

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        // The reset ran and the real prompt still fired rather than stalling.
        expect(queuedPrompts()).toHaveLength(0);
        expect(createWorkflowMutationMock).toHaveBeenCalledWith(
          expect.objectContaining({ goal: 'real prompt' }),
        );
      });

      // cleanupState() nulls workflowId before onNewChat decides to keep the queue,
      // so the prompts that survive are briefly unowned and depend on the id the
      // next turn creates to re-claim them.
      it('re-owns a carried-over queue once the new chat has a workflow', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt(GENIE_CHAT_RESET_MESSAGE);
        await queuePrompt('first');
        await queuePrompt('second');

        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();

        // The reset started the new chat and 'first' gave it a workflow, so 'second'
        // is still queued and has to be stored against that workflow, not the
        // abandoned one and not as unowned.
        expect(queuedPrompts()).toEqual([queued('second')]);
        expect(saveSessionStorageValue).toHaveBeenCalledWith(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY, {
          workflowId: MOCK_WORKFLOW_ID,
          prompts: [queued('second')],
        });
      });

      // Regression: Workhorse holds an exclusive lock on the workflow for the life
      // of the socket and releases it just before closing, so a prompt sent between
      // the agent finishing and the socket closing came back rejected with 1013.
      describe('when the turn ends before the socket closes', () => {
        beforeEach(async () => {
          // A real first turn, so the socket the queue has to wait on is a real one.
          findDuoChat().vm.$emit('send-chat-prompt', 'first turn');
          await waitForPromises();
          triggerStreamEvent('open');
          await queuePrompt('queued text');

          workflowStreamFactory.getWorkflowStream().connect.mockClear();
          wrapper.vm.isWaitingOnPrompt = false;
          await waitForPromises();
        });

        it('holds the queued prompt', () => {
          expect(queuedPrompts()).toEqual([queued('queued text')]);
          expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
        });

        it('sends it once the socket closes', async () => {
          expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();

          triggerStreamEvent('close', { type: 'close', code: 1000 });
          await waitForPromises();

          expect(queuedPrompts()).toEqual([]);
          expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
        });
      });

      it('does not drain the queue while the component is being destroyed', async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');

        createWorkflowMutationMock.mockClear();
        workflowStreamFactory.getWorkflowStream().connect.mockClear();

        // beforeDestroy sets isWaitingOnPrompt = false.
        wrapper.destroy();
        await waitForPromises();

        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });
    });

    // Regression: picking another thread from the history list unmounts the state
    // manager and mounts it again against that thread's workflow, restoring the queue
    // from sessionStorage on the way. Those prompts were typed in the thread the user
    // left, so they must not follow them into this one.
    describe('when mounted for a thread the prompts were not typed in', () => {
      const storedQueue = [{ id: 'q1', prompt: createUserPrompt({ text: 'from elsewhere' }) }];

      const mountWithStoredQueue = async (queueOwner) => {
        // The outer beforeEach already mounted one; it shares the stream singleton
        // these examples assert against, so it has to go before the next mount.
        wrapper.destroy();

        getSessionStorageValue.mockImplementation((key) =>
          key === DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY
            ? { exists: true, value: { workflowId: queueOwner, prompts: storedQueue } }
            : { exists: true, value: { workflowId: MOCK_WORKFLOW_ID } },
        );

        createComponent({
          propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
        });
        await waitForPromises();
      };

      it('drops a queue stored against another workflow', async () => {
        await mountWithStoredQueue('gid://gitlab/Ai::DuoWorkflows::Workflow/999');

        expect(queuedPrompts()).toEqual([]);
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });

      it('restores and fires a queue stored against the workflow it is showing', async () => {
        await mountWithStoredQueue(MOCK_WORKFLOW_ID);

        // Restored, then drained as soon as the hydrated thread turned out to be idle.
        expect(queuedPrompts()).toEqual([]);
        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });
    });

    // Regression: the queue outlived the thread it was typed in, so picking another
    // agent from the rail -- which starts a new chat by routing here -- fired the old
    // thread's prompts at it.
    describe('when a new chat replaces the thread the prompts were typed in', () => {
      beforeEach(async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');

        mockRoute.name = AGENTIC_CHAT_NEW_ROUTE;
        await waitForPromises();
      });

      it('drops the queue instead of firing it at the new chat', () => {
        expect(queuedPrompts()).toEqual([]);
        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });
    });

    // Regression: the carry-over exemption keyed off "the agent was reused", which a
    // hand-typed base command also satisfies. Sending at an approval gate made that
    // reachable, so /new started a blank chat and the old queue fired into it.
    describe('when the user types a base command with prompts still queued', () => {
      beforeEach(async () => {
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('queued text');
        wrapper.vm.isWaitingOnPrompt = false;

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: GENIE_CHAT_NEW_MESSAGE }),
        );
        await waitForPromises();
      });

      it('drops the queue rather than firing it at the chat the command starts', () => {
        expect(queuedPrompts()).toEqual([]);
        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });
    });

    describe('when a turn ends at a tool approval gate', () => {
      const pendingToolRequest = {
        content: 'May I run this command?',
        role: 'assistant',
        requestId: 'm1',
        message_type: 'request',
        tool_info: { name: 'run_command', args: { command: 'ls -la' } },
      };

      beforeEach(async () => {
        // A tool call can only be pending on a workflow that already exists.
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        wrapper.vm.isWaitingOnPrompt = true;
        await queuePrompt('then do this');
        await store.dispatch('setMessages', [pendingToolRequest]);

        // The chat agent reports TOOL_CALL_APPROVAL_REQUIRED, and the socket closing
        // on a non-RUNNING status ends the turn before the user has answered.
        wrapper.vm.workflowStatus = DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED;
        wrapper.vm.isWaitingOnPrompt = false;
        await waitForPromises();
      });

      it('holds the queue rather than cancelling the pending tool call', () => {
        expect(queuedPrompts()).toEqual([queued('then do this')]);
        expect(createWorkflowMutationMock).not.toHaveBeenCalled();
        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });

      // Regression: the approval gate was folded into the composer's gate as well,
      // so a prompt typed while the approval was up got queued behind it. Sending
      // one denies the tool call, and that is the user's way out of an approval they
      // do not want to answer -- but only for the prompt they are typing now.
      it('still lets the composer send', () => {
        expect(findDuoChat().props('canSendPrompt')).toBe(true);
      });

      describe('and the user submits another prompt instead of answering', () => {
        beforeEach(async () => {
          findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'never mind' }));
          await waitForPromises();
        });

        it('sends it straight away', () => {
          expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
            expect.objectContaining({ userPrompt: createUserPrompt({ text: 'never mind' }) }),
          );
          expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
        });

        it('leaves the prompt queued before the approval where it was', () => {
          expect(queuedPrompts()).toEqual([queued('then do this')]);
        });
      });

      describe('once the approved tool call finishes', () => {
        beforeEach(async () => {
          findDuoChat().vm.$emit('approve-tool');
          await nextTick();
          workflowStreamFactory.getWorkflowStream().connect.mockClear();

          // The tool ran, so the workflow leaves the approval status.
          await store.dispatch('setMessages', [
            pendingToolRequest,
            { content: 'Done', role: 'assistant', requestId: 'm2', message_type: 'agent' },
          ]);
          wrapper.vm.workflowStatus = DUO_WORKFLOW_STATUS_RUNNING;
          await nextTick();

          wrapper.vm.workflowStatus = DUO_WORKFLOW_STATUS_INPUT_REQUIRED;
          await waitForPromises();
        });

        it('sends the queued prompt', () => {
          expect(queuedPrompts()).toEqual([]);
          expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
        });
      });
    });
  });

  describe('Global state watchers', () => {
    describe('duoChatGlobalState.commands', () => {
      beforeEach(() => {
        createComponent({
          propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
        });
      });

      describe('when commands are added', () => {
        it('starts a new chat and sends the command question', async () => {
          const testQuestion = 'What is GitLab CI/CD?';

          // Trigger the watcher by adding a command to the global state
          duoChatGlobalState.commands = [{ question: testQuestion }];
          await waitForPromises();

          // Assert that onNewChat() side effects occurred
          expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);
          expect(findChatLoadingState().exists()).toBe(false);

          // Assert that onSendChatPrompt() side effects occurred
          expect(findDuoChat().props('isLoading')).toBe(true);
          expect(createWorkflowMutationMock).toHaveBeenCalledWith(
            expect.objectContaining({
              projectId: MOCK_PROJECT_ID,
              goal: testQuestion,
            }),
          );
          expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
          expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
            expect.any(Object),
            expect.objectContaining({
              content: testQuestion,
              role: 'user',
              requestId: DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
            }),
          );
        });

        it('does not trigger chat when commands array is empty', async () => {
          jest.clearAllMocks();

          duoChatGlobalState.commands = [];
          await nextTick();

          expect(actionSpies.setMessages).not.toHaveBeenCalled();
          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
          expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
        });
      });

      describe('when a command has autoSend: false', () => {
        it('resets the thread but does not send a prompt or create a workflow', async () => {
          duoChatGlobalState.commands = [
            { agent: { name: 'Permissions Assistant' }, resourceId: '1', autoSend: false },
          ];
          await waitForPromises();

          // onNewChat() side effects should have run
          expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);

          // onSendChatPrompt() should NOT have been called
          expect(createWorkflowMutationMock).not.toHaveBeenCalled();
          expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
        });

        it('passes currentWelcomeMessage to WebAgenticDuoChat as emptyStateTitle', async () => {
          const welcomeMessage = 'Tell me what you need.';
          duoChatGlobalState.commands = [
            {
              agent: { name: 'Permissions Assistant' },
              resourceId: '1',
              autoSend: false,
              welcomeMessage,
            },
          ];
          await waitForPromises();

          expect(findDuoChat().props('emptyStateTitle')).toBe(welcomeMessage);
        });

        it('passes currentPredefinedPrompts to WebAgenticDuoChat as predefinedPrompts', async () => {
          const predefinedPrompts = ['How do I fork?', 'What is a pipeline?'];
          duoChatGlobalState.commands = [
            {
              agent: { name: 'Permissions Assistant' },
              resourceId: '1',
              autoSend: false,
              predefinedPrompts,
            },
          ];
          await waitForPromises();

          expect(findDuoChat().props('predefinedPrompts')).toEqual(predefinedPrompts);
        });

        it('clears welcomeMessage and predefinedPrompts when onNewChat is called again', async () => {
          duoChatGlobalState.commands = [
            {
              agent: { name: 'Permissions Assistant' },
              resourceId: '1',
              autoSend: false,
              welcomeMessage: 'Hello!',
              predefinedPrompts: ['Prompt A'],
            },
          ];
          await waitForPromises();

          await wrapper.vm.onNewChat();

          expect(findDuoChat().props('emptyStateTitle')).toBeNull();
          expect(findDuoChat().props('predefinedPrompts')).toEqual(
            MOCK_CONTEXT_PRESETS_RESPONSE.data.aiChatContextPresets.questions,
          );
        });

        it('does not send command-scoped context once onNewChat is called again', async () => {
          const formContextEnvelope = {
            category: 'form_context',
            content: '{"form_id":"ask-duo-pat"}',
            metadata: '{}',
          };
          duoChatGlobalState.commands = [
            {
              agent: { name: 'Permissions Assistant' },
              resourceId: '1',
              autoSend: false,
              additionalContext: [formContextEnvelope],
            },
          ];
          await waitForPromises();

          await wrapper.vm.onNewChat();

          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
          );
          await waitForPromises();

          const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;
          const { additionalContext } = call[0];

          expect(additionalContext.filter((c) => c.category === 'form_context')).toHaveLength(0);
        });
      });
    });
  });

  describe('onNewChat', () => {
    it.each`
      referenceWithVersion
      ${DUO_WORKFLOW_CHAT_DEFINITION}
      ${DUO_WORKFLOW_NEW_CHAT_DEFINITION}
    `(
      'clears selectedFoundationalAgent when referenceWithVersion is $referenceWithVersion',
      async ({ referenceWithVersion }) => {
        createComponent();
        await waitForPromises();

        wrapper.vm.selectedFoundationalAgent = { referenceWithVersion };

        await wrapper.vm.onNewChat();
        await nextTick();

        expect(wrapper.vm.selectedFoundationalAgent).toBeNull();
      },
    );
  });

  describe('when socket connection terminates', () => {
    beforeEach(async () => {
      flowStatusQueryMock.mockResolvedValueOnce({
        data: {
          duoWorkflowWorkflows: {
            edges: [
              {
                node: {
                  id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/456',
                  status: DUO_WORKFLOW_STATUS_RUNNING,
                },
              },
            ],
          },
        },
      });
      createComponent();
      wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
      wrapper.vm.workflowStatus = DUO_WORKFLOW_STATUS_RUNNING;

      // Trigger a workflow to create the WebSocket connection
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();
    });

    // The queued one-shot above survives an example that never polls, so drop whatever is
    // left of the queue rather than leaving the next example to consume it.
    afterEach(() => {
      flowStatusQueryMock.mockReset().mockResolvedValue(DEFAULT_FLOW_STATUS_RESPONSE);
    });

    describe.each`
      case                           | status                                             | locked
      ${'still attached elsewhere'}  | ${DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED} | ${true}
      ${'reported as finished'}      | ${DUO_WORKFLOW_STATUS_FINISHED}                    | ${false}
      ${'reported as something new'} | ${'SOME_NEW_STATUS'}                               | ${false}
    `('and the code is 1013 and the flow is $case', ({ status, locked }) => {
      beforeEach(async () => {
        // Answer the very first poll, so the outer one-shot cannot pre-empt this status.
        flowStatusQueryMock.mockReset().mockResolvedValue(flowStatusResponse(status));

        // Suppress expected vue-apollo error for workflowStatus query
        // triggered when isFlowLocked becomes true and starts polling
        const errSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
        triggerStreamEvent('close', { type: 'close', code: 1013 });
        await waitForPromises();
        await nextTick();
        errSpy.mockRestore();
      });

      it('locks the chat only while another client still holds the flow', () => {
        expect(findDuoChat().props('isFlowLocked')).toBe(locked);
      });
    });

    describe('and the code is 1013 (close and try again)', () => {
      beforeEach(async () => {
        // Suppress expected vue-apollo error for workflowStatus query
        // triggered when isFlowLocked becomes true and starts polling
        const errSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
        triggerStreamEvent('close', { type: 'close', code: 1013 });
        await waitForPromises();
        await nextTick();
        errSpy.mockRestore();
      });

      it('keeps the chat enabled and marks the flow as locked', () => {
        expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: true });
        expect(findDuoChat().props('isFlowLocked')).toBe(true);
      });

      it('starts polling for workflow status', () => {
        expect(flowStatusQueryMock).toHaveBeenCalledWith({
          id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/456',
        });
      });

      it('does not poll for workflow status when workflowId is null', async () => {
        flowStatusQueryMock.mockClear();

        // Simulate stale localStorage scenario: isFlowLocked is true but workflowId is null
        wrapper.vm.workflowId = null;
        await nextTick();

        jest.advanceTimersByTime(3000);
        await waitForPromises();

        expect(flowStatusQueryMock).not.toHaveBeenCalled();
      });
    });

    describe('and the code is 4400 (invalid request)', () => {
      const checkpointMissingClose = {
        type: 'close',
        code: 4400,
        reason: 'Checkpoint ts-gone was not found in this session.',
      };
      const invalidRequestError =
        'Could not process the last message. Send a new message to try again.';

      const findChatErrors = () =>
        actionSpies.addDuoChatMessage.mock.calls.flatMap(([, message]) => message.errors ?? []);

      beforeEach(() => {
        actionSpies.addDuoChatMessage.mockClear();
      });

      it.each([
        ['a missing resume checkpoint', checkpointMissingClose],
        ['any other rejection', { type: 'close', code: 4400, reason: 'Goal cannot be empty' }],
      ])('reports the same message for %s', async (_, closeEvent) => {
        triggerStreamEvent('close', closeEvent);
        await nextTick();

        expect(findChatErrors()).toEqual([invalidRequestError]);
      });

      it('reports the backend reason to Sentry rather than to the user', async () => {
        triggerStreamEvent('close', checkpointMissingClose);
        await nextTick();

        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          expect.any(Error),
          expect.objectContaining({ extra: expect.objectContaining(checkpointMissingClose) }),
        );
        expect(findChatErrors()).not.toContain(checkpointMissingClose.reason);
      });

      // The failed-retry marker on its own reads as "try again", which fails identically.
      it('reports it even while a retry is in flight', async () => {
        wrapper.vm.retryingMessageId = 'message-1';

        triggerStreamEvent('close', checkpointMissingClose);
        await nextTick();

        expect(findChatErrors()).toEqual([invalidRequestError]);
      });
    });

    describe('when status changes', () => {
      beforeEach(async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        triggerStreamEvent('close', { type: 'close', code: 1013 });
        await waitForPromises();
        await nextTick();
      });

      it('unlocks the flow when the status becomes available', async () => {
        expect(findDuoChat().props('isFlowLocked')).toBe(true);

        // Next poll will give us an updated status
        flowStatusQueryMock.mockResolvedValueOnce({
          data: {
            duoWorkflowWorkflows: {
              edges: [
                {
                  node: {
                    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/456',
                    status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
                  },
                },
              ],
            },
          },
        });

        jest.advanceTimersByTime(3000);
        await waitForPromises();
        await nextTick();

        expect(findDuoChat().props('isFlowLocked')).toBe(false);
      });

      it('sends the next queued prompt once the flow unlocks and is idle', async () => {
        findDuoChat().vm.$emit('queue-chat-prompt', 'queued while locked');
        // A locked tab is not running a turn of its own.
        wrapper.vm.isWaitingOnPrompt = false;
        await nextTick();
        workflowStreamFactory.getWorkflowStream().connect.mockClear();

        flowStatusQueryMock.mockResolvedValueOnce({
          data: {
            duoWorkflowWorkflows: {
              edges: [
                {
                  node: {
                    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/456',
                    status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
                  },
                },
              ],
            },
          },
        });

        jest.advanceTimersByTime(3000);
        await waitForPromises();
        await nextTick();
        await waitForPromises();

        expect(findDuoChat().props('queuedPrompts')).toHaveLength(0);
        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('hydrates the active thread to reconnect', async () => {
        workflowEventsQueryMock.mockClear();

        jest.advanceTimersByTime(3000);
        await waitForPromises();
        await nextTick();

        expect(workflowEventsQueryMock).toHaveBeenCalledWith({ workflowId: MOCK_WORKFLOW_ID });
      });
    });
  });

  describe('when automatic reconnection is exhausted', () => {
    beforeEach(async () => {
      createComponent();
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();
    });

    it('does not render the connection error alert while the stream is healthy', () => {
      expect(findConnectionErrorAlert().exists()).toBe(false);
    });

    describe('once the stream reports max_retries_exceeded', () => {
      beforeEach(async () => {
        triggerStreamEvent('error', { type: 'error', reason: 'max_retries_exceeded' });
        await nextTick();
      });

      it('renders the connection error alert', () => {
        expect(findConnectionErrorAlert().exists()).toBe(true);
      });

      it('does not report the exhausted retries as a chat error', () => {
        expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ errors: expect.anything() }),
        );
        expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
      });

      it('stops the loading and tool approval indicators', () => {
        expect(findDuoChat().props('isLoading')).toBe(false);
        expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      });

      it('disables the prompt and points the user at reconnecting', () => {
        expect(findDuoChat().props('chatState')).toEqual({
          isEnabled: false,
          reason: 'Reconnect to continue this conversation.',
        });
      });

      describe('and another message is sent anyway', () => {
        beforeEach(async () => {
          workflowStreamFactory.getWorkflowStream().connect.mockClear();
          actionSpies.addDuoChatMessage.mockClear();
          findDuoChat().vm.$emit(
            'send-chat-prompt',
            createUserPrompt({ text: 'another question' }),
          );
          await waitForPromises();
          await nextTick();
        });

        it('does not start a new goal', () => {
          expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
        });

        it('does not add the message to the chat log', () => {
          expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalled();
        });

        it('keeps the alert visible', () => {
          expect(findConnectionErrorAlert().exists()).toBe(true);
        });
      });

      it('still allows starting a new chat', async () => {
        findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: '/reset' }));
        await waitForPromises();
        await nextTick();

        expect(findConnectionErrorAlert().exists()).toBe(false);
        expect(findDuoChat().props('chatState')).toEqual({ isEnabled: true, reason: '' });
      });

      describe('and the user asks to reconnect', () => {
        beforeEach(async () => {
          findConnectionErrorAlert().vm.$emit('retry');
          await nextTick();
        });

        it('reconnects the stream', () => {
          expect(workflowStreamFactory.getWorkflowStream().retry).toHaveBeenCalled();
        });

        it('hides the alert and waits on the stream again', () => {
          expect(findConnectionErrorAlert().exists()).toBe(false);
          expect(findDuoChat().props('isLoading')).toBe(true);
        });

        it('re-enables the prompt', () => {
          expect(findDuoChat().props('chatState')).toEqual({ isEnabled: true, reason: '' });
        });
      });
    });

    it('reports any other stream error as a chat error', () => {
      triggerStreamEvent('error', { type: 'error', origin: 'decode', message: 'read failed' });

      expect(findConnectionErrorAlert().exists()).toBe(false);
      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          errors: ['Error: Unable to connect to workflow service. Please try again.'],
        }),
      );
    });
  });

  describe('Socket cleanup', () => {
    it('clears state on component destroy when stream is not active', () => {
      createComponent();

      wrapper.destroy();

      expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);
    });

    it('emits "change-title" event in beforeDestroy hook', () => {
      expect(wrapper?.emitted('change-title')).toBeUndefined();

      // The header owner emits the clear as it unmounts, so it has to be real.
      // `stubs: { DuoAgenticChatHeader: false }` does not un-stub here.
      createComponent({ stubs: { DuoAgenticChatHeader } });

      let changeTitleEmitted = false;
      wrapper.vm.$on('change-title', () => {
        changeTitleEmitted = true;
      });

      wrapper.destroy();

      expect(changeTitleEmitted).toBe(true);
    });

    it('sets isProcessingToolApproval to false on socket close when not waiting for approval', async () => {
      createComponent();
      await waitForPromises();

      wrapper.vm.isProcessingToolApproval = true;
      wrapper.vm.workflowStatus = 'completed';
      wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

      wrapper.vm.startWorkflow({
        userPrompt: createUserPrompt({ text: 'test question' }),
        additionalContext: wrapper.vm.additionalContext,
      });

      expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();

      triggerStreamEvent('close', { type: 'close' });

      expect(findDuoChat().props('isToolApprovalProcessing')).toBe(false);
      expect(findDuoChat().props('isLoading')).toBe(false);
    });

    it('keeps isProcessingToolApproval true on socket close when workflow is RUNNING', async () => {
      createComponent();
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      findDuoChat().vm.$emit('approve-tool');
      await nextTick();

      triggerStreamEvent('message', {
        type: 'message',
        data: {
          requestID: 'request-1',
          newCheckpoint: {
            checkpoint: {
              channel_values: {
                ui_chat_log: [{ content: 'Running', message_type: 'agent' }],
              },
            },
            status: DUO_WORKFLOW_STATUS_RUNNING,
          },
        },
      });
      await waitForPromises();
      await nextTick();

      triggerStreamEvent('close', { type: 'close' });
      await nextTick();

      expect(findDuoChat().props('isToolApprovalProcessing')).toBe(true);
    });
  });

  describe('toggle position based on chatMode', () => {
    const findAgenticModeToggle = () => wrapper.findComponent(AgenticModeToggle);

    beforeEach(() => {
      jest.clearAllMocks();
    });

    it('shows toggle as checked when in agentic mode', () => {
      duoChatGlobalState.chatMode = 'agentic';
      createComponent({
        propsData: { forceAgenticModeForCoreDuoUsers: false },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              isClassicAvailable: true,
            },
          },
        },
      });

      expect(findAgenticModeToggle().props('value')).toBe(true);
    });

    it('shows toggle as unchecked when in classic mode', () => {
      duoChatGlobalState.chatMode = 'classic';
      createComponent({
        propsData: { forceAgenticModeForCoreDuoUsers: false },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              isClassicAvailable: true,
            },
          },
        },
      });

      expect(findAgenticModeToggle().props('value')).toBe(false);
    });
  });

  describe('onBackToList', () => {
    beforeEach(() => {
      createComponent();
    });

    it('pushes the history route', async () => {
      await waitForPromises();

      wrapper.vm.onBackToList();
      await nextTick();

      expect(mockRouter.push).toHaveBeenCalledWith({ name: AGENTIC_CHAT_HISTORY_ROUTE });
    });

    it('clears the active thread', async () => {
      const clearActiveWorkflowSpy = jest.spyOn(wrapper.vm, 'clearActiveWorkflow');

      wrapper.vm.onBackToList();
      await nextTick();

      expect(clearActiveWorkflowSpy).toHaveBeenCalled();
    });

    it('clears inactive thread state when going back to list', async () => {
      getSessionStorageValue.mockReturnValue({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });
      workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE });
      createComponent();
      await waitForPromises();

      expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']({})).toBeDefined();

      wrapper.vm.onBackToList();
      await nextTick();

      expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']).toBeUndefined();
    });
  });

  describe('web search', () => {
    beforeEach(() => {
      createComponent();
    });

    describe('@web-search-toggled', () => {
      it('calls updateWebSearchMutation when workflowId exists', async () => {
        createComponent();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        findPromptInputActions().vm.$emit('update:web-search-enabled', true);
        await waitForPromises();

        expect(updateWebSearchMutationMock).toHaveBeenCalledWith({
          workflowId: MOCK_WORKFLOW_ID,
          webSearchEnabled: true,
        });
      });

      it('does not call mutation when workflowId is not set', async () => {
        createComponent();

        findPromptInputActions().vm.$emit('update:web-search-enabled', true);
        await waitForPromises();

        expect(updateWebSearchMutationMock).not.toHaveBeenCalled();
      });

      // The flow service reads web_search_enabled off the workflow record when the
      // turn starts, so the turn must not outrun the write.
      it('does not start the turn until the preference write has landed', async () => {
        createComponent();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;
        workflowStreamFactory.getWorkflowStream().connect.mockClear();

        let resolveUpdate;
        updateWebSearchMutationMock.mockReturnValueOnce(
          new Promise((resolve) => {
            resolveUpdate = resolve;
          }),
        );

        findPromptInputActions().vm.$emit('update:web-search-enabled', true);
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();

        resolveUpdate(MOCK_UPDATE_WEB_SEARCH_MUTATION_RESPONSE);
        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('keeps the toggled value when the mutation succeeds', async () => {
        createComponent();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        findPromptInputActions().vm.$emit('update:web-search-enabled', true);
        await waitForPromises();

        expect(wrapper.vm.webSearchEnabled).toBe(true);
      });

      it('persists rapid toggles in click order', async () => {
        createComponent();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        findPromptInputActions().vm.$emit('update:web-search-enabled', true);
        findPromptInputActions().vm.$emit('update:web-search-enabled', false);
        await waitForPromises();

        expect(updateWebSearchMutationMock.mock.calls.map(([variables]) => variables)).toEqual([
          { workflowId: MOCK_WORKFLOW_ID, webSearchEnabled: true },
          { workflowId: MOCK_WORKFLOW_ID, webSearchEnabled: false },
        ]);
      });

      describe.each`
        description         | mockFailure
        ${'rejects'}        | ${() => updateWebSearchMutationMock.mockRejectedValueOnce(new Error('mutation failed'))}
        ${'returns errors'} | ${() => updateWebSearchMutationMock.mockResolvedValueOnce({ data: { updateDuoWorkflowWebSearch: { workflow: null, errors: ['Workflow not found'] } } })}
      `('when the mutation $description', ({ mockFailure }) => {
        // Switch web search on successfully first, so the failing click below has a
        // non-default value to fall back to.
        beforeEach(async () => {
          createComponent();
          wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

          findPromptInputActions().vm.$emit('update:web-search-enabled', true);
          await waitForPromises();

          mockFailure();
        });

        it('restores the value the user saw before the click', async () => {
          findPromptInputActions().vm.$emit('update:web-search-enabled', false);
          await waitForPromises();

          expect(wrapper.vm.webSearchEnabled).toBe(true);
        });

        // The stored preference has to track what the toggle displays, or the next
        // new thread would start from a value the user never ended up selecting.
        it('rolls the stored preference back too', async () => {
          findPromptInputActions().vm.$emit('update:web-search-enabled', false);
          await waitForPromises();

          expect(saveWebSearchPreference).toHaveBeenLastCalledWith(true);
        });

        it('reports the failure to Sentry without adding a message to the conversation', async () => {
          actionSpies.addDuoChatMessage.mockClear();

          findPromptInputActions().vm.$emit('update:web-search-enabled', false);
          await waitForPromises();

          expect(captureExceptionForDuoChat).toHaveBeenCalled();
          expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalled();
        });

        it('leaves the newly selected thread alone when the user switches threads mid-flight', async () => {
          findPromptInputActions().vm.$emit('update:web-search-enabled', false);
          wrapper.vm.workflowId = 'gid://gitlab/Ai::DuoWorkflows::Workflow/999';
          await waitForPromises();

          expect(wrapper.vm.webSearchEnabled).toBe(false);
        });
      });
    });

    describe('restoring the web search preference', () => {
      const [MOCK_WORKFLOW_NODE] = MOCK_WORKFLOW_EVENTS_RESPONSE.duoWorkflowWorkflows.nodes;
      const workflowEventsResponseWith = (webSearchEnabled) => ({
        data: {
          duoWorkflowWorkflows: {
            nodes: [{ ...MOCK_WORKFLOW_NODE, webSearchEnabled }],
          },
        },
      });

      it('applies the value stored on the workflow record', async () => {
        workflowEventsQueryMock.mockResolvedValueOnce(workflowEventsResponseWith(true));
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        await wrapper.vm.loadActiveWorkflow();
        await nextTick();

        expect(findPromptInputActions().props('webSearchEnabled')).toBe(true);
      });

      it('ignores a response for a thread the user has already navigated away from', async () => {
        let resolveWorkflowEvents;
        workflowEventsQueryMock.mockReturnValueOnce(
          new Promise((resolve) => {
            resolveWorkflowEvents = resolve;
          }),
        );
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        const loaded = wrapper.vm.loadActiveWorkflow();
        wrapper.vm.workflowId = 'gid://gitlab/Ai::DuoWorkflows::Workflow/999';
        resolveWorkflowEvents(workflowEventsResponseWith(true));
        await loaded;

        expect(wrapper.vm.webSearchEnabled).toBe(false);
      });

      // A thread with no workflow record yet has nothing to read the toggle back
      // from, so the stored preference stands in for it.
      describe('from localStorage', () => {
        const webSearchAvailable = {
          glFeatures: { dapWebSearch: true },
          webSearchAllowedForGroup: true,
        };

        it('starts a thread from the stored preference', () => {
          loadWebSearchPreference.mockReturnValue(true);
          createComponent({ provide: webSearchAvailable });

          expect(wrapper.vm.webSearchEnabled).toBe(true);
        });

        it.each`
          scenario                               | provide
          ${'the group has not allowed it'}      | ${{ glFeatures: { dapWebSearch: true }, webSearchAllowedForGroup: false }}
          ${'the feature flag is off'}           | ${{ glFeatures: { dapWebSearch: false }, webSearchAllowedForGroup: true }}
          ${'the mount provides no gate at all'} | ${{}}
        `('is ignored when $scenario', ({ provide }) => {
          loadWebSearchPreference.mockReturnValue(true);
          createComponent({ provide });

          expect(wrapper.vm.webSearchEnabled).toBe(false);
        });

        it('is applied again when a new chat starts', async () => {
          loadWebSearchPreference.mockReturnValue(true);
          createComponent({ provide: webSearchAvailable });
          wrapper.vm.webSearchEnabled = false;

          await wrapper.vm.onNewChat();

          expect(wrapper.vm.webSearchEnabled).toBe(true);
        });

        it('loses to the workflow record when an existing thread is opened', async () => {
          loadWebSearchPreference.mockReturnValue(true);
          createComponent({ provide: webSearchAvailable });
          workflowEventsQueryMock.mockResolvedValueOnce(workflowEventsResponseWith(false));
          wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

          await wrapper.vm.loadActiveWorkflow();

          expect(wrapper.vm.webSearchEnabled).toBe(false);
        });

        it('is written on every toggle, with or without a workflow', () => {
          createComponent({ provide: webSearchAvailable });

          findPromptInputActions().vm.$emit('update:web-search-enabled', true);

          expect(saveWebSearchPreference).toHaveBeenCalledWith(true);
        });
      });
    });
  });

  describe('Agentic Toggle', () => {
    const findAgenticModeToggle = () => wrapper.findComponent(AgenticModeToggle);

    beforeEach(() => {
      duoChatGlobalState.chatMode = 'classic';
      jest.clearAllMocks();
      createComponent({
        propsData: { forceAgenticModeForCoreDuoUsers: false },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              isClassicAvailable: true,
            },
          },
        },
      });
    });

    it('calls setAgenticMode with the toggle value when toggle changes', async () => {
      const toggle = findAgenticModeToggle();

      // Toggle directly controls agentic mode - false means agentic mode is disabled
      toggle.vm.$emit('change', false);
      await nextTick();

      expect(setAgenticMode).toHaveBeenCalledWith({
        agenticMode: false,
        saveCookie: true,
      });
    });

    it('is enabled by default', () => {
      expect(findAgenticModeToggle().props('disabled')).toBe(false);
    });

    it('is disabled when the selected thread is archived', async () => {
      getSessionStorageValue.mockReturnValue({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });
      workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE });
      createComponent({
        propsData: { forceAgenticModeForCoreDuoUsers: false },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              isClassicAvailable: true,
              defaultNamespaceSelected: true,
            },
          },
        },
      });
      await waitForPromises();

      expect(findAgenticModeToggle().props('disabled')).toBe(true);
    });

    it.each([false, true])(
      'when forceAgenticModeForCoreDuoUsers is %s',
      (forceAgenticModeForCoreDuoUsers) => {
        createComponent({
          propsData: { forceAgenticModeForCoreDuoUsers },
          provide: {
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              defaultProps: {
                isClassicAvailable: true,
              },
            },
          },
        });
        expect(findAgenticModeToggle().exists()).toBe(!forceAgenticModeForCoreDuoUsers);
      },
    );
  });

  describe('Agentic chat user model selection', () => {
    const findModelSelectDropdown = () => wrapper.findComponent(ModelSelectDropdown);

    describe('when user model selection is enabled', () => {
      beforeEach(async () => {
        createComponent({
          propsData: { userModelSelectionEnabled: true, rootNamespaceId: MOCK_NAMESPACE_ID },
        });
        await waitForPromises();
      });

      it('renders `ModelSelectDropdown` in the correct slot', () => {
        expect(findModelSelectDropdown().exists()).toBe(true);
        const slot = findDuoChat().vm.$slots['agentic-model'];
        const vnode = typeof slot === 'function' ? slot()[0] : slot[0];

        const testId = vnode.props
          ? vnode.props['data-testid'] // Vue 3
          : vnode.data.attrs['data-testid']; // Vue 2

        expect(testId).toBe('model-dropdown-container');
      });

      describe('when availableModels query is loading', () => {
        it('triggers a loading state', async () => {
          // Use a never-resolving handler so models stay in loading state
          const pendingModelsHandler = jest.fn().mockReturnValue(new Promise(() => {}));
          createComponent({
            propsData: { userModelSelectionEnabled: true, rootNamespaceId: MOCK_NAMESPACE_ID },
            apolloHandlers: [[getAiChatAvailableModels, pendingModelsHandler]],
          });
          getCurrentModel.mockClear();
          await waitForPromises();

          expect(findModelSelectDropdown().props('isLoading')).toBe(true);
          expect(findModelSelectDropdown().props('selectedOption')).toBe(null);
          expect(getCurrentModel).not.toHaveBeenCalled();
        });
      });

      describe('when availableModels query has loaded', () => {
        it('invokes `getCurrentModel()` with the correct arguments', async () => {
          await waitForPromises();

          expect(getCurrentModel).toHaveBeenCalledWith({
            availableModels: MOCK_MODEL_LIST_ITEMS,
            pinnedModel: null,
            selectedModel: null,
          });
        });

        it('passes the correct props to `ModelSelectDropdown`', async () => {
          await waitForPromises();

          expect(findModelSelectDropdown().props('isLoading')).toBe(false);
          expect(findModelSelectDropdown().props('disabled')).toBe(false);
          expect(findModelSelectDropdown().props('placeholderDropdownText')).toBe('Select a model');
          expect(findModelSelectDropdown().props('items')).toMatchObject(MOCK_MODEL_LIST_ITEMS);
          expect(findModelSelectDropdown().props('selectedOption')).toMatchObject(
            MOCK_GITLAB_DEFAULT_MODEL_ITEM,
          );
        });
      });

      it('saves the model and updates tracker context without starting a new chat when model is selected', async () => {
        await waitForPromises();

        const selectedModel = MOCK_MODEL_LIST_ITEMS[1];
        const onNewChatSpy = jest.spyOn(wrapper.vm, 'onNewChat');

        await findModelSelectDropdown().vm.$emit('select', selectedModel.value);

        expect(saveModel).toHaveBeenCalledWith(selectedModel);
        expect(onNewChatSpy).not.toHaveBeenCalled();
      });

      it('disables dropdown when pinned model is set', async () => {
        const pinnedModel = { text: 'Pinned Model', value: 'pinned/model' };
        checkModelSelectionDisabled.mockReturnValue(true);

        createComponent({
          propsData: { userModelSelectionEnabled: true, rootNamespaceId: MOCK_NAMESPACE_ID },
          data: { pinnedModel },
        });
        await waitForPromises();

        expect(findModelSelectDropdown().props('disabled')).toBe(true);
      });
    });

    describe('when user model selection is disabled', () => {
      beforeEach(() => {
        createComponent({ propsData: { userModelSelectionEnabled: false } });
      });

      it('does not render `ModelSelectDropdown`', () => {
        expect(findModelSelectDropdown().exists()).toBe(false);
      });
    });
  });

  describe('prompt input actions', () => {
    it.each([true, false])(
      'renders the input actions in the textarea toolbar when newModelSelection is %s',
      async (newModelSelection) => {
        createComponent({ provide: { glFeatures: { newModelSelection } } });
        await waitForPromises();

        expect(findPromptInputActions().exists()).toBe(true);
        expect(findPromptInputActions().props('webSearchEnabled')).toBe(false);
      },
    );

    it('disables the input actions while chat is disabled', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });
      createComponent();
      await waitForPromises();

      expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: false });
      expect(findPromptInputActions().props('disabled')).toBe(true);
    });

    // Reaches the toolbar through the same slot scope that carries `dispatchAction`.
    it('forwards goal availability from the composer slot scope', async () => {
      createComponent();
      await waitForPromises();

      expect(findPromptInputActions().props('goalAvailable')).toBe(false);
    });
  });

  describe('when newModelSelection feature flag is enabled', () => {
    const findModelSelectDropdown = () => wrapper.findComponent(ModelSelectDropdown);
    const findChatModelSelector = () => wrapper.findComponent(ChatModelSelector);
    const findAgenticModeToggle = () => wrapper.findComponent(AgenticModeToggle);
    const findUseClassicChatButton = () => wrapper.findComponentByTestId('use-classic-chat-button');

    const createComponentWithFlag = ({ propsData = {}, provide = {}, ...options } = {}) => {
      createComponent({
        propsData: {
          userModelSelectionEnabled: true,
          rootNamespaceId: MOCK_NAMESPACE_ID,
          ...propsData,
        },
        provide: { glFeatures: { newModelSelection: true }, ...provide },
        ...options,
      });
    };

    beforeEach(() => {
      availableModelsQueryHandlerMock.mockClear();
    });

    describe('when user model selection is enabled', () => {
      beforeEach(async () => {
        createComponentWithFlag();
        await waitForPromises();
      });

      it('renders `ChatModelSelector` instead of `ModelSelectDropdown`', () => {
        expect(findChatModelSelector().exists()).toBe(true);
        expect(findModelSelectDropdown().exists()).toBe(false);
      });

      it('passes the chat context to `ChatModelSelector`', () => {
        expect(findChatModelSelector().props()).toMatchObject({
          rootNamespaceId: MOCK_NAMESPACE_ID,
          namespaceId: null,
          projectId: null,
          disabled: false,
          showClassicChatButton: false,
        });
      });

      it('leaves the available models query to `ChatModelSelector`', () => {
        expect(availableModelsQueryHandlerMock).not.toHaveBeenCalled();
      });

      it('does not provide the legacy header row slots', () => {
        expect(findDuoChat().vm.$scopedSlots['agentic-model']).toBeUndefined();
        expect(findDuoChat().vm.$scopedSlots['agentic-switch']).toBeUndefined();
        expect(findDuoChat().vm.$scopedSlots['textarea-toolbar']).toBeDefined();
      });
    });

    describe('when `ChatModelSelector` resolves a model', () => {
      beforeEach(async () => {
        createComponentWithFlag();
        await waitForPromises();

        findChatModelSelector().vm.$emit('change', {
          currentModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[1],
          defaultModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[0],
        });
        await nextTick();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();
      });

      it('builds the websocket url with the emitted models', () => {
        expect(WorkflowSocketUtils.buildWebsocketUrl).toHaveBeenCalledWith(
          expect.objectContaining({
            currentModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[1],
            defaultModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[0],
          }),
        );
      });
    });

    describe('when a model is selected', () => {
      let onNewChatSpy;

      beforeEach(async () => {
        onNewChatSpy = jest.spyOn(DuoAgenticChatStateManager.methods, 'onNewChat');
        createComponentWithFlag();
        await waitForPromises();
        onNewChatSpy.mockClear();

        findChatModelSelector().vm.$emit('change', {
          currentModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[1],
          defaultModel: MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[0],
        });
        await nextTick();
      });

      it('keeps the current conversation instead of starting a new chat', () => {
        expect(onNewChatSpy).not.toHaveBeenCalled();
      });
    });

    describe('when the model selector is not rendered but the agentic toggle conditions hold', () => {
      beforeEach(async () => {
        createComponentWithFlag({
          propsData: {
            userModelSelectionEnabled: false,
            forceAgenticModeForCoreDuoUsers: false,
          },
          provide: {
            glFeatures: { newModelSelection: true },
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              defaultProps: {
                isClassicAvailable: true,
              },
            },
          },
        });
        await waitForPromises();
      });

      it('renders the standalone non-agentic chat button in the textarea toolbar slot', () => {
        expect(findChatModelSelector().exists()).toBe(false);
        expect(findAgenticModeToggle().exists()).toBe(false);
        expect(findUseClassicChatButton().exists()).toBe(true);

        const slot = findDuoChat().vm.$scopedSlots['textarea-toolbar'];

        expect(slot()).not.toHaveLength(0);
      });

      it('switches to classic mode when the standalone button is clicked', async () => {
        findUseClassicChatButton().vm.$emit('click');
        await nextTick();

        expect(setAgenticMode).toHaveBeenCalledWith({ agenticMode: false, saveCookie: true });
      });
    });

    describe('when the model selector renders and the agentic toggle conditions hold', () => {
      beforeEach(async () => {
        createComponentWithFlag({
          propsData: { forceAgenticModeForCoreDuoUsers: false },
          provide: {
            glFeatures: { newModelSelection: true },
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              defaultProps: {
                isClassicAvailable: true,
              },
            },
          },
        });
        await waitForPromises();
      });

      it('moves the classic chat action into the selector and renders no standalone control', () => {
        expect(findChatModelSelector().props('showClassicChatButton')).toBe(true);
        expect(findAgenticModeToggle().exists()).toBe(false);
        expect(findUseClassicChatButton().exists()).toBe(false);
      });

      it('switches to classic mode on the selector switch-to-classic event', async () => {
        findChatModelSelector().vm.$emit('switch-to-classic');
        await nextTick();

        expect(setAgenticMode).toHaveBeenCalledWith({ agenticMode: false, saveCookie: true });
      });
    });
  });

  describe('when duoChatRedesign feature flag is enabled', () => {
    const findAgenticChatHeader = () => wrapper.findComponent(DuoAgenticChatHeader);

    const createComponentWithRedesign = ({ provide = {}, ...options } = {}) => {
      createComponent({
        provide: { glFeatures: { duoChatRedesign: true }, ...provide },
        ...options,
      });
    };

    describe('single header', () => {
      beforeEach(async () => {
        createComponentWithRedesign();
        await waitForPromises();
      });

      it('turns the single header on', () => {
        expect(findAgenticChatHeader().props('singleHeader')).toBe(true);
      });

      it('takes the orbit preference back from the header', async () => {
        expect(findAgenticChatHeader().props('orbitEnabled')).toBe(false);

        findAgenticChatHeader().vm.$emit('change', true);
        await nextTick();

        expect(findAgenticChatHeader().props('orbitEnabled')).toBe(true);
      });

      it('does not provide the subheader slot to the chat view', () => {
        expect(findDuoChat().vm.$scopedSlots.subheader).toBeUndefined();
      });

      it('leaves the chat view header off, so only its alerts render', () => {
        expect(findDuoChat().props('showHeader')).toBe(false);
      });

      it('hands the header owner no thread title for a fresh chat', () => {
        expect(findAgenticChatHeader().props('threadTitle')).toBe(null);
      });

      it('hands the header owner the goal once the first prompt creates the thread', async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: 'Summarize this project' }),
        );
        await waitForPromises();

        expect(findAgenticChatHeader().props('threadTitle')).toBe('Summarize this project');
      });

      it.each(['change-title', 'change-subtitle'])('forwards %s from the header owner', (event) => {
        findAgenticChatHeader().vm.$emit(event, 'Anything');

        expect(wrapper.emitted(event).at(-1)).toEqual(['Anything']);
      });
    });

    describe('with a custom agent selected', () => {
      beforeEach(async () => {
        createComponentWithRedesign({
          initialState: {
            currentAgent: { id: 'gid://gitlab/Ai::Catalog::Item/5', name: 'Security Analyst' },
          },
        });
        await waitForPromises();
      });

      it('hands the agent to the header owner', () => {
        expect(findAgenticChatHeader().props('currentAgent')).toMatchObject({
          name: 'Security Analyst',
        });
      });
    });

    describe('when the flag is disabled', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('provides the subheader slot to the chat view', () => {
        expect(findDuoChat().vm.$scopedSlots.subheader).toBeDefined();
      });

      it('shows the chat view header', () => {
        expect(findDuoChat().props('showHeader')).toBe(true);
      });

      it('does not hand the header owner a thread title when the first prompt creates the thread', async () => {
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: 'Summarize this project' }),
        );
        await waitForPromises();

        expect(findAgenticChatHeader().props('threadTitle')).toBe(null);
      });

      it('still mounts the header owner, with the single header off', () => {
        expect(findAgenticChatHeader().props('singleHeader')).toBe(false);
      });
    });
  });

  describe('availableModels query skip and variables', () => {
    beforeEach(() => {
      availableModelsQueryHandlerMock.mockClear();
    });

    describe('skip behavior', () => {
      it('skips the query when userModelSelectionEnabled is false', async () => {
        createComponent({
          propsData: { userModelSelectionEnabled: false, rootNamespaceId: MOCK_NAMESPACE_ID },
        });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).not.toHaveBeenCalled();
      });

      it('skips the query when none of projectId, namespaceId, or rootNamespaceId are provided', async () => {
        createComponent({ propsData: { userModelSelectionEnabled: true } });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).not.toHaveBeenCalled();
      });

      it('skips the query when newModelSelection is enabled', async () => {
        createComponent({
          propsData: { userModelSelectionEnabled: true, projectId: MOCK_PROJECT_ID },
          provide: { glFeatures: { newModelSelection: true } },
        });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).not.toHaveBeenCalled();
      });

      it('calls the query when newModelSelection is enabled alongside duoUiNext', async () => {
        createComponent({
          propsData: { userModelSelectionEnabled: true, projectId: MOCK_PROJECT_ID },
          provide: { glFeatures: { newModelSelection: true, duoUiNext: true } },
        });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).toHaveBeenCalled();
      });

      it('calls the query when at least one ID is provided', async () => {
        createComponent({
          propsData: { userModelSelectionEnabled: true, projectId: MOCK_PROJECT_ID },
        });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).toHaveBeenCalled();
      });
    });

    describe('variables prioritization', () => {
      it.each([
        [
          'sends only projectId when projectId is provided',
          {
            projectId: MOCK_PROJECT_ID,
            namespaceId: MOCK_NAMESPACE_ID,
            rootNamespaceId: 'gid://gitlab/Group/789',
          },
          { projectId: MOCK_PROJECT_ID },
        ],
        [
          'sends only namespaceId when projectId is not provided',
          { namespaceId: MOCK_NAMESPACE_ID, rootNamespaceId: 'gid://gitlab/Group/789' },
          { namespaceId: MOCK_NAMESPACE_ID },
        ],
        [
          'sends only rootNamespaceId when neither projectId nor namespaceId are provided',
          { rootNamespaceId: 'gid://gitlab/Group/789' },
          { rootNamespaceId: 'gid://gitlab/Group/789' },
        ],
      ])('%s', async (_, propsData, expectedVariables) => {
        createComponent({ propsData: { userModelSelectionEnabled: true, ...propsData } });
        await waitForPromises();

        expect(availableModelsQueryHandlerMock).toHaveBeenCalledWith(expectedVariables);
      });
    });
  });

  describe('catalogAgents query variables', () => {
    it('passes only projectId when both projectId and namespaceId are provided', async () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          namespaceId: MOCK_NAMESPACE_ID,
          resourceId: MOCK_RESOURCE_ID,
        },
      });
      await waitForPromises();

      expect(configuredAgentsQueryMock).toHaveBeenCalledWith({
        includeFoundationalConsumers: false,
        first: 20,
        projectId: MOCK_PROJECT_ID,
      });
    });

    it('passes only projectId when only projectId is provided', async () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
        },
      });
      await waitForPromises();

      expect(configuredAgentsQueryMock).toHaveBeenCalledWith({
        includeFoundationalConsumers: false,
        first: 20,
        projectId: MOCK_PROJECT_ID,
      });
    });

    it('passes only groupId when only namespaceId is provided', async () => {
      createComponent({
        propsData: {
          namespaceId: MOCK_NAMESPACE_ID,
          resourceId: MOCK_RESOURCE_ID,
        },
      });
      await waitForPromises();

      expect(configuredAgentsQueryMock).toHaveBeenCalledWith({
        includeFoundationalConsumers: false,
        first: 20,
        groupId: MOCK_NAMESPACE_ID,
      });
    });

    it('passes groupId when neither projectId nor namespaceId are provided', async () => {
      createComponent({
        propsData: {
          resourceId: MOCK_RESOURCE_ID,
        },
      });
      await waitForPromises();

      expect(configuredAgentsQueryMock).toHaveBeenCalledWith({
        includeFoundationalConsumers: false,
        first: 20,
        groupId: null,
      });
    });
  });

  describe('Fetching foundational agents', () => {
    describe('when project and namespace are available', () => {
      it('passes project_id and namespace_id', async () => {
        createComponent({
          propsData: { projectId: MOCK_PROJECT_ID, namespaceId: MOCK_NAMESPACE_ID },
        });

        await waitForPromises();

        expect(aiFoundationalChatAgentsQueryMock).toHaveBeenCalledWith({
          namespaceId: MOCK_NAMESPACE_ID,
          projectId: MOCK_PROJECT_ID,
        });
      });
    });

    describe('when project and namespace are not available', () => {
      it('does not pass project_id and namespace_id', async () => {
        createComponent({ propsData: {} });

        await waitForPromises();

        expect(aiFoundationalChatAgentsQueryMock).toHaveBeenCalledWith({
          namespaceId: null,
          projectId: null,
        });
      });
    });
  });

  describe('agent selection', () => {
    let agent;

    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      const agentResponse = MOCK_CONFIGURED_AGENTS_RESPONSE.data.aiCatalogConfiguredItems.nodes[0];
      agent = {
        ...agentResponse.item,
        pinnedItemVersionId: agentResponse.pinnedItemVersion.id,
        text: agentResponse.item.name,
      };
    });

    it('uses catalogAgentsFromResponse to transform the Apollo response', () => {
      expect(catalogAgentsFromResponse).toHaveBeenCalled();
    });

    it('uses the agentConfig from Apollo query when start workflow is called', async () => {
      await wrapper.vm.onNewChat(agent);
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(agentFlowConfigQueryMock).toHaveBeenCalledWith({
        agentVersionId: agent.pinnedItemVersionId,
      });

      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          agentConfig: MOCK_FLOW_AGENT_CONFIG,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );

      expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
    });

    it('uses workflow definition when foundational chat is selected', async () => {
      await wrapper.vm.onNewChat(MOCK_FETCHED_FOUNDATIONAL_AGENT);
      await waitForPromises();

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(agentFlowConfigQueryMock).not.toHaveBeenCalled();
      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          workflowDefinition: 'agent/v1',
          agentConfig: null,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );

      expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
    });

    describe('switching from a foundational agent to a catalog agent', () => {
      it('fetches agent flow config and sends agent version id', async () => {
        wrapper.vm.onNewChat(MOCK_FETCHED_FOUNDATIONAL_AGENT);
        await waitForPromises();

        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenLastCalledWith(
          expect.objectContaining({
            workflowDefinition: 'agent/v1',
            agentConfig: null,
            clientCapabilities: ['incremental_streaming', 'web_search'],
          }),
        );

        await wrapper.vm.onNewChat(agent);
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );

        await waitForPromises();

        expect(agentFlowConfigQueryMock).toHaveBeenCalledWith({
          agentVersionId: agent.pinnedItemVersionId,
        });

        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenLastCalledWith(
          expect.objectContaining({
            workflowDefinition: undefined,
            clientCapabilities: ['incremental_streaming', 'web_search'],
          }),
        );

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });
    });

    it('re-uses the selected flow config when /new is used to start a new thread', async () => {
      await wrapper.vm.onNewChat(agent);
      await waitForPromises();

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: '/new' }));
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
    });

    it('preserves agentConfig when selecting the same custom agent multiple times', async () => {
      // Select custom agent first time
      await wrapper.vm.onNewChat(agent);
      await waitForPromises();

      // Send first message to ensure agentConfig is populated
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'First message' }));
      await waitForPromises();

      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          agentConfig: MOCK_FLOW_AGENT_CONFIG,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );

      // Clear mocks to verify next call
      WorkflowSocketUtils.buildStartRequest.mockClear();

      // Select the SAME custom agent again (new chat with same agent)
      await wrapper.vm.onNewChat(agent);
      await waitForPromises();

      // Send another message
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Second message' }));
      await waitForPromises();

      // Verify agentConfig is still present (not null)
      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          agentConfig: MOCK_FLOW_AGENT_CONFIG,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );
    });

    it('resets agentConfig when default agent follows a custom agent chat', async () => {
      // Select custom agent first
      await wrapper.vm.onNewChat(agent);
      await waitForPromises();

      // Send message with custom agent
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: 'Custom agent message' }),
      );
      await waitForPromises();

      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          agentConfig: MOCK_FLOW_AGENT_CONFIG,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );

      // Clear mocks to verify next call
      WorkflowSocketUtils.buildStartRequest.mockClear();

      // Switch to foundational agent
      await wrapper.vm.onNewChat(MOCK_FETCHED_FOUNDATIONAL_AGENT);
      await waitForPromises();

      // Send message with foundational agent
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: 'Foundational agent message' }),
      );
      await waitForPromises();

      // Verify agentConfig is null and workflowDefinition is used instead
      expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          workflowDefinition: MOCK_FETCHED_FOUNDATIONAL_AGENT.referenceWithVersion,
          agentConfig: null,
          clientCapabilities: ['incremental_streaming', 'web_search'],
        }),
      );
    });

    it('sends no config when the default agent is selected (no id on selection)', async () => {
      await wrapper.vm.onNewChat({ name: 'default duo' });

      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
      );
      await waitForPromises();

      expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
    });

    describe('when chat is triggered via duoChatGlobalState.commands with an agent', () => {
      it('sets the selected agent from the command by id and displays it', async () => {
        duoChatGlobalState.commands = [
          ...duoChatGlobalState.commands,
          {
            question: 'Analyze this code for vulnerabilities',
            resourceId: MOCK_RESOURCE_ID,
            variables: {},
            agent: { id: DUO_FOUNDATIONAL_AGENT_MOCK.id },
          },
        ];
        await nextTick();

        expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
          expect.anything(),
          MOCK_FETCHED_FOUNDATIONAL_AGENT,
        );
        expect(findDuoChat().props('title')).toBe(DUO_FOUNDATIONAL_AGENT_MOCK.name);
      });

      it('sets the selected agent from the command by name and displays it', async () => {
        duoChatGlobalState.commands = [
          ...duoChatGlobalState.commands,
          {
            question: 'Analyze this code for vulnerabilities',
            resourceId: MOCK_RESOURCE_ID,
            variables: {},
            agent: { name: DUO_FOUNDATIONAL_AGENT_MOCK.name },
          },
        ];
        await nextTick();

        expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
          expect.anything(),
          MOCK_FETCHED_FOUNDATIONAL_AGENT,
        );
        expect(findDuoChat().props('title')).toBe(DUO_FOUNDATIONAL_AGENT_MOCK.name);
      });
    });
  });

  describe('Agent deletion handling', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('disables chat when agent is deleted', async () => {
      // Mock thread with deleted agent
      workflowEventsQueryMock.mockResolvedValue({
        data: {
          ...MOCK_WORKFLOW_EVENTS_RESPONSE,
          duoWorkflowWorkflows: {
            nodes: [
              {
                id: 'workflow-1',
                status: 'completed',
                aiCatalogItemVersionId: 'AgentVersion 999',
                workflowDefinition: null,
                archived: false,
                stalled: false,
                webSearchEnabled: false,
                latestCheckpoint: null,
              },
            ],
          },
        },
      });

      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      expect(findDuoChat().props('isChatAvailable')).toBe(false);
      expect(findDuoChat().props('error')).toBe(
        'The agent associated with this conversation is no longer available. You can view the conversation history but cannot send new messages.',
      );
    });

    it('re-enables chat when starting new chat after viewing deleted agent thread', async () => {
      // Mock thread with deleted agent
      workflowEventsQueryMock.mockResolvedValue({
        data: {
          ...MOCK_WORKFLOW_EVENTS_RESPONSE,
          duoWorkflowWorkflows: {
            nodes: [
              {
                id: 'workflow-1',
                status: 'completed',
                aiCatalogItemVersionId: 'AgentVersion 999',
                workflowDefinition: null,
                archived: false,
                stalled: false,
                webSearchEnabled: false,
                latestCheckpoint: null,
              },
            ],
          },
        },
      });

      // Create component with workflowId to trigger hydration on mount
      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      // Verify chat is disabled
      expect(findDuoChat().props('isChatAvailable')).toBe(false);
      expect(findDuoChat().props('error')).toBe(
        'The agent associated with this conversation is no longer available. You can view the conversation history but cannot send new messages.',
      );

      // Start a new chat with default agent
      wrapper.vm.onNewChat({ name: 'GitLab Duo Agent' });
      await nextTick();

      // Verify chat is re-enabled and error is cleared
      expect(findDuoChat().props('isChatAvailable')).toBe(true);
      expect(findDuoChat().props('error')).toBe('');
    });
  });

  describe('showErrorBannerMessage computed property', () => {
    const PREFERENCES_PATH = '/-/profile/preferences';

    const createComponentWithNamespaceConfig = ({
      defaultNamespaceSelected,
      preferencesPath = PREFERENCES_PATH,
      routeName = AGENTIC_CHAT_SHOW_ROUTE,
      agentOrWorkflowDeletedError = '',
      namespaceSaveError = '',
    }) => {
      createComponent({
        routeName,
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected,
              preferencesPath,
            },
          },
        },
        data: { agentOrWorkflowDeletedError, namespaceSaveError },
      });
    };

    describe.each`
      defaultNamespaceSelected | routeName                  | agentOrWorkflowDeletedError | namespaceSaveError  | expectedError          | description
      ${false}                 | ${AGENTIC_CHAT_SHOW_ROUTE} | ${''}                       | ${''}               | ${''}                  | ${'returns empty string when namespace not selected (now handled by empty state)'}
      ${true}                  | ${AGENTIC_CHAT_SHOW_ROUTE} | ${''}                       | ${''}               | ${''}                  | ${'returns empty string when namespace is selected'}
      ${false}                 | ${AGENTIC_CHAT_SHOW_ROUTE} | ${'Agent was deleted'}      | ${''}               | ${'Agent was deleted'} | ${'shows agentOrWorkflowDeletedError'}
      ${true}                  | ${AGENTIC_CHAT_SHOW_ROUTE} | ${'Agent was deleted'}      | ${''}               | ${'Agent was deleted'} | ${'shows agentOrWorkflowDeletedError when namespace is selected'}
      ${false}                 | ${AGENTIC_CHAT_SHOW_ROUTE} | ${''}                       | ${'Unable to save'} | ${'Unable to save'}    | ${'shows namespaceSaveError'}
      ${false}                 | ${AGENTIC_CHAT_SHOW_ROUTE} | ${'Agent was deleted'}      | ${'Unable to save'} | ${'Unable to save'}    | ${'prioritizes namespaceSaveError over agentOrWorkflowDeletedError'}
    `(
      '$description',
      ({
        defaultNamespaceSelected,
        routeName,
        agentOrWorkflowDeletedError,
        namespaceSaveError,
        expectedError,
      }) => {
        it('returns correct error', () => {
          createComponentWithNamespaceConfig({
            defaultNamespaceSelected,
            routeName,
            agentOrWorkflowDeletedError,
            namespaceSaveError,
          });

          const errorProp = findDuoChat().props('error');
          expect(errorProp).toBe(expectedError);
        });
      },
    );
  });

  describe('showNoNamespaceEmptyState computed property', () => {
    const PREFERENCES_PATH = '/-/profile/preferences';

    const createComponentWithNamespaceConfig = ({
      defaultNamespaceSelected,
      preferencesPath = PREFERENCES_PATH,
      routeName = AGENTIC_CHAT_SHOW_ROUTE,
    }) => {
      createComponent({
        routeName,
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected,
              preferencesPath,
            },
          },
        },
      });
    };

    describe('when namespace is not selected', () => {
      it('renders no-namespace empty state in CHAT view', () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: false,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });

        const duoChat = findDuoChat();
        const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

        expect(customEmptyState).toBeDefined();
      });

      it('disables the chat input', async () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: false,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });

        await nextTick();

        const duoChat = findDuoChat();

        expect(duoChat.props('chatState')).toMatchObject({
          isEnabled: false,
        });
      });
    });

    describe('when namespace is selected', () => {
      it('does not render no-namespace empty state', () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: true,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });

        const duoChat = findDuoChat();
        const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state'];

        expect(customEmptyState).toBeUndefined();
      });
    });

    describe('when NoNamespaceEmptyState emits save-error', () => {
      it('shows the message in the error banner', async () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: false,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });
        await waitForPromises();

        wrapper
          .findComponent(NoNamespaceEmptyState)
          .vm.$emit('save-error', 'Unable to save your namespace selection. Try again.');
        await nextTick();

        expect(findDuoChat().props('error')).toBe(
          'Unable to save your namespace selection. Try again.',
        );
      });

      it('clears the error banner when starting a new chat', async () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: false,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });
        await waitForPromises();

        wrapper
          .findComponent(NoNamespaceEmptyState)
          .vm.$emit('save-error', 'Unable to save your namespace selection. Try again.');
        await nextTick();

        expect(findDuoChat().props('error')).toBe(
          'Unable to save your namespace selection. Try again.',
        );

        // Initialization is route-driven, not mode-prop-driven: mirror an
        // in-place switch to the new-chat route to trigger onNewChat's cleanup.
        mockRoute.name = AGENTIC_CHAT_NEW_ROUTE;
        await nextTick();

        expect(findDuoChat().props('error')).toBe('');
      });
    });

    describe('when NoNamespaceEmptyState emits namespace-selected', () => {
      it('refreshes the page', async () => {
        createComponentWithNamespaceConfig({
          defaultNamespaceSelected: false,
          routeName: AGENTIC_CHAT_SHOW_ROUTE,
        });
        await waitForPromises();

        expect(refreshCurrentPage).not.toHaveBeenCalled();

        wrapper.findComponent(NoNamespaceEmptyState).vm.$emit('namespace-selected');
        await nextTick();

        expect(refreshCurrentPage).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('empty state priority', () => {
    const PREFERENCES_PATH = '/-/profile/preferences';

    it('shows no-namespace empty state over no-credits when both conditions are true', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });

      createComponent({
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected: false,
              preferencesPath: PREFERENCES_PATH,
            },
          },
        },
      });
      await waitForPromises();

      const duoChat = findDuoChat();
      const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

      expect(customEmptyState).toBeDefined();
    });

    it('shows no-credits empty state when namespace is selected but credits exhausted', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });

      createComponent({
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected: true,
              preferencesPath: PREFERENCES_PATH,
            },
          },
        },
      });
      await waitForPromises();

      const duoChat = findDuoChat();
      const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

      expect(customEmptyState).toBeDefined();
    });

    it('shows no-namespace empty state over trial/subscription when both conditions are true', () => {
      createComponent({
        propsData: { trialActive: true },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected: false,
              preferencesPath: PREFERENCES_PATH,
            },
          },
        },
      });

      const duoChat = findDuoChat();
      const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

      expect(customEmptyState).toBeDefined();
    });

    it('shows no-credits empty state over trial/subscription when both conditions are true', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });

      createComponent({
        propsData: { trialActive: true },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected: true,
              preferencesPath: PREFERENCES_PATH,
            },
          },
        },
      });
      await waitForPromises();

      const duoChat = findDuoChat();
      const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

      expect(customEmptyState).toBeDefined();
    });

    describe('thread load retry and error states', () => {
      const errorText = 'Network timeout occurred';
      const RETRY_DELAY_MS = 10000;

      it('shows the loading state over no-namespace empty state while a retry is in progress', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent({
          provide: {
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              defaultProps: {
                defaultNamespaceSelected: false,
                preferencesPath: PREFERENCES_PATH,
              },
            },
          },
        });
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(NoNamespaceEmptyState).exists()).toBe(false);
      });

      it('shows the error state over no-namespace empty state once retries are exhausted', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent({
          provide: {
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              defaultProps: {
                defaultNamespaceSelected: false,
                preferencesPath: PREFERENCES_PATH,
              },
            },
          },
        });
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(NoNamespaceEmptyState).exists()).toBe(false);
      });

      it('shows the loading state over no-credits empty state while a retry is in progress', async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent();
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(NoCreditsEmptyState).exists()).toBe(false);
      });

      it('shows the error state over no-credits empty state once retries are exhausted', async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue(new Error(errorText));

        createComponent();
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();
        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(NoCreditsEmptyState).exists()).toBe(false);
      });

      it('shows the error state immediately, without retrying, on a permission error', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValue({
          graphQLErrors: [{ message: 'Forbidden', extensions: { code: NO_RESOURCE_PERMISSIONS } }],
        });

        createComponent();
        await waitForPromises();

        expect(workflowEventsQueryMock).toHaveBeenCalledTimes(1);
        expect(wrapper.findComponent(ThreadLoadErrorEmptyState).exists()).toBe(true);
        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(false);
      });

      it('resets the loading state when a retry attempt resolves via a non-permission handler', async () => {
        getSessionStorageValue.mockReturnValueOnce({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });
        workflowEventsQueryMock.mockRejectedValueOnce(new Error(errorText)).mockRejectedValueOnce({
          graphQLErrors: [
            { message: 'No default namespace', extensions: { code: 'NO_DEFAULT_NAMESPACE' } },
          ],
        });

        createComponent();
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(true);

        jest.advanceTimersByTime(RETRY_DELAY_MS);
        await waitForPromises();

        expect(wrapper.findComponent(ThreadLoadingEmptyState).exists()).toBe(false);
        expect(wrapper.findComponent(NoNamespaceEmptyState).exists()).toBe(true);
      });
    });

    // Messages are set via direct store mutation because clearActiveWorkflow()
    // wipes messages set via initialState during mount (no stream is connected
    // in tests). Mutating after mount ensures messages survive the wipe.
    describe('credits exhausted banner', () => {
      it('shows the credits exhausted alert when out of credits and messages exist', async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });
        createComponent();
        await waitForPromises();
        store.state.messages = [{ role: 'user', content: 'Hello' }];
        await nextTick();

        expect(findCreditsExhaustedAlert().exists()).toBe(true);
      });

      it('does not show the credits exhausted alert when out of credits but no messages exist', () => {
        createComponent({ data: { hasCredits: false } });

        expect(findCreditsExhaustedAlert().exists()).toBe(false);
      });

      it('does not show the credits exhausted alert when credits are available', async () => {
        createComponent();
        store.state.messages = [{ role: 'user', content: 'Hello' }];
        await nextTick();

        expect(findCreditsExhaustedAlert().exists()).toBe(false);
      });

      it('passes props to the alert', async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });
        createComponent({
          propsData: {
            isTrial: true,
            isFreeAddonCreditsUser: true,
            purchaseCreditsPath: '/buy',
            canBuyAddon: true,
          },
        });
        await waitForPromises();
        store.state.messages = [{ role: 'user', content: 'Hello' }];
        await nextTick();

        const alert = findCreditsExhaustedAlert();
        expect(alert.props('isTrial')).toBe(true);
        expect(alert.props('isFreeAddonCreditsUser')).toBe(true);
        expect(alert.props('hasAgenticToggle')).toBe(false);
        expect(alert.props('purchaseCreditsPath')).toBe('/buy');
        expect(alert.props('canBuyAddon')).toBe(true);
      });
    });

    it('shows trial/subscription empty state when namespace selected and credits available', () => {
      createComponent({
        propsData: { trialActive: true },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              defaultNamespaceSelected: true,
              preferencesPath: PREFERENCES_PATH,
            },
          },
        },
      });

      const duoChat = findDuoChat();
      const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

      expect(customEmptyState).toBeDefined();
    });
  });

  describe('dynamicTitle', () => {
    it('passes the base title when no custom agent is selected', async () => {
      createComponent();
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('GitLab Duo');
    });

    it('passes the agent name as title when a custom agent is selected', async () => {
      const mockCatalogAgent = {
        id: 'Agent 5',
        name: 'My Custom Agent',
        description: 'This is my custom agent',
        pinnedItemVersionId: 'AgentVersion 5',
      };

      createComponent({
        propsData: {
          mode: 'default',
        },
        data: {
          aiCatalogItemVersionId: 'AgentVersion 5',
          catalogAgents: [mockCatalogAgent],
        },
        initialState: {
          currentAgent: mockCatalogAgent,
        },
      });
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('My Custom Agent');
    });

    it('passes the agent name as title when a foundational agent is selected', async () => {
      createComponent({
        initialState: {
          currentAgent: MOCK_FETCHED_FOUNDATIONAL_AGENT,
        },
      });

      await wrapper.vm.onNewChat(MOCK_FETCHED_FOUNDATIONAL_AGENT);
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe(MOCK_FETCHED_FOUNDATIONAL_AGENT.name);
    });

    it('uses currentAgent from Vuex store for title when available', async () => {
      const mockAgent = {
        id: 'Agent 123',
        name: 'Store Agent Name',
      };

      createComponent({
        initialState: {
          currentAgent: mockAgent,
        },
      });
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('Store Agent Name');
    });

    it('falls back to duoChatTitle when currentAgent is null in store', async () => {
      createComponent({
        initialState: {
          currentAgent: null,
        },
      });
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('GitLab Duo');
    });
  });

  describe('agent switching via Vuex integration', () => {
    it('updates title when currentAgent changes in store', async () => {
      createComponent({
        initialState: {
          currentAgent: null,
        },
      });
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('GitLab Duo');

      await wrapper.vm.$store.dispatch('setCurrentAgent', {
        id: 'agent-1',
        name: 'New Agent',
      });
      await nextTick();

      expect(findDuoChat().props('title')).toBe('New Agent');
    });

    it('reverts to default title when currentAgent is set to null', async () => {
      createComponent({
        initialState: {
          currentAgent: { id: 'agent-1', name: 'Some Agent' },
        },
      });
      await waitForPromises();

      expect(findDuoChat().props('title')).toBe('Some Agent');

      await wrapper.vm.$store.dispatch('setCurrentAgent', null);
      await nextTick();

      expect(findDuoChat().props('title')).toBe('GitLab Duo');
    });
  });

  describe('flowConfig Apollo query integration', () => {
    beforeEach(() => {
      createWorkflowMutationMock.mockResolvedValue({
        data: { aiDuoWorkflowCreate: { workflow: { id: '456' }, errors: [] } },
      });
    });

    it('queries agentConfig when aiCatalogItemVersionId is set', async () => {
      agentFlowConfigQueryMock.mockClear();

      createComponent({
        data: {
          aiCatalogItemVersionId: 'gid://gitlab/Ai::Catalog::ItemVersion/1',
        },
      });

      await waitForPromises();

      expect(agentFlowConfigQueryMock).toHaveBeenCalledWith({
        agentVersionId: 'gid://gitlab/Ai::Catalog::ItemVersion/1',
      });
    });

    it('fetches fresh agent config when switching agents', async () => {
      const agent2 = {
        id: 'Agent 2',
        name: 'Test Agent',
        pinnedItemVersionId: 'version-2',
      };

      agentFlowConfigQueryMock.mockClear();

      createComponent({
        data: {
          aiCatalogItemVersionId: 'version-1',
        },
      });
      await waitForPromises();

      // Switch to agent2
      await wrapper.vm.onNewChat(agent2);
      await waitForPromises();

      // Verify query was called with the new agent version id
      expect(agentFlowConfigQueryMock).toHaveBeenCalledWith({
        agentVersionId: 'version-2',
      });
    });

    describe('when switching from custom agent to default agent', () => {
      beforeEach(async () => {
        createComponent({
          data: {
            aiCatalogItemVersionId: 'version-1',
          },
        });
        await waitForPromises();
      });

      it('stops querying agent config', async () => {
        // Verify config query was called for the custom agent
        expect(agentFlowConfigQueryMock).toHaveBeenCalledWith({
          agentVersionId: 'version-1',
        });

        agentFlowConfigQueryMock.mockClear();

        // Switch to default agent (no agent.id)
        wrapper.vm.onNewChat({ name: 'default duo' });
        await waitForPromises();

        // Verify no config is sent when starting workflow with default agent
        findDuoChat().vm.$emit(
          'send-chat-prompt',
          createUserPrompt({ text: MOCK_USER_MESSAGE.content }),
        );
        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
        expect(agentFlowConfigQueryMock).not.toHaveBeenCalled();
      });
    });
  });

  describe('initialization and layout', () => {
    beforeEach(() => {
      createComponent({
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            isClassicAvailable: true,
            defaultProps: {},
          },
          activeTabData: {
            props: {
              isClassicAvailable: true,
            },
          },
        },
      });
    });

    it('shows header', () => {
      expect(findDuoChat().props('showHeader')).toBe(true);
    });

    it('does not set up window resize listeners on mount', () => {
      const addEventListenerSpy = jest.spyOn(window, 'addEventListener');
      createComponent({
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            isClassicAvailable: true,
            defaultProps: {},
          },
          activeTabData: {
            props: {
              isClassicAvailable: true,
            },
          },
        },
      });

      const resizeCalls = addEventListenerSpy.mock.calls.filter(([event]) => event === 'resize');
      expect(resizeCalls).toHaveLength(0);
      addEventListenerSpy.mockRestore();
    });

    it('does not try to clean up resize listeners on destroy', () => {
      const removeEventListenerSpy = jest.spyOn(window, 'removeEventListener');
      wrapper.destroy();

      const resizeCalls = removeEventListenerSpy.mock.calls.filter(([event]) => event === 'resize');
      expect(resizeCalls).toHaveLength(0);
      removeEventListenerSpy.mockRestore();
    });

    it('calls setAgenticMode when toggling classic mode', async () => {
      getCookie.mockReturnValue('false');

      // Recreate component to show Classic toggle
      createComponent({
        propsData: { forceAgenticModeForCoreDuoUsers: false },
        provide: {
          chatConfiguration: {
            title: 'GitLab Duo Agentic Chat',
            defaultProps: {
              isClassicAvailable: true,
            },
          },
          activeTabData: {
            props: {
              isClassicAvailable: true,
            },
          },
        },
      });

      const findAgenticModeToggle = () => wrapper.findComponent(AgenticModeToggle);

      // Toggle directly controls agentic mode - false means agentic mode is disabled
      findAgenticModeToggle().vm.$emit('change', false);
      await nextTick();

      expect(setAgenticMode).toHaveBeenCalledWith({
        agenticMode: false,
        saveCookie: true,
      });
    });

    describe('Apollo queries', () => {
      beforeEach(async () => {
        createComponent({
          propsData: {
            userModelSelectionEnabled: true,
            rootNamespaceId: MOCK_NAMESPACE_ID,
          },
          provide: {
            chatConfiguration: {
              title: 'GitLab Duo Agentic Chat',
              isClassicAvailable: true,
              defaultProps: {},
            },
            activeTabData: {
              props: {
                isClassicAvailable: true,
              },
            },
          },
        });
        await waitForPromises();
      });

      it('runs contextPresets GraphQL query on mount', () => {
        expect(contextPresetsQueryHandlerMock).toHaveBeenCalled();
      });

      it('runs availableModels GraphQL query on mount', () => {
        expect(availableModelsQueryHandlerMock).toHaveBeenCalled();
      });

      it('runs catalogAgents GraphQL query on mount', () => {
        expect(configuredAgentsQueryMock).toHaveBeenCalled();
      });
    });
  });

  describe('Chat snapshot caching', () => {
    beforeEach(() => {
      MOCK_UTILS_SETUP();
      jest.clearAllMocks();
    });

    describe('hydrateActiveWorkflow', () => {
      describe('when cached messages exist', () => {
        beforeEach(() => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });
          createComponent();
        });

        it('loads cached messages once the workflow status is confirmed active', async () => {
          await waitForPromises();
          expect(loadThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
          expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), snapshotMessages);
        });

        it('updates with fresh messages from API after cache is loaded', async () => {
          await waitForPromises();

          // First call: cached messages
          expect(actionSpies.setMessages).toHaveBeenNthCalledWith(
            1,
            expect.anything(),
            snapshotMessages,
          );

          // Second call: fresh messages from API
          expect(actionSpies.setMessages).toHaveBeenNthCalledWith(
            2,
            expect.anything(),
            MOCK_TRANSFORMED_MESSAGES,
          );
        });
      });

      // The cached messages are painted before the checkpoint query says whether the
      // thread is still active, and the credits query resolves inside that window and
      // would otherwise re-enable the input on an archived thread.
      describe('while a cached snapshot is painted and the workflow is unconfirmed', () => {
        let resolveCheckpoint;

        beforeEach(async () => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          workflowEventsQueryMock.mockReturnValue(
            new Promise((resolve) => {
              resolveCheckpoint = resolve;
            }),
          );

          createComponent();
          await waitForPromises();
        });

        // Settles the hydration the examples deliberately leave in flight, so a
        // component stuck mid-hydration does not resume during a later example.
        afterEach(async () => {
          resolveCheckpoint({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
          await waitForPromises();
        });

        it('paints the cached messages', () => {
          expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), snapshotMessages);
        });

        it('locks the prompt', () => {
          expect(findDuoChat().props('isChatAvailable')).toBe(false);
        });

        it('does not explain the lock, which is transient', () => {
          expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: true });
          expect(findDuoChat().props('error')).toBe('');
        });

        it('unlocks the prompt once the workflow comes back active', async () => {
          resolveCheckpoint({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
          await waitForPromises();

          expect(findDuoChat().props('isChatAvailable')).toBe(true);
        });

        it('leaves the prompt locked when the workflow comes back archived', async () => {
          resolveCheckpoint({ data: MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE });
          await waitForPromises();

          expect(findDuoChat().props('chatState')).toMatchObject({
            isEnabled: false,
            reason: expect.stringContaining('archived'),
          });
        });
      });

      describe('when no cached messages exist', () => {
        beforeEach(() => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          createComponent();
        });

        it('does not set messages from cache', async () => {
          await waitForPromises();

          expect(loadThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
          // Only called once with API data, not with cache
          expect(actionSpies.setMessages).toHaveBeenCalledTimes(1);
          expect(actionSpies.setMessages).toHaveBeenCalledWith(
            expect.anything(),
            MOCK_TRANSFORMED_MESSAGES,
          );
        });

        it('still fetches messages from API', async () => {
          await waitForPromises();
          expect(workflowEventsQueryMock).toHaveBeenCalled();
        });
      });

      describe('when the snapshot continues past the reloaded checkpoint', () => {
        const checkpointMessages = [
          { role: 'user', content: 'Question', message_id: 'm1', requestId: 'r1' },
          { role: 'assistant', content: 'Persisted answer', message_id: 'm2', requestId: 'r2' },
        ];
        const streamedTailMessage = {
          role: 'assistant',
          content: 'Streamed answer the checkpoint has not persisted yet',
          message_id: 'm3',
          requestId: 'r3',
        };

        beforeEach(() => {
          loadThreadSnapshot.mockReturnValue({
            v: 1,
            convoId: '456',
            messages: [...checkpointMessages, streamedTailMessage],
          });
          WorkflowUtils.transformChatMessages.mockReturnValue(checkpointMessages);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });
          createComponent();
        });

        it('keeps the streamed tail instead of dropping it for the checkpoint', async () => {
          await waitForPromises();

          expect(findDuoChat().props('messages')).toEqual([
            ...checkpointMessages,
            streamedTailMessage,
          ]);
        });
      });

      describe('when the reloaded workflow has failed', () => {
        beforeEach(() => {
          WorkflowUtils.parseWorkflowData.mockReturnValue({
            workflowGoal: '',
            workflowStatus: 'FAILED',
            errors: null,
            duoMessages: [],
          });

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });
          createComponent();
        });

        it('shows the incomplete-response error banner', async () => {
          await waitForPromises();

          expect(findDuoChat().props('error')).toBe(
            "GitLab Duo couldn't complete this response. Recent messages might be missing or incomplete. Try sending your message again.",
          );
        });
      });

      describe('when active workflow thread is archived', () => {
        beforeEach(async () => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          workflowEventsQueryMock.mockResolvedValue({
            data: MOCK_WORKFLOW_EVENTS_ARCHIVED_RESPONSE,
          });

          createComponent();
          await waitForPromises();
        });

        it('shows archived empty state instead of loading thread', () => {
          const duoChat = findDuoChat();
          const customEmptyState = getInstanceSlots(duoChat.vm)['custom-empty-state']({});

          expect(customEmptyState).toBeDefined();
        });

        it('disables chat input', () => {
          expect(findDuoChat().props('chatState')).toMatchObject({
            isEnabled: false,
            reason: expect.stringContaining('archived'),
          });
        });

        it('does not display the thread messages', () => {
          expect(findDuoChat().props('messages')).toEqual([]);
        });

        it('clears the stored snapshot so a stale cache is not painted later', () => {
          expect(clearThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
        });
      });

      describe('when the persisted workflow no longer exists', () => {
        beforeEach(async () => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          workflowEventsQueryMock.mockResolvedValue({
            data: MOCK_WORKFLOW_EVENTS_EMPTY_RESPONSE,
          });

          createComponent();
          await waitForPromises();
        });

        it('clears the stored snapshot', () => {
          expect(clearThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
        });

        it('surfaces the deleted-chat error', () => {
          expect(wrapper.vm.showErrorBannerMessage).toBe('This chat was deleted.');
        });
      });

      describe('when server reports credits exhausted', () => {
        beforeEach(async () => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);

          creditsAvailableQueryMock.mockResolvedValue({
            data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
          });

          WorkflowUtils.transformChatMessages.mockReturnValue([]);
          WorkflowUtils.parseWorkflowData.mockReturnValue({
            checkpoint: { channel_values: { ui_chat_log: [] } },
          });

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          createComponent();

          await waitForPromises();
        });

        it('disables chat due to credit exhaustion', () => {
          expect(findDuoChat().props('chatState')).toMatchObject({
            isEnabled: false,
            reason: '',
          });
        });

        it('resets loading, waiting, and processing state', async () => {
          wrapper.vm.isLoading = true;
          wrapper.vm.isWaitingOnPrompt = true;
          wrapper.vm.isProcessingMessage = true;

          wrapper.vm.setOutOfCredits();
          await nextTick();

          expect(wrapper.vm.isLoading).toBe(false);
          expect(wrapper.vm.isWaitingOnPrompt).toBe(false);
          expect(wrapper.vm.isProcessingMessage).toBe(false);
        });
      });

      describe('when server reports billing forbidden', () => {
        beforeEach(async () => {
          loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);

          creditsAvailableQueryMock.mockResolvedValue({
            data: {
              gitlabCreditsAvailable: false,
              gitlabCreditsUnavailableReason: 'USAGE_BILLING_FORBIDDEN',
            },
          });

          WorkflowUtils.transformChatMessages.mockReturnValue([]);
          WorkflowUtils.parseWorkflowData.mockReturnValue({
            checkpoint: { channel_values: { ui_chat_log: [] } },
          });

          getSessionStorageValue.mockReturnValue({
            exists: true,
            value: { workflowId: MOCK_WORKFLOW_ID },
          });

          duoChatGlobalState.isAgenticChatShown = true;

          createComponent();

          await waitForPromises();
        });

        it('disables chat with billing forbidden message', () => {
          expect(findDuoChat().props('chatState')).toMatchObject({
            isEnabled: false,
            reason: expect.stringContaining('contact your administrator'),
          });
        });
      });
    });

    describe('when workflow definition is agentic_chat/v1 and agenticChatFlowRegistryMigration is disabled', () => {
      let onNewChatSpy;

      beforeEach(async () => {
        onNewChatSpy = jest.spyOn(DuoAgenticChatStateManager.methods, 'onNewChat');

        workflowEventsQueryMock.mockResolvedValue({
          data: {
            duoWorkflowWorkflows: {
              nodes: [
                {
                  id: 'workflow-1',
                  status: 'completed',
                  aiCatalogItemVersionId: null,
                  workflowDefinition: DUO_WORKFLOW_NEW_CHAT_DEFINITION,
                  archived: false,
                  stalled: false,
                  webSearchEnabled: false,
                  latestCheckpoint: {
                    workflowGoal: '',
                    workflowStatus: 'completed',
                    errors: null,
                    duoMessages: [],
                  },
                },
              ],
            },
          },
        });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          provide: { glFeatures: { agenticChatFlowRegistryMigration: false } },
        });
        await waitForPromises();
      });

      it('calls onNewChat instead of loading the thread', () => {
        expect(onNewChatSpy).toHaveBeenCalled();
      });
    });

    describe('setCurrentAgent action', () => {
      beforeEach(() => {
        actionSpies.setCurrentAgent.mockClear();
      });

      it('calls setCurrentAgent with catalog agent after loading thread', async () => {
        const mockCatalogAgent = {
          id: 'Agent 5',
          name: 'My Custom Agent',
          description: 'This is my custom agent',
          itemType: 'AGENT',
          foundational: false,
          latestVersion: { id: 'AgentVersion 5', versionName: '1.0.0' },
          pinnedItemVersionId: 'AgentVersion 5',
          pinnedItemVersion: { id: 'AgentVersion 5', versionName: '1.0.0' },
        };

        workflowEventsQueryMock.mockResolvedValue({
          data: {
            duoWorkflowWorkflows: {
              nodes: [
                {
                  id: 'workflow-1',
                  status: 'completed',
                  aiCatalogItemVersionId: 'AgentVersion 5',
                  workflowDefinition: null,
                  archived: false,
                  stalled: false,
                  webSearchEnabled: false,
                  latestCheckpoint: null,
                },
              ],
            },
          },
        });

        WorkflowUtils.transformChatMessages.mockReturnValue([]);
        WorkflowUtils.parseWorkflowData.mockReturnValue({
          workflowGoal: '',
          workflowStatus: 'completed',
          errors: null,
          duoMessages: [],
        });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          data: {
            catalogAgents: [mockCatalogAgent],
          },
        });

        await waitForPromises();

        expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
          expect.anything(),
          mockCatalogAgent,
        );
      });

      it('calls setCurrentAgent with foundational agent after loading thread', async () => {
        workflowEventsQueryMock.mockResolvedValue({
          data: MOCK_WORKFLOW_EVENTS_RESPONSE_WITH_FOUNDATIONAL_AGENT,
        });

        WorkflowUtils.transformChatMessages.mockReturnValue([]);
        WorkflowUtils.parseWorkflowData.mockReturnValue({
          checkpoint: { channel_values: { ui_chat_log: [] } },
          workflowStatus: 'completed',
        });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent();

        await waitForPromises();

        expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({
            referenceWithVersion: MOCK_FETCHED_FOUNDATIONAL_AGENT.referenceWithVersion,
          }),
        );
      });

      it('calls setCurrentAgent(null) when no agent is associated with thread', async () => {
        workflowEventsQueryMock.mockResolvedValue({
          data: {
            duoWorkflowWorkflows: {
              nodes: [
                {
                  id: 'workflow-1',
                  status: 'completed',
                  aiCatalogItemVersionId: '',
                  workflowDefinition: null,
                  archived: false,
                  stalled: false,
                  webSearchEnabled: false,
                  latestCheckpoint: null,
                },
              ],
            },
          },
        });

        WorkflowUtils.transformChatMessages.mockReturnValue([]);
        WorkflowUtils.parseWorkflowData.mockReturnValue({
          workflowGoal: '',
          workflowStatus: 'completed',
          errors: null,
          duoMessages: [],
        });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent();

        await waitForPromises();

        expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(expect.anything(), null);
      });
    });

    describe('reconnection with custom agent', () => {
      const MOCK_CUSTOM_AGENT_VERSION_ID = 'AgentVersion 5';

      afterEach(() => {
        workflowStreamFactory
          .getWorkflowStream()
          .getStatus.mockReturnValue({ connected: false, bufferedCount: 0 });
      });

      beforeEach(() => {
        actionSpies.setCurrentAgent.mockClear();

        workflowEventsQueryMock.mockResolvedValue({
          data: {
            duoWorkflowWorkflows: {
              nodes: [
                {
                  id: 'workflow-1',
                  status: 'running',
                  aiCatalogItemVersionId: MOCK_CUSTOM_AGENT_VERSION_ID,
                  workflowDefinition: null,
                  archived: false,
                  stalled: false,
                  webSearchEnabled: false,
                  latestCheckpoint: {
                    workflowGoal: '',
                    workflowStatus: DUO_WORKFLOW_STATUS_RUNNING,
                    errors: null,
                    duoMessages: [],
                  },
                },
              ],
            },
          },
        });

        WorkflowUtils.transformChatMessages.mockReturnValue([]);
        WorkflowUtils.parseWorkflowData.mockReturnValue({
          workflowGoal: '',
          workflowStatus: DUO_WORKFLOW_STATUS_RUNNING,
          errors: null,
          duoMessages: [],
        });
      });

      it('reconnects to a running custom agent workflow', async () => {
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          data: {
            catalogAgents: [
              {
                id: 'Agent 5',
                name: 'My Custom Agent',
                pinnedItemVersionId: MOCK_CUSTOM_AGENT_VERSION_ID,
              },
            ],
          },
        });

        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).toHaveBeenCalled();
      });

      it('sets aiCatalogItemVersionId before calling startWorkflow on reconnect', async () => {
        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          data: {
            catalogAgents: [
              {
                id: 'Agent 5',
                name: 'My Custom Agent',
                pinnedItemVersionId: MOCK_CUSTOM_AGENT_VERSION_ID,
              },
            ],
          },
        });

        await waitForPromises();

        expect(wrapper.vm.aiCatalogItemVersionId).toBe(MOCK_CUSTOM_AGENT_VERSION_ID);
        expect(WorkflowSocketUtils.buildStartRequest).toHaveBeenCalled();
      });

      it('does not reconnect when workflow status is not RUNNING', async () => {
        WorkflowUtils.parseWorkflowData.mockReturnValue({
          checkpoint: { channel_values: { ui_chat_log: [] } },
          workflowStatus: 'completed',
        });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          data: {
            catalogAgents: [
              {
                id: 'Agent 5',
                name: 'My Custom Agent',
                pinnedItemVersionId: MOCK_CUSTOM_AGENT_VERSION_ID,
              },
            ],
          },
        });

        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });

      it('does not reconnect when stream is already connected', async () => {
        workflowStreamFactory
          .getWorkflowStream()
          .getStatus.mockReturnValue({ connected: true, bufferedCount: 0 });

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent({
          data: {
            catalogAgents: [
              {
                id: 'Agent 5',
                name: 'My Custom Agent',
                pinnedItemVersionId: MOCK_CUSTOM_AGENT_VERSION_ID,
              },
            ],
          },
        });

        await waitForPromises();

        expect(workflowStreamFactory.getWorkflowStream().connect).not.toHaveBeenCalled();
      });
    });

    describe('connectToStream (route-driven init, additive stream adoption)', () => {
      const getStream = () => workflowStreamFactory.getWorkflowStream();

      afterEach(() => {
        getStream().getStatus.mockReturnValue({ connected: false, bufferedCount: 0 });
        getStream().disconnect.mockReset();
      });

      describe('opening a thread while a reply is already streaming', () => {
        let hydrateActiveWorkflowSpy;

        beforeEach(async () => {
          getStream().getStatus.mockReturnValue({ connected: true, bufferedCount: 0 });
          hydrateActiveWorkflowSpy = jest
            .spyOn(DuoAgenticChatStateManager.methods, 'hydrateActiveWorkflow')
            .mockResolvedValue();

          createComponent({
            data: { workflowId: MOCK_WORKFLOW_ID },
            initialState: {
              messages: [{ message_id: 'm1' }, { message_id: 'm2' }],
            },
          });
          await waitForPromises();
        });

        it('still loads the thread, because init is unconditional', () => {
          expect(hydrateActiveWorkflowSpy).toHaveBeenCalled();
        });

        it('adopts the live reply on top by waiting on the prompt', () => {
          expect(wrapper.vm.isWaitingOnPrompt).toBe(true);
        });

        it('anchors the dedup marker to the last loaded message so chunks are not duplicated', () => {
          expect(wrapper.vm.lastProcessedMessageId).toBe('m2');
        });
      });

      describe('opening a thread with no reply streaming', () => {
        beforeEach(async () => {
          getStream().getStatus.mockReturnValue({ connected: false, bufferedCount: 0 });
          jest
            .spyOn(DuoAgenticChatStateManager.methods, 'hydrateActiveWorkflow')
            .mockResolvedValue();

          createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
          await waitForPromises();
        });

        it('does not show a phantom waiting state', () => {
          expect(wrapper.vm.isWaitingOnPrompt).toBe(false);
        });
      });

      describe('landing on the new-chat route while a previous reply is still streaming', () => {
        let onNewChatSpy;
        let hydrateActiveWorkflowSpy;

        beforeEach(async () => {
          // Stateful mock: onNewChat's cleanupSocket -> disconnect must actually
          // flip the flag, so adoptRunningStream sees no live stream afterwards.
          let connected = true;
          getStream().getStatus.mockImplementation(() => ({ connected, bufferedCount: 0 }));
          getStream().disconnect.mockImplementation(() => {
            connected = false;
          });

          onNewChatSpy = jest.spyOn(DuoAgenticChatStateManager.methods, 'onNewChat');
          hydrateActiveWorkflowSpy = jest.spyOn(
            DuoAgenticChatStateManager.methods,
            'hydrateActiveWorkflow',
          );

          createComponent({ routeName: AGENTIC_CHAT_NEW_ROUTE });
          await waitForPromises();
        });

        it('starts a blank chat and does not hydrate', () => {
          expect(onNewChatSpy).toHaveBeenCalled();
          expect(hydrateActiveWorkflowSpy).not.toHaveBeenCalled();
        });

        it('does not adopt the previous thread reply', () => {
          expect(wrapper.vm.isWaitingOnPrompt).toBe(false);
        });
      });
    });

    describe('messages watcher', () => {
      it('has debounced watcher for messages', () => {
        createComponent();

        // Verify the watcher exists by checking component options
        const watchers = wrapper.vm.$options.watch;
        expect(watchers.messages).toBeDefined();
        expect(watchers.messages.deep).toBe(true);
      });
    });

    describe('default agent avatar on initial load', () => {
      it('passes the default foundational agent id and avatar to the chat view when no agent is selected', async () => {
        createComponent();
        await waitForPromises();

        const { id, avatarUrl } =
          MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE.data.aiFoundationalChatAgents.nodes[0];

        expect(findDuoChat().props('agentId')).toBe(id);
        expect(findDuoChat().props('agentAvatarUrl')).toBe(avatarUrl);
      });
    });

    describe('transformedMessages', () => {
      it('passes the transformer pipeline output to duo-agentic-chat-view', async () => {
        const rawMessages = [{ content: 'hello', role: 'user', requestId: 'r1' }];
        const transformedOutput = [
          { content: 'hello (transformed)', role: 'user', requestId: 'r1' },
        ];
        runMessageTransformers.mockReturnValue(transformedOutput);

        createComponent();
        await store.dispatch('setMessages', rawMessages);
        await nextTick();

        expect(runMessageTransformers).toHaveBeenCalledWith(rawMessages, expect.any(Array));
        expect(findDuoChat().props('messages')).toEqual(transformedOutput);
      });
    });

    describe('integration scenarios', () => {
      it('loads cached messages on mount when available', async () => {
        loadThreadSnapshot.mockReturnValue(threadSnapshotWithMessages);

        getSessionStorageValue.mockReturnValue({
          exists: true,
          value: { workflowId: MOCK_WORKFLOW_ID },
        });

        createComponent();
        await waitForPromises();

        // Cache was loaded
        expect(loadThreadSnapshot).toHaveBeenCalledWith(MOCK_WORKFLOW_ID);
        // Messages were set from cache
        expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), snapshotMessages);
      });

      it('does not clear cache when starting new conversation', () => {
        createComponent();
        wrapper.vm.workflowId = MOCK_WORKFLOW_ID;

        wrapper.vm.onNewChat();

        // Cache was cleared for the workflow
        expect(clearThreadSnapshot).not.toHaveBeenCalled();
        // Messages were reset
        expect(actionSpies.setMessages).toHaveBeenCalledWith(expect.anything(), []);
      });
    });
  });

  describe('Duo UI Next', () => {
    describe('when the feature flag is disabled', () => {
      it('does not render the DuoNext component by default', () => {
        createComponent();
        expect(findDuoNext().exists()).toBe(false);
      });
    });

    describe('when the feature flag is enabled', () => {
      beforeEach(() => {
        createComponent({
          provide: {
            glFeatures: {
              duoUiNext: true,
            },
          },
        });
      });

      it('renders the DuoNext component if the flag is enabled', () => {
        expect(findDuoNext().exists()).toBe(true);
        expect(findDuoChat().exists()).toBe(false);
      });
    });
  });

  describe('Credit limitation', () => {
    describe('when credits are unavailable on load', () => {
      beforeEach(async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });

        createComponent();
        await waitForPromises();
      });

      it('disables chat when credits are exhausted', () => {
        const duoChat = findDuoChat();

        expect(duoChat.props('chatState')).toMatchObject({
          isEnabled: false,
          reason: '',
        });
      });

      it('hides model selector when userModelSelectionEnabled is true', async () => {
        creditsAvailableQueryMock.mockResolvedValue({
          data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
        });

        createComponent({
          propsData: {
            userModelSelectionEnabled: true,
          },
        });
        await waitForPromises();

        const modelSelector = wrapper.findComponent(ModelSelectDropdown);
        expect(modelSelector.exists()).toBe(false);
      });

      it('renders custom empty state in duo chat', () => {
        const duoChat = findDuoChat();
        const customEmptyStateSlot = getInstanceSlots(duoChat.vm)['custom-empty-state'];

        expect(customEmptyStateSlot).toBeDefined();
        expect(typeof customEmptyStateSlot).toBe('function');

        const customEmptyState = customEmptyStateSlot({});
        expect(customEmptyState).toBeDefined();
      });
    });

    describe('when credits are available on load', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('passes enabled chatState to duo chat component', () => {
        const duoChat = findDuoChat();

        expect(duoChat.props('chatState')).toMatchObject({
          isEnabled: true,
        });
      });

      it('shows model selector when userModelSelectionEnabled is true', async () => {
        createComponent({
          propsData: {
            userModelSelectionEnabled: true,
          },
        });
        await waitForPromises();

        const modelSelector = wrapper.findComponent(ModelSelectDropdown);
        expect(modelSelector.exists()).toBe(true);
      });
    });

    describe('runtime credit exhaustion', () => {
      describe('and the code is 1008 (insufficient credits)', () => {
        beforeEach(async () => {
          createComponent({
            propsData: {
              userModelSelectionEnabled: true,
            },
          });
          findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'test message' }));
          await waitForPromises();

          triggerStreamEvent('close', {
            type: 'close',
            code: 1008,
            reason: 'Insufficient credits: quota exceeded',
          });
          await waitForPromises();
          await nextTick();
        });

        it('disables chat when credits are exhausted', () => {
          const duoChat = findDuoChat();

          expect(duoChat.props('chatState')).toMatchObject({
            isEnabled: false,
            reason: '',
          });
        });

        it('hides model selector', () => {
          const modelSelector = wrapper.findComponent(ModelSelectDropdown);
          expect(modelSelector.exists()).toBe(false);
        });
      });

      describe('and the code is 1008 with USAGE_BILLING_FORBIDDEN reason', () => {
        beforeEach(async () => {
          createComponent({
            propsData: {
              userModelSelectionEnabled: true,
            },
          });
          findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'test message' }));
          await waitForPromises();

          triggerStreamEvent('close', {
            type: 'close',
            code: 1008,
            reason: 'USAGE_BILLING_FORBIDDEN: Usage billing not available',
          });
          await waitForPromises();
          await nextTick();
        });

        it('disables chat with billing forbidden message', () => {
          expect(findDuoChat().props('chatState')).toMatchObject({
            isEnabled: false,
            reason: expect.stringContaining('contact your administrator'),
          });
        });
      });
    });
  });

  describe('trackBinaryFeedbackEvent', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('calls trackEvent with correct parameters when track-feedback is emitted', async () => {
      getSessionStorageValue.mockReturnValueOnce({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });
      createComponent();
      await waitForPromises();

      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      const feedbackEvent = { feedbackType: 'thumbs_up', feedbackReason: 'accurate' };
      findDuoChat().vm.$emit('track-feedback', feedbackEvent);

      expect(trackEventSpy).toHaveBeenCalledWith(
        FEEDBACK_TRACKING_EVENT,
        expect.objectContaining({
          label: 'thumbs_up',
          value: 456,
          property: 'accurate',
        }),
        undefined,
      );
    });
  });

  describe('computedTrustedUrls', () => {
    beforeEach(() => {
      window.gon = {};
    });

    afterEach(() => {
      delete window.gon;
    });

    it('includes default trusted URLs (gitlab.com and docs URL)', () => {
      createComponent();
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).toContain('gitlab.com');
      expect(trustedUrls).toContain(docsUrlHost);
    });

    it('includes instance hostname from gon.gitlab_url when available', () => {
      window.gon.gitlab_url = 'https://gitlab.example.com';
      createComponent();
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).toContain('gitlab.example.com');
    });

    it('does not include instance hostname when gon.gitlab_url is not set', () => {
      createComponent();
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).not.toContain('my-gitlab.example.com');
    });

    it('includes additional URLs passed as props', () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          trustedUrls: ['custom1.example.com', 'custom2.example.com'],
        },
      });
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).toContain('custom1.example.com');
      expect(trustedUrls).toContain('custom2.example.com');
    });

    it('removes duplicate URLs', () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          trustedUrls: ['gitlab.com', `https://${docsUrlHost}`],
        },
      });
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      const gitlabComCount = trustedUrls.filter((url) => url === 'gitlab.com').length;
      const docsUrlCount = trustedUrls.filter((url) => url === docsUrlHost).length;

      expect(gitlabComCount).toBe(1);
      expect(docsUrlCount).toBe(1);
    });

    it('returns an array of unique hostnames', () => {
      window.gon.gitlab_url = 'https://my-gitlab.example.com';
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          trustedUrls: ['https://custom.example.com'],
        },
      });
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(Array.isArray(trustedUrls)).toBe(true);
      expect(new Set(trustedUrls).size).toBe(trustedUrls.length);
    });

    it('handles empty trustedUrls prop gracefully', () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          trustedUrls: [],
        },
      });
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).toContain('gitlab.com');
      expect(trustedUrls).toContain(docsUrlHost);
    });

    it('handles null trustedUrls prop gracefully', () => {
      createComponent({
        propsData: {
          projectId: MOCK_PROJECT_ID,
          resourceId: MOCK_RESOURCE_ID,
          trustedUrls: null,
        },
      });
      const trustedUrls = wrapper.vm.computedTrustedUrls;

      expect(trustedUrls).toContain('gitlab.com');
      expect(trustedUrls).toContain(docsUrlHost);
    });
  });

  describe('deferred agent selection', () => {
    let resolveFoundationalAgents;
    let resolveCatalogAgents;

    const pendingFoundationalAgentsMocks = () => {
      aiFoundationalChatAgentsQueryMock.mockReturnValueOnce(
        new Promise((resolve) => {
          resolveFoundationalAgents = resolve;
        }),
      );
      configuredAgentsQueryMock.mockResolvedValueOnce({
        data: {
          aiCatalogConfiguredItems: {
            nodes: [],
            pageInfo: { hasNextPage: false, endCursor: null },
            __typename: 'AiCatalogItemConsumerConnection',
          },
        },
      });
    };

    const pendingCatalogAgentsMocks = () => {
      aiFoundationalChatAgentsQueryMock.mockResolvedValueOnce(
        MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE,
      );
      configuredAgentsQueryMock.mockReturnValueOnce(
        new Promise((resolve) => {
          resolveCatalogAgents = resolve;
        }),
      );
    };

    const pushAgentCommand = async (agentName) => {
      duoChatGlobalState.commands = [{ agent: { name: agentName }, autoSend: false }];
      await nextTick();
    };

    const resolveFoundational = async (response = MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE) => {
      resolveFoundationalAgents(response);
      await waitForPromises();
    };

    const resolveCatalog = async () => {
      resolveCatalogAgents({
        data: {
          aiCatalogConfiguredItems: {
            nodes: [],
            pageInfo: { hasNextPage: false, endCursor: null },
            __typename: 'AiCatalogItemConsumerConnection',
          },
        },
      });
      await waitForPromises();
    };

    it('does not process agent command while foundationalAgents are loading', async () => {
      pendingFoundationalAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand(DUO_FOUNDATIONAL_AGENT_MOCK.name);

      expect(actionSpies.setCurrentAgent).not.toHaveBeenCalled();
      // Command should still be in the queue (not consumed)
      expect(duoChatGlobalState.commands).toHaveLength(1);
    });

    it('does not process agent command while catalogAgents are loading', async () => {
      pendingCatalogAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand(DUO_FOUNDATIONAL_AGENT_MOCK.name);

      expect(actionSpies.setCurrentAgent).not.toHaveBeenCalled();
      expect(duoChatGlobalState.commands).toHaveLength(1);
    });

    it('selects the agent when agents finish loading', async () => {
      pendingFoundationalAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand(DUO_FOUNDATIONAL_AGENT_MOCK.name);
      await resolveFoundational();

      expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ name: DUO_FOUNDATIONAL_AGENT_MOCK.name }),
      );
    });

    it('selects the agent when catalogAgents finish loading', async () => {
      pendingCatalogAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand(DUO_FOUNDATIONAL_AGENT_MOCK.name);
      await resolveCatalog();

      expect(actionSpies.setCurrentAgent).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ name: DUO_FOUNDATIONAL_AGENT_MOCK.name }),
      );
    });

    it('uses the correct agent definition when creating a workflow', async () => {
      pendingFoundationalAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand(DUO_FOUNDATIONAL_AGENT_MOCK.name);
      await resolveFoundational();

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'test question' }));
      await waitForPromises();

      expect(createWorkflowMutationMock).toHaveBeenCalledWith(
        expect.objectContaining({
          workflowDefinition: DUO_FOUNDATIONAL_AGENT_MOCK.referenceWithVersion,
        }),
      );
    });

    it('does not select the agent when it is not in the loaded list', async () => {
      pendingFoundationalAgentsMocks();
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await pushAgentCommand('Non-existent Agent');
      await resolveFoundational();

      expect(actionSpies.setCurrentAgent).not.toHaveBeenCalled();
    });
  });

  describe('processPendingCommands integration', () => {
    it('does not process commands when isLoading is true', async () => {
      let resolvePromise = null;
      const pendingPromise = new Promise((resolve) => {
        resolvePromise = resolve;
      });
      workflowEventsQueryMock.mockReturnValue(pendingPromise);

      getSessionStorageValue.mockReturnValue({
        exists: true,
        value: { workflowId: MOCK_WORKFLOW_ID },
      });
      createComponent({
        propsData: { projectId: MOCK_PROJECT_ID, resourceId: MOCK_RESOURCE_ID },
      });

      await nextTick();

      const testQuestion = 'What is GitLab CI/CD?';

      duoChatGlobalState.commands = [{ question: testQuestion }];

      await nextTick();

      expect(createWorkflowMutationMock).not.toHaveBeenCalled();

      resolvePromise({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });

      await waitForPromises();

      await nextTick();

      // Commands should be processed after hydration completes
      expect(createWorkflowMutationMock).toHaveBeenCalledWith(
        expect.objectContaining({
          goal: testQuestion,
        }),
      );
    });
  });

  describe('triggerSource', () => {
    it('is set to web_chat when user sends a prompt', async () => {
      createComponent();
      await waitForPromises();

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'some question' }));

      findDuoChat().vm.$emit('approve-tool');
      await nextTick();

      expect(EventsTracker.updateContext).toHaveBeenCalledWith(
        expect.objectContaining({ triggerSource: TRIGGER_SOURCE_WEB_CHAT }),
      );
    });

    it('is set to web_ui when processing commands and passed to tracked events', async () => {
      createComponent();
      await waitForPromises();

      duoChatGlobalState.commands = [{ question: 'Deploy my app' }];
      await nextTick();
      await waitForPromises();

      findDuoChat().vm.$emit('approve-tool');
      await nextTick();

      expect(EventsTracker.updateContext).toHaveBeenCalledWith(
        expect.objectContaining({ triggerSource: TRIGGER_SOURCE_WEB_UI }),
      );
    });
  });

  describe('errorCaptured', () => {
    ignoreConsoleMessages([
      /^\[Vue warn\]: Error in mounted hook: "Error: child component exploded"/,
      /^Error: child component exploded/,
    ]);

    it('reports the error and component info to Sentry', () => {
      const error = new Error('child component exploded');

      try {
        createComponent({
          stubs: {
            DuoAgenticChatView: stubComponent(DuoAgenticChatView, {
              mounted() {
                throw error;
              },
            }),
          },
        });
      } catch {
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(error, {
          extra: { info: 'mounted hook', component: 'DuoAgenticChatView' },
        });
      }
    });
  });
});
