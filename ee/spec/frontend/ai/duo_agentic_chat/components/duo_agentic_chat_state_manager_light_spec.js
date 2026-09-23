import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import VueApollo from 'vue-apollo';
import { parseDocument } from 'yaml';
import { getInstanceSlots, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { getSessionStorageValue } from '~/lib/utils/local_storage';
import waitForPromises from 'helpers/wait_for_promises';
import { createUserPrompt } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import storeMutations from 'ee/ai/tanuki_bot/store/mutations';
import * as storeActions from 'ee/ai/tanuki_bot/store/actions';
import getUserWorkflows from 'ee/ai/graphql/get_user_workflow.query.graphql';
import getAiChatContextPresets from 'ee/ai/graphql/get_ai_chat_context_presets.query.graphql';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import getConfiguredAgents from 'ee/ai/graphql/get_configured_agents.query.graphql';
import getAgentFlowConfig from 'ee/ai/graphql/get_agent_flow_config.query.graphql';
import getFoundationalChatAgents from 'ee/ai/graphql/get_foundational_chat_agents.graphql';
import getFlowStatus from 'ee/ai/graphql/get_flow_status.query.graphql';
import duoWorkflowMutation from 'ee/ai/graphql/duo_workflow.mutation.graphql';
import deleteAgenticWorkflowMutation from 'ee/ai/graphql/delete_agentic_workflow.mutation.graphql';
import updateWebSearchMutation from 'ee/ai/graphql/update_duo_workflow_web_search.mutation.graphql';
import getWorkflowLatestCheckpointQuery from 'ee/ai/graphql/get_workflow_latest_checkpoint.query.graphql';
import getWorkflowBranchesQuery from 'ee/ai/graphql/get_workflow_branches.query.graphql';
import getGitlabCreditsStatusQuery from 'ee/ai/graphql/get_gitlab_credits_status.query.graphql';
import DuoAgenticChatStateManagerLight from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_state_manager_light.vue';
import DuoAgenticChatView from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_view.vue';
import PromptInputActions from 'ee/ai/duo_agentic_chat/components/prompt_input_actions.vue';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import {
  getCurrentModel,
  getDefaultModel,
  getModel,
  saveModel,
  isModelSelectionDisabled as checkModelSelectionDisabled,
} from 'ee/ai/duo_agentic_chat/utils/model_selection_utils';
import * as WorkflowSocketUtils from 'ee/ai/duo_agentic_chat/websocket/workflow_utils';
import { loadThreadSnapshot } from 'ee/ai/duo_agentic_chat/utils/chat_thread_snapshot';
import { AGENTIC_CHAT_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import {
  MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE,
  MOCK_GITLAB_DEFAULT_MODEL_ITEM,
  MOCK_CONFIGURED_AGENTS_RESPONSE,
  MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE,
  MOCK_FLOW_CONFIG_RESPONSE,
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

jest.mock('~/lib/utils/websocket_utils', () => ({
  parseMessage: jest.fn(async (event) => {
    const data = typeof event.data === 'string' ? event.data : await event.data.text();
    return JSON.parse(data);
  }),
}));

jest.mock('ee/ai/duo_agentic_chat/utils/workflow_utils', () => ({
  WorkflowUtils: {
    transformChatMessages: jest.fn(),
    parseWorkflowData: jest.fn(),
    normalizeDuoMessages: jest.fn(),
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
    reset: jest.fn(),
  },
}));

const MOCK_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/456';
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
const MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE = {
  data: {
    deleteDuoWorkflowsWorkflow: { success: true, clientMutationId: null, errors: [] },
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

const MOCK_USER_WORKFLOWS_RESPONSE = {
  data: {
    duoWorkflowWorkflows: {
      pageInfo: { endCursor: null, hasNextPage: false },
      edges: [
        {
          node: {
            id: MOCK_WORKFLOW_ID,
            title: 'Test workflow goal',
            lastUpdatedAt: '2024-01-01T00:00:00Z',
            aiCatalogItemVersionId: null,
            agentName: 'GitLab Duo',
            archived: false,
          },
        },
      ],
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

Vue.use(Vuex);
Vue.use(VueApollo);

jest.mock('~/lib/utils/common_utils', () => ({
  getCookie: jest.fn(),
}));

jest.mock('~/lib/utils/local_storage', () => ({
  getStorageValue: jest.fn(() => ({ exists: false })),
  saveStorageValue: jest.fn(),
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

describe('Duo Agentic Chat State Manager Light', () => {
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

  const mockRefetch = jest.fn().mockResolvedValue({});
  let mockRouter;
  let mockRoute;
  const userWorkflowsQueryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_WORKFLOWS_RESPONSE);
  const contextPresetsQueryHandlerMock = jest.fn().mockResolvedValue(MOCK_CONTEXT_PRESETS_RESPONSE);
  const availableModelsQueryHandlerMock = jest
    .fn()
    .mockResolvedValue(MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE);
  const configuredAgentsQueryMock = jest.fn().mockResolvedValue(MOCK_CONFIGURED_AGENTS_RESPONSE);
  const aiFoundationalChatAgentsQueryMock = jest
    .fn()
    .mockResolvedValue(MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE);
  const agentFlowConfigQueryMock = jest.fn().mockResolvedValue(MOCK_FLOW_CONFIG_RESPONSE);
  const flowStatusQueryMock = jest.fn().mockResolvedValue({
    data: {
      duoWorkflowWorkflows: {
        edges: [
          {
            node: {
              id: '1',
              status: 'completed',
            },
          },
        ],
      },
    },
  });
  const createWorkflowMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
  const deleteWorkflowMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
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
      [getUserWorkflows, userWorkflowsQueryHandlerMock],
      [getAiChatContextPresets, contextPresetsQueryHandlerMock],
      [getConfiguredAgents, configuredAgentsQueryMock],
      [getFoundationalChatAgents, aiFoundationalChatAgentsQueryMock],
      [getAgentFlowConfig, agentFlowConfigQueryMock],
      [getFlowStatus, flowStatusQueryMock],
      [duoWorkflowMutation, createWorkflowMutationMock],
      [deleteAgenticWorkflowMutation, deleteWorkflowMutationMock],
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

    wrapper = mountFn(DuoAgenticChatStateManagerLight, {
      store,
      apolloProvider,
      propsData,
      provide: defaultProvide,
      mocks: {
        $router: mockRouter,
        $route: mockRoute,
      },
      stubs,
      data() {
        return data;
      },
    });

    if (wrapper.vm.$apollo?.queries?.agenticWorkflows) {
      wrapper.vm.$apollo.queries.agenticWorkflows.refetch = mockRefetch;
    }
  };

  beforeEach(() => {
    mockRefetch.mockClear();
    loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);
    MOCK_UTILS_SETUP();
    // Reset Apollo handler mocks to default values
    createWorkflowMutationMock.mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
    deleteWorkflowMutationMock.mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
    workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
    workflowBranchesQueryMock.mockClear();
    workflowBranchesQueryMock.mockResolvedValue({ data: { duoWorkflowBranches: [] } });
    creditsAvailableQueryMock.mockResolvedValue({
      data: { gitlabCreditsAvailable: true, gitlabCreditsUnavailableReason: null },
    });
    userWorkflowsQueryHandlerMock.mockResolvedValue(MOCK_USER_WORKFLOWS_RESPONSE);
    // In the default state, there isn't workflowId registered in session storage
    getSessionStorageValue.mockReturnValue({ exists: false, value: null });
  });

  afterEach(() => {
    if (wrapper) {
      wrapper = null;
    }
  });

  describe('reduced presentation', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the agentic chat view', () => {
      expect(findDuoChat().exists()).toBe(true);
    });

    it('hides the chat header', () => {
      expect(findDuoChat().props('showHeader')).toBe(false);
    });

    it('does not provide the subheader or prompt-control slots', () => {
      const slots = getInstanceSlots(findDuoChat().vm);

      expect(slots.subheader).toBeUndefined();
      expect(slots['agentic-model']).toBeUndefined();
      expect(slots['agentic-switch']).toBeUndefined();
    });

    it('passes an empty chatPromptPlaceholder through by default', () => {
      expect(findDuoChat().props('chatPromptPlaceholder')).toBe('');
    });

    it('passes a custom chatPromptPlaceholder to AgenticDuoChat', () => {
      createComponent({
        propsData: { chatPromptPlaceholder: 'What would you like to work on?' },
      });

      expect(findDuoChat().props('chatPromptPlaceholder')).toBe('What would you like to work on?');
    });

    it('replaces the welcome empty state with a blank element for a subscribed user', () => {
      createComponent({ propsData: { subscriptionActive: true } });

      const [vnode] = getInstanceSlots(findDuoChat().vm)['custom-empty-state']({});

      expect(vnode.componentOptions).toBeUndefined();
      const testId = vnode.props
        ? vnode.props['data-testid'] // Vue 3
        : vnode.data.attrs['data-testid']; // Vue 2
      expect(testId).toBe('duo-chat-empty-state-opt-out');
    });

    it('provides the empty-state slot even when no gating state applies, keeping the view fallback hidden', () => {
      expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']({})).toBeDefined();
    });

    it('still renders gating empty states', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });
      createComponent();
      await waitForPromises();

      const emptyState = getInstanceSlots(findDuoChat().vm)['custom-empty-state']({});

      expect(emptyState[0].componentOptions).toBeDefined();
    });
  });

  describe('@select-alternative', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

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
        data: { duoWorkflowBranches: [{ forkThreadTs: 'ts-fork', messages: [] }] },
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

    it('ignores navigation while a turn is in flight', async () => {
      seedMessages([
        { id: 'user-1', role: 'user', content: 'What is GitLab?' },
        { id: 'assistant-1', role: 'assistant', content: 'First (failed) answer' },
        { id: 'user-2', role: 'user', content: 'What is GitLab?' },
        { id: 'assistant-2', role: 'assistant', content: 'Second answer' },
      ]);

      // Sending a prompt marks the turn as in flight (isWaitingOnPrompt).
      findDuoChat().vm.$emit('send-chat-prompt', 'What is GitLab?');
      await nextTick();

      findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-2', index: 1 });
      await waitForPromises();

      expect(findDuoChat().props('selectedAlternatives')).toEqual({});
    });
  });

  // This variant is a parallel copy of the full state manager, so the attachment
  // wiring has to be asserted here too. Without it the composer would accept files
  // and this manager would drop them on the way to the flow service.
  describe('attachments', () => {
    const attachment = {
      id: 'att-1',
      filename: 'diagram.png',
      mimeType: 'image/png',
      byteSize: 2048,
      data: 'aGVsbG8=',
      previewUrl: 'data:image/png;base64,aGVsbG8=',
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('forwards the attachments as additional context', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: 'Explain this image', attachments: [attachment] }),
      );
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([
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

    // An image on its own is a user turn, not an approval resume, so it keeps the
    // context that only a user turn carries.
    it('carries the foundational agent context when only images are sent', async () => {
      // Assigned rather than passed as `data`: loading the workflow resolves the
      // selection itself, and would clear a value seeded before it.
      wrapper.vm.orbitEnabled = true;
      wrapper.vm.selectedFoundationalAgent = {
        referenceWithVersion: 'agent@1.0.0',
        flowConfig: null,
      };

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ attachments: [attachment] }));
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext).toEqual(
        expect.arrayContaining([
          {
            category: 'orbit_context',
            content: JSON.stringify({ orbit_enabled: true }),
            metadata: '{}',
          },
        ]),
      );
    });

    it('adds no attachments envelope when the event omits them', async () => {
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Just text' }));
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([]);
    });

    it('opens the file picker when the actions menu asks for it', () => {
      const openFilePicker = jest.fn();
      findDuoChat().vm.openFilePicker = openFilePicker;

      findPromptInputActions().vm.$emit('attach-files');

      expect(openFilePicker).toHaveBeenCalled();
    });
  });

  describe('retry after compaction', () => {
    const compactedMessages = [
      { id: 'user-1', role: 'user', content: 'Prompt' },
      { id: 'assistant-1', role: 'assistant', content: 'Response' },
      {
        id: 'compaction-1',
        role: 'tool',
        message_type: 'tool',
        message_sub_type: 'compaction',
        content: 'Summarized 2 messages',
      },
    ];
    const seedMessages = (messages) => {
      messages.forEach((m) => store.commit('ADD_MESSAGE', m));
    };

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

    it('forwards is-retry-enabled=false when a compaction follows the last prompt', async () => {
      seedMessages(compactedMessages);
      await nextTick();

      expect(findDuoChat().props('isRetryEnabled')).toBe(false);
    });

    it('forwards is-retry-enabled=true again once a new prompt follows the compaction', async () => {
      seedMessages([
        ...compactedMessages,
        { id: 'user-2', requestId: 'req-2', role: 'user', content: 'A new prompt' },
        { id: 'assistant-2', requestId: 'req-2', role: 'assistant', content: 'A new response' },
      ]);
      await nextTick();

      expect(findDuoChat().props('isRetryEnabled')).toBe(true);
    });
  });
});
