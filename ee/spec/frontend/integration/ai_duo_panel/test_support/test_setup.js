/**
 * Shared mounting and DOM vocabulary for the Duo chat frontend integration specs,
 * both the agentic surface and the classic one.
 *
 * Helpers are added by the MR that first needs them, so nothing here is
 * unused. This file therefore grows across the series rather than arriving
 * complete.
 */
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import { fireEvent, within } from '@testing-library/vue';
import { duoChatGlobalState, CHAT_MODES } from 'ee/ai/state';
import AiPanel from 'ee/ai/components/ai_panel.vue';
import { createApolloProvider } from 'ee/ai/graphql';
import { createRouter } from 'ee/ai/duo_agents_platform/router/ai_panel_router';
import {
  AGENTIC_CHAT_HISTORY_ROUTE,
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import DuoAgenticChatStateManager from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_state_manager.vue';
import createStore from 'ee/ai/tanuki_bot/store';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat';
import { initializePlugins } from 'ee/ai/duo_agentic_chat/plugins';
import { workflowStreamFactory } from 'ee/ai/duo_agentic_chat/websocket/workflow_stream_factory';
import { fullMount, getText, setInputValue } from 'ee_jest/integration/helpers/test_helpers';
import { installWebSocketMock, restoreWebSocket } from './websocket_mock';

Vue.use(VueApollo);
Vue.use(VueRouter);

const NAMESPACE_ID = 'gid://gitlab/Group/1';
export const PROJECT_ID = 'gid://gitlab/Project/1';
// Must match `rules_project.full_path` in
// ee/spec/frontend/fixtures/ai_duo_panel_integration.rb, which is where the
// AGENTS.md / chat-rules.md blobs the rule context provider reads come from.
export const PROJECT_PATH = 'group/project-with-rules';

// Load-bearing for every mount: without it `checkNamespaceAvailability` disables
// the chat and the "select a default namespace" empty state masks everything else.
// Spread rather than repeated so the reason has one home.
const NAMESPACE_SELECTED_PROPS = { defaultNamespaceSelected: true };

/**
 * Mirrors the production wiring in `ee/ai/init_duo_panel.js`: the same values
 * feed `chatConfiguration.defaultProps` (consumed as route props) and the
 * `AiPanel` props (bound on `<router-view>`), so specs set them in one place.
 */
export const buildChatConfiguration = ({ defaultProps = {}, ...overrides } = {}) => ({
  agenticTitle: 'GitLab Duo Agentic Chat',
  classicTitle: 'GitLab Duo Chat',
  defaultProps: {
    isAgenticAvailable: true,
    isClassicAvailable: false,
    // Required by both state managers, which scope per-user storage keys with it.
    userId: 'gid://gitlab/User/1',
    namespaceId: NAMESPACE_ID,
    rootNamespaceId: NAMESPACE_ID,
    ...NAMESPACE_SELECTED_PROPS,
    duoSettingsPath: '/groups/gitlab-org/-/settings/gitlab_duo',
    chatDisabledReason: '',
    isDuoDisabled: false,
    isDuoDisabledNonAdmin: false,
    // Read by `createRouter` to decide the startup route, so it belongs here
    // rather than only on the panel props.
    shouldShowBlockedState: false,
    containerType: 'group',
    canStartTrial: false,
    isTrialExpired: false,
    forceAgenticModeForCoreDuoUsers: false,
    canBuyAddon: false,
    userModelSelectionEnabled: false,
    // Required prop on the blocked-state view, always set by init_duo_panel.js.
    accessDenied: false,
    identityVerificationRequired: false,
    // Gates the Sessions tab in the navigation rail.
    isDuoAgentPlatformEnabled: true,
    ...defaultProps,
  },
  ...overrides,
});

/**
 * Classic-chat counterpart of `buildChatConfiguration`. Flipping the two
 * availability flags is what routes every rail toggle to `CLASSIC_CHAT_*` and
 * keeps `isAgenticMode` false. `autoExpand` is separately load-bearing:
 * `createRouter` starts on `CLOSED_ROUTE` without it, so no chat body renders.
 */
export const buildClassicChatConfiguration = ({ defaultProps = {}, ...overrides } = {}) =>
  buildChatConfiguration({
    autoExpand: true,
    defaultProps: {
      isAgenticAvailable: false,
      isClassicAvailable: true,
      ...defaultProps,
    },
    ...overrides,
  });

const STATE_MANAGER_PROVIDE = {
  badgeType: 'beta',
  chatConfiguration: {
    title: 'GitLab Duo Agentic Chat',
    isClassicAvailable: false,
    defaultProps: { ...NAMESPACE_SELECTED_PROPS },
  },
  activeTabData: {
    props: {
      isClassicAvailable: false,
      userId: null,
    },
  },
  duoUiNext: false,
};

// Both mount helpers below bypass `initDuoPanel`, which is where production builds
// the registry and registers the bundled plugins, so the harness does it instead.
// One registry per mount, built fresh so a spec can provide its own instead.
const buildPluginRegistry = () => {
  const registry = new DuoChatPluginRegistry();
  initializePlugins(registry);
  return registry;
};

// A state-manager-only mount still needs a real router, because VueRouter makes
// `$router` read-only and a `mocks: { $router }` stub cannot overwrite it. Only
// the routes the state manager pushes to are needed, plus a root route: the Vue 3
// router shim navigates to the initial location during `install()`, and without a
// match for `''` it warns, which aborts the rest of the plugin chain and leaves
// the component without `$store`. `ai_panel_router.js` carries the same route for
// the same reason.
const createStateManagerRouter = () =>
  new VueRouter({
    mode: 'abstract',
    routes: [
      { name: 'root', path: '', component: { render: () => null } },
      { name: AGENTIC_CHAT_SHOW_ROUTE, path: '/agentic-chat', component: { render: () => null } },
      {
        name: AGENTIC_CHAT_NEW_ROUTE,
        path: '/agentic-chat/new',
        component: { render: () => null },
      },
      {
        name: AGENTIC_CHAT_HISTORY_ROUTE,
        path: '/agentic-chat/history',
        component: { render: () => null },
      },
    ],
  });

const mountedWrappers = [];

// Mount helpers are wrapped so `teardownDuoChatTest` can destroy every wrapper
// itself; see its docblock for why that has to happen before `terminate()`.
const trackMountedWrapper =
  (mount) =>
  (...args) => {
    const wrapper = mount(...args);
    mountedWrappers.push(wrapper);
    return wrapper;
  };

/**
 * Mounts the whole AI sidebar (navigation rail + router + chat), which is what the
 * navigation rail, the agent picker and anything keyed off `$route.name` need.
 *
 * `namespace` selects which index component the Sessions route resolves to, the same
 * way `init_duo_panel.js` does in production. It defaults to `user` because that is
 * what every spec here needed before the side panel had its own namespace.
 */
export const mountAISidebar = trackMountedWrapper(
  ({
    chatConfiguration = buildChatConfiguration(),
    propsData = {},
    namespace = 'user',
    provide = {},
  } = {}) => {
    const { defaultProps } = chatConfiguration;

    return fullMount(AiPanel, {
      store: createStore(),
      router: createRouter('/', namespace, chatConfiguration),
      apolloProvider: createApolloProvider(),
      propsData: {
        chatDisabledReason: defaultProps.chatDisabledReason,
        shouldShowBlockedState: defaultProps.shouldShowBlockedState,
        userId: defaultProps.userId,
        projectId: defaultProps.projectId,
        namespaceId: defaultProps.namespaceId,
        rootNamespaceId: defaultProps.rootNamespaceId,
        userModelSelectionEnabled: defaultProps.userModelSelectionEnabled,
        ...propsData,
      },
      provide: {
        isSidePanelView: true,
        chatConfiguration,
        badgeType: 'beta',
        duoChatPluginRegistry: buildPluginRegistry(),
        ...provide,
      },
    });
  },
);

/**
 * Mounts just the chat state manager. Cheaper than the whole panel and enough
 * for anything asserted inside `chat-component`.
 *
 * The wrapper is destroyed for us: `teardownDuoChatTest` destroys every mounted
 * wrapper, so specs neither hold on to it nor destroy it.
 */
export const mountDuoAgenticChatStateManager = trackMountedWrapper(
  ({ propsData = {}, provide = {} } = {}) =>
    fullMount(DuoAgenticChatStateManager, {
      store: createStore(),
      router: createStateManagerRouter(),
      apolloProvider: createApolloProvider(),
      propsData: {
        userId: 'gid://gitlab/User/1',
        mode: 'active',
        exploreAiCatalogPath: '/-/ai/catalog',
        ...propsData,
      },
      provide: {
        ...STATE_MANAGER_PROVIDE,
        duoChatPluginRegistry: buildPluginRegistry(),
        ...provide,
      },
    }),
);

/**
 * Resets everything the panel persists between mounts: web storage (which holds
 * the selected model and the current workflow id) and the `duoChatGlobalState`
 * observable, which is module-scoped and therefore survives unmounting.
 *
 * `chatMode` has to be set here rather than inferred from the chat
 * configuration: it is the panel's own single source of truth for which surface
 * is active, and a classic spec that leaves it on `AGENTIC` gets agentic routes
 * from every rail toggle.
 */
export const clearPanelStorage = ({ chatMode = CHAT_MODES.AGENTIC } = {}) => {
  window.localStorage.clear();
  window.sessionStorage.clear();
  duoChatGlobalState.chatMode = chatMode;
  duoChatGlobalState.lastRoutePerTab = {};
};

/**
 * `beforeEach` body for every spec that renders the chat. Fakes the websocket
 * transport -- installed even where no prompt is sent, so that an unexpected
 * connection attempt is caught by the fake instead of reaching the real
 * `WebSocket` -- and drops panel state left behind by an earlier test.
 *
 * Specs that drive a workflow install their GraphQL handlers on top of this.
 */
export const setupDuoChatTest = ({ chatMode } = {}) => {
  installWebSocketMock();
  clearPanelStorage({ chatMode });
};

/**
 * `afterEach` counterpart. Destroys the mounted wrappers itself, before
 * terminating the stream, because `beforeDestroy` hooks read its connection
 * state. Leaving that to VTU's `enableAutoDestroy` would invert the
 * order: `shared_test_setup.js` registers it in the root block, so it runs
 * after any `afterEach` a spec registers inside a `describe`. It still runs
 * afterwards as a safety net -- destroying twice is a no-op.
 *
 * Terminating the stream is the other part worth knowing about: the factory hands
 * out one shared instance, and its worker, subscribers and message buffer outlive
 * the unmount, so releasing them cannot be left to the component teardown.
 */
export const teardownDuoChatTest = () => {
  try {
    mountedWrappers.forEach((wrapper) => wrapper.destroy());
  } finally {
    // Still runs if a destroy() throws, so nothing leaks into the next test.
    mountedWrappers.length = 0;
    workflowStreamFactory.getWorkflowStream().terminate();
    restoreWebSocket();
    clearPanelStorage();
  }
};

// --- finders -----------------------------------------------------------------
// All return DOM nodes (or null) so specs assert against the real rendered DOM.

// Null-safe in the container so nesting two lookups still honours the contract
// above: a missing outer element yields null rather than throwing.
const byTestId = (testId, container = document) =>
  container?.querySelector(`[data-testid="${testId}"]`) ?? null;

export const findChatInput = () => byTestId('chat-prompt-input');
const findChatForm = () => byTestId('chat-prompt-form');

export const findSubmitButton = () => byTestId('chat-prompt-submit-button');

export const findChatToggle = () => byTestId('ai-chat-toggle');
export const findHistoryToggle = () => byTestId('ai-history-toggle');
export const findSessionsToggle = () => byTestId('ai-sessions-toggle');

// The blocked state replaces the usual tabs when Duo is off for the container.
// Named for its testid rather than `findEmptyState`, which the chat's own
// `gl-duo-chat-empty-state` takes.
export const findDuoDisabledToggle = () => byTestId('duo-disabled-toggle');
export const findDuoDisabledEmptyState = () => byTestId('duo-disabled-empty-state');
export const findDuoSettingsCta = () => byTestId('duo-settings-cta');

export const findDuoAgenticChatPanel = () => byTestId('duo-agentic-chat');
export const findThreadListPanel = () => byTestId('duo-chat-threads');
export const findAgentSessionsPanel = () => byTestId('agent-sessions');

/** The individual rows of the thread list found by `findThreadListPanel`. */
export const findThreadBoxes = () =>
  document.querySelectorAll('[data-testid="chat-threads-thread-box"]');

/** The history row whose title holds `text`, or null. */
export const findThreadBoxWithText = (text) =>
  Array.from(findThreadBoxes()).find((box) => box.textContent.includes(text)) ?? null;

/**
 * The rendered conversation, and the container to make message assertions
 * against: a prompt string also appears in the thread list that titles a
 * conversation after it, so asserting on the document cannot tell "the chat
 * replied" apart from "the chat is listed in history".
 */
export const findChatMessages = () => byTestId('chat-messages');

export const findChatComponent = () => byTestId('chat-component');

// Shown in place of the conversation when the selected thread can no longer be
// posted to, which is what an archived workflow looks like to the UI.
export const findThreadInactiveEmptyState = () => byTestId('thread-inactive-empty-state');
export const findBackToThreadsButton = () =>
  byTestId('back-to-threads-button', findThreadInactiveEmptyState());

// The chat header's error banner, which also carries the "conversation deleted"
// message.
export const findChatError = () => byTestId('chat-error');

export const findEmptyState = () => byTestId('gl-duo-chat-empty-state');
export const findCancelButton = () => byTestId('chat-prompt-cancel-button');
export const findMessages = () => document.querySelectorAll('.duo-chat-message');

// The manual-retry action on a finished turn (`turn_feedback_bar.vue`'s
// `agentic-retry` widget) and the pager it renders once a retry collapses into
// alternatives (`alternative_pager.vue`). The testid is the one
// `turn_feedback_bar.vue` sets on the widget: it lands on the button root via
// attribute fallthrough, overriding the button's own `agentic-retry-button`.
export const findRetryButton = () => byTestId('agentic-retry');
export const findAlternativePagerPrevious = () => byTestId('alternative-pager-previous');
export const findAlternativePagerNext = () => byTestId('alternative-pager-next');
export const findAlternativePagerPosition = () => byTestId('alternative-pager-position');

// Prompts the user submitted while a turn was in flight, rendered below the
// conversation until the queue releases them.
export const findQueuedPromptMessages = () =>
  document.querySelectorAll('[data-testid="queued-prompt-message"]');
export const findQueuedPromptRemoveButton = () =>
  byTestId('queued-prompt-remove-button', findQueuedPromptMessages()[0]);

/** Finds a button by accessible name anywhere in the document. */
export const findButton = (name, container = document.body) =>
  within(container).queryAllByRole('button', { name })[0] || null;

export const findPanelHeading = () => byTestId('content-container-title');
export const panelHeadingText = () => {
  const heading = findPanelHeading();
  return heading === null ? null : getText(heading);
};

// Only the redesigned single header emits a subtitle, so this is null whenever
// the chat keeps a header of its own.
export const findPanelSubheading = () => byTestId('content-container-subtitle');
export const panelSubheadingText = () => {
  const subheading = findPanelSubheading();
  return subheading === null ? null : getText(subheading);
};

// The prompt footer is the cleanest discriminator between the classic chat view
// and the history list: the list hides it, the conversation shows it. Both are
// asserted through the DOM because this suite bans reaching into the router or
// the route-derived computeds.
export const isShowingClassicChatView = () => byTestId('chat-footer') !== null;
export const isShowingClassicListView = () => findThreadBoxes().length > 0;

export const findApproveButton = () => byTestId('approve-tool-inline');
export const findDenyButton = () => byTestId('deny-tool-inline');

// The row testids come from duo-ui's `message_tool_row.vue`, the metadata chip
// from `message_tool.vue` -- hence the two prefixes.
export const findToolRowLabel = () => byTestId('tool-row-label');
export const findToolRowSecondary = () => byTestId('tool-row-secondary');
export const findToolMessageProjectInfo = () => byTestId('tool-message-project-info');

// The two halves of the compact plugin: the indicator that stands in for the
// `/compact` prompt while it runs, and the divider that marks where the
// conversation was compacted.
export const findCompactingIndicator = () => byTestId('compacting-indicator');
export const findCompactionDelimiter = () => byTestId('compaction-delimiter');

// duo-ui's generic "Duo is generating an answer" loader. The testid is bound on the
// component in our own view and falls through to duo-ui's root, which carries none.
export const findResponseLoader = () => byTestId('response-loader');

export const findContextSelectionTitles = () =>
  document.querySelectorAll('[data-testid="chat-context-selections-title"]');

// Direction marks GlTruncate pads its two halves with, so the visible label can be
// compared as a plain string.
const BIDI_MARKS = /[\u200b-\u200f\u202a-\u202e]/g;

/**
 * The visible labels of the context tokens on a user message.
 *
 * Taken from duo-ui's own `context-item-*-title` elements inside its tokens
 * wrapper. The `aria-label` carrying the same text belongs to GlTruncate and only
 * exists in its middle-truncation mode, so a library bump could take it away.
 */
export const findContextTokenLabels = () =>
  Array.from(
    byTestId('chat-context-tokens-wrapper')?.querySelectorAll(
      '[id^="context-item-"][id$="-title"]',
    ) ?? [],
  ).map((token) => token.textContent.replace(BIDI_MARKS, '').replace(/\s+/g, ' ').trim());

export const findSlashCommandsMenu = () => byTestId('slash-commands-panel');

/** The command rows of the menu found by `findSlashCommandsMenu`. */
export const findSlashCommandOptions = () =>
  Array.from(findSlashCommandsMenu()?.querySelectorAll('[role="option"]') ?? []);

export const findChatSubheader = () => byTestId('chat-subheader');
export const findAgentToggle = () => byTestId('add-new-agent-toggle');
export const findAgentItem = (agentId) => byTestId(`listbox-item-${agentId}`);

// Scoped to the dropdown: `toggle-button` is a generic GlCollapsibleListbox testid.
export const findModelToggle = () =>
  byTestId('toggle-button', byTestId('model-dropdown-container'));
export const findModelToggleText = () => byTestId('dropdown-toggle-text');
export const findModelItem = (ref) => byTestId(`listbox-item-${ref}`);

// --- interactions ------------------------------------------------------------

/**
 * Submits a prompt. The send is wired to `@submit.stop.prevent` on `gl-form`,
 * so dispatching `submit` on the form is the DOM equivalent of pressing Enter.
 */
export const sendPrompt = (text) => {
  setInputValue(findChatInput(), text);
  findChatForm().dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
};

/**
 * Types into the composer without submitting. Assigning the value leaves the
 * caret at the end, which the slash-command menu reads to decide whether the
 * caret still sits on the token it is completing.
 *
 * `sendPrompt` is the shortcut for "prompt and send"; this is for the cases that
 * need the intermediate state.
 */
export const typeInComposer = (text) => setInputValue(findChatInput(), text);

/**
 * Presses and releases a key in the composer, for behaviour wired to the
 * keyboard rather than to form submission. Both halves matter: the slash menu
 * acts on keydown, while sending the prompt is wired to keyup. Resolves after
 * Vue has re-rendered.
 */
export const pressComposerKey = async (key) => {
  const input = findChatInput();

  await fireEvent.keyDown(input, { key });
  await fireEvent.keyUp(input, { key });
};

export const cancelPrompt = () => findCancelButton().click();

export const openChatTab = () => findChatToggle().click();
export const openHistoryTab = () => findHistoryToggle().click();

export const approveTool = () => findApproveButton().click();
export const openAgentDropdown = () => findAgentToggle().querySelector('button').click();
