<script>
// eslint-disable-next-line no-restricted-imports
import { mapActions, mapState } from 'vuex';
import { debounce } from 'lodash-es';
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import getFlowStatus from 'ee/ai/graphql/get_flow_status.query.graphql';
import ChatLoadingState from 'ee/ai/components/chat_loading_state.vue';
import { removeDraft } from 'ee/ai/utils/chat_draft_storage';
import getConfiguredAgents from 'ee/ai/graphql/get_configured_agents.query.graphql';
import getFoundationalChatAgents from 'ee/ai/graphql/get_foundational_chat_agents.graphql';
import getAgentFlowConfig from 'ee/ai/graphql/get_agent_flow_config.query.graphql';
import getGitlabCreditsStatusQuery from 'ee/ai/graphql/get_gitlab_credits_status.query.graphql';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import { computeTrustedUrls } from 'ee/ai/shared/utils/trusted_urls_utils';
import {
  getSessionStorageValue,
  saveSessionStorageValue,
  removeSessionStorageValue,
} from '~/lib/utils/local_storage';
import { duoChatGlobalState } from 'ee/ai/state';
import { clearDuoChatCommands, setAgenticMode } from 'ee/ai/utils';
import { maybeDoBarrelRoll } from 'ee/ai/easter_eggs/barrel_roll';
import { convertToGraphQLId, parseGid } from '~/graphql_shared/utils';
import { TYPENAME_AI_DUO_WORKFLOW, ENUM_USAGE_BILLING_FORBIDDEN } from '~/graphql_shared/constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { InternalEvents } from '~/tracking';
import {
  GENIE_CHAT_RESET_MESSAGE,
  GENIE_CHAT_CLEAR_MESSAGE,
  GENIE_CHAT_NEW_MESSAGE,
  GENIE_CHAT_MODEL_ROLES,
  DUO_AGENTIC_CHAT_CLIENT_CAPABILITIES,
  DUO_WORKFLOW_STATUS_RUNNING,
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
  DUO_WORKFLOW_ATTACHED_STATUSES,
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_WORKFLOW_STATUS_STOPPED,
  DUO_CURRENT_WORKFLOW_STORAGE_KEY,
  DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
  DUO_WORKFLOW_INACTIVE_CHAT_REASON,
  DUO_WORKFLOW_CHAT_DEFINITION,
  DUO_WORKFLOW_NEW_CHAT_DEFINITION,
  NEW_AGENTIC_CHAT_FLOW_CONFIG,
} from 'ee/ai/constants';
import getAiChatContextPresets from 'ee/ai/graphql/get_ai_chat_context_presets.query.graphql';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import ModelSelectDropdown from 'ee/ai/shared/feature_settings/model_select_dropdown.vue';
import { fetchPolicies } from '~/lib/graphql';
import { logError } from '~/lib/logger';
import { s__, sprintf } from '~/locale';
import { formatDefaultModelData } from 'ee/ai/shared/utils/model_selection_utils';
import {
  AGENTIC_CHAT_SHOW_ROUTE,
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_HISTORY_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { safeRouterPush } from 'ee/ai/duo_agents_platform/utils/router_utils';
import { buildAiCatalogEventProperties } from 'ee/ai/catalog/event_properties';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { captureExceptionForDuoChat } from '../observability/sentry_utils';
import { reconcileAndReportLoadedMessages } from '../observability/snapshot_divergence_reporting';
import { withCaptureErrors } from '../observability/with_capture_errors';
import { EventsTracker } from '../observability/events_tracker';
import { initMessageObservers } from '../observability/message_observers';
import { initDuoAgenticChatEventHub } from '../events/event_hub';
import { workflowStreamFactory } from '../websocket/workflow_stream_factory';
import {
  ApolloUtils,
  CONFIGURED_AGENTS_PER_PAGE,
  fetchMoreConfiguredAgents,
} from '../utils/apollo_utils';
import {
  getCurrentModel,
  getDefaultModel,
  getModel,
  saveModel,
  isModelSelectionDisabled as checkModelSelectionDisabled,
} from '../utils/model_selection_utils';
import {
  buildWebsocketUrl,
  buildStartRequest,
  processWorkflowMessage,
} from '../websocket/workflow_utils';
import { WorkflowUtils } from '../utils/workflow_utils';
import {
  validateAgentExists as validateAgent,
  prepareAgentSelection,
  catalogAgentsFromResponse,
  foundationalAgentToItemAndVersion,
} from '../utils/agent_utils';
import { formatErrorMessage } from '../utils/error_handler';
import {
  collectSupersededAttemptIds,
  excludeSupersededMessages,
  isToolApprovalRequest,
} from '../utils/messages_utils';
import { buildAttachmentContext } from '../utils/attachment_utils';
import { runMessageTransformers } from '../transformers/index';
import { clarificationQuestionTransformer } from '../transformers/clarification_question_transformer';
import { toolDenialTransformer } from '../transformers/tool_denial_transformer';
import { alternativesTransformer } from '../transformers/alternatives_transformer';
import { isCompactionMessage } from '../plugins/compact/utils';
import {
  WS_CLOSE_NORMAL,
  WORKFLOW_NOT_FOUND_CODE,
  FEEDBACK_TRACKING_EVENT,
  CHAT_TRACKING_EVENT,
  NO_DEFAULT_NAMESPACE_CODE,
  NO_RESOURCE_PERMISSIONS,
  TRACKING_EVENT_SUBMIT_MESSAGE,
  TRIGGER_SOURCE_WEB_CHAT,
  TRIGGER_SOURCE_WEB_UI,
  MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER,
  DEFAULT_AGENT_ID,
  WS_CLOSE_TRY_AGAIN_LATER,
  WS_CLOSE_POLICY_VIOLATION,
  WS_CLOSE_INVALID_REQUEST,
  RETRY_STATE,
} from '../constants';
import {
  saveThreadSnapshot,
  loadThreadSnapshot,
  clearThreadSnapshot,
} from '../utils/chat_thread_snapshot';
import {
  isWebSearchAvailable,
  loadWebSearchPreference,
  saveWebSearchPreference,
} from '../utils/web_search_preference';
import { loadActiveWorkflowWithRetry, isThreadLoadAborted } from '../services/load_active_workflow';
import { SystemContextManager } from '../context/system_context_manager';
import { PageContextProvider } from '../context/page_context_provider';
import { RuleContextProvider } from '../context/rule_context_provider';
import { createUserPrompt, EMPTY_USER_PROMPT } from '../services/user_prompt';
import { getExternalContextItems } from '../context/external_context_store';
import { DuoChatPluginRegistry } from '../services/plugin_registry';
import { slashCommandContextFor } from '../context/slash_commands_context';
import { messageWidgets, messageTransformers } from '../services/plugin_capabilities';
import PromptQueue from './prompt_queue.vue';
import DuoAgenticChatHeader from './duo_agentic_chat_header.vue';
import AgenticModeToggle from './agentic_mode_toggle.vue';
import ChatModelSelector from './model_selection/chat_model_selector.vue';
import PromptInputActions from './prompt_input_actions.vue';
import OrbitToggle from './orbit_toggle.vue';
import NoNamespaceEmptyState from './no_namespace_empty_state.vue';
import NoCreditsEmptyState from './no_credits_empty_state.vue';
import CreditsExhaustedAlert from './credits_exhausted_alert.vue';
import NoBillingForbiddenEmptyState from './no_billing_forbidden_empty_state.vue';
import ConnectionErrorAlert from './connection_error_alert.vue';
import FreeAddonExhaustedEmptyState from './free_addon_exhausted_empty_state.vue';
import ActiveTrialOrSubscriptionEmptyState from './active_trial_or_subscription_empty_state.vue';
import DuoAgenticChatView from './duo_agentic_chat_view.vue';
import ThreadInactiveEmptyState from './thread_inactive_empty_state.vue';
import ThreadLoadErrorEmptyState from './thread_load_error_empty_state.vue';
import ThreadLoadingEmptyState from './thread_loading_empty_state.vue';
import TurnProgress from './turn_progress.vue';

const BUILT_IN_MESSAGE_TRANSFORMERS = [clarificationQuestionTransformer, toolDenialTransformer];

const hasGraphQLErrorCode = (errorData, code) =>
  errorData?.graphQLErrors?.some((e) => e?.extensions?.code === code);

export default {
  name: 'DuoAgenticChatStateManager',
  components: {
    DuoAgenticChatView,
    GlButton,
    ModelSelectDropdown,
    ChatModelSelector,
    PromptInputActions,
    PromptQueue,
    AgenticModeToggle,
    OrbitToggle,
    DuoAgenticChatHeader,
    ChatLoadingState,
    NoNamespaceEmptyState,
    NoCreditsEmptyState,
    CreditsExhaustedAlert,
    ConnectionErrorAlert,
    FreeAddonExhaustedEmptyState,
    NoBillingForbiddenEmptyState,
    ActiveTrialOrSubscriptionEmptyState,
    ThreadInactiveEmptyState,
    ThreadLoadErrorEmptyState,
    ThreadLoadingEmptyState,
    TurnProgress,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagsMixin(), InternalEvents.mixin(), glSlotsMixin],
  inject: {
    chatConfiguration: {
      default: () => ({
        title: s__('DuoAgenticChat|GitLab Duo Agentic Chat'),
      }),
    },
    // An empty registry by default: a mount without plugins renders the built-in
    // duo-ui message types and nothing else, rather than failing.
    duoChatPluginRegistry: {
      default: () => new DuoChatPluginRegistry(),
    },
    // Mirrors prompt_input_actions: defaults to false so a mount that does not
    // provide it keeps web search off rather than granting what no group allowed.
    webSearchAllowedForGroup: {
      default: false,
    },
  },
  provide() {
    return { renderGFM };
  },
  props: {
    userId: {
      type: String,
      required: true,
    },
    projectId: {
      type: String,
      required: false,
      default: null,
    },
    projectPath: {
      type: String,
      required: false,
      default: '',
    },
    namespaceId: {
      type: String,
      required: false,
      default: null,
    },
    rootNamespaceId: {
      type: String,
      required: false,
      default: null,
    },
    resourceId: {
      type: String,
      required: false,
      default: null,
    },
    metadata: {
      type: String,
      required: false,
      default: null,
    },
    userModelSelectionEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    selectedAgentError: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    forceAgenticModeForCoreDuoUsers: {
      type: Boolean,
      required: false,
      default: true,
    },
    trustedUrls: {
      type: Array,
      required: false,
      default: () => [],
    },
    isTrial: {
      type: Boolean,
      required: false,
      default: false,
    },
    trialActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    canBuyAddon: {
      type: Boolean,
      required: false,
      default: false,
    },
    purchaseCreditsPath: {
      type: String,
      required: false,
      default: '',
    },
    tierUpgradePath: {
      type: String,
      required: false,
      default: '',
    },
    isSaas: {
      type: Boolean,
      required: false,
      default: false,
    },
    subscriptionActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSubscriptionExpired: {
      type: Boolean,
      required: false,
      default: false,
    },
    exploreAiCatalogPath: {
      type: String,
      required: false,
      default: null,
    },
    isFreeAddonCreditsUser: {
      type: Boolean,
      required: false,
      default: false,
    },
    isHandRaiseLeadAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change-title', 'change-subtitle', 'session-id-changed'],
  apollo: {
    workflowStatus: {
      query: getFlowStatus,
      pollInterval: 3000,
      // A relock restarts this query, and the cached status it would otherwise answer
      // from is the one that freed the lock last time.
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      skip() {
        return !this.isFlowLocked || !this.workflowId;
      },
      variables() {
        return {
          id: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.workflowId),
        };
      },
      update(data) {
        return data?.duoWorkflowWorkflows?.edges[0]?.node.status;
      },
      // On the result rather than a watcher on workflowStatus: two lock episodes in one
      // thread can both poll the same status, and a watcher would not fire the second
      // time, leaving the chat locked with nothing left to release it.
      async result({ data }) {
        const status = data?.duoWorkflowWorkflows?.edges[0]?.node.status;

        // Clearing on any status at all would send the queue into a flow another
        // client is still attached to, which the server rejects all over again.
        if (!this.isFlowLocked || !status || DUO_WORKFLOW_ATTACHED_STATUSES.includes(status)) {
          return;
        }

        this.isFlowLocked = false;
        await this.hydrateActiveWorkflow();
      },
    },
    contextPresets: {
      query: getAiChatContextPresets,
      variables() {
        return {
          resourceId: this.resourceId,
          projectId: this.projectId,
          namespaceId: this.namespaceId,
          url: typeof window !== 'undefined' && window.location ? window.location.href : '',
          questionCount: 4,
          foundationalAgentReference: this.selectedFoundationalAgent?.reference ?? null,
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        return data?.aiChatContextPresets || {};
      },
      // Deliberately not onError(): presets are decoration on the empty state, and
      // an error bubble for them would be persisted into the thread snapshot. The
      // empty state degrades to no prompts.
    },
    availableModels: {
      query: getAiChatAvailableModels,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      skip() {
        if (!this.userModelSelectionEnabled || this.usesModelSelector) return true;
        return !this.projectId && !this.namespaceId && !this.rootNamespaceId;
      },
      variables() {
        if (this.projectId) {
          return { projectId: this.projectId };
        }

        if (this.namespaceId) {
          return { namespaceId: this.namespaceId };
        }

        return { rootNamespaceId: this.rootNamespaceId };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        const { selectableModels = [], defaultModel, pinnedModel } = data.aiChatAvailableModels;

        const formattedDefaultModel = defaultModel
          ? formatDefaultModelData(defaultModel)
          : undefined;

        const models = selectableModels.map(
          ({ ref, name, modelProvider, modelDescription, costIndicator }) => {
            const isDefaultModel = ref === defaultModel?.ref;

            return {
              text: isDefaultModel ? formattedDefaultModel?.text : name,
              value: isDefaultModel ? formattedDefaultModel?.value : ref,
              provider: modelProvider,
              description: modelDescription,
              costIndicator,
            };
          },
        );

        this.pinnedModel = pinnedModel?.ref
          ? {
              text: pinnedModel.name,
              value: pinnedModel.ref,
            }
          : null;

        EventsTracker.updateContext({
          model: getCurrentModel({
            availableModels: models,
            pinnedModel: this.pinnedModel,
            selectedModel: this.selectedModel,
          })?.value,
        });

        return models;
      },
      error(err) {
        this.onError(err);
      },
    },
    catalogAgents: {
      query: getConfiguredAgents,
      variables() {
        return {
          includeFoundationalConsumers: false,
          first: CONFIGURED_AGENTS_PER_PAGE,
          ...(this.projectId ? { projectId: this.projectId } : { groupId: this.namespaceId }),
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      // NOTE, any update here should also be made to ee/app/assets/javascripts/ai/components/new_chat_button.vue
      update: catalogAgentsFromResponse,
      result({ data }) {
        const pageInfo = data?.aiCatalogConfiguredItems?.pageInfo;
        if (pageInfo?.hasNextPage) {
          fetchMoreConfiguredAgents(this.$apollo.queries.catalogAgents, pageInfo);
        }
      },
      error(err) {
        this.onError(err);
      },
    },
    foundationalAgents: {
      query: getFoundationalChatAgents,
      update(data) {
        return (
          data?.aiFoundationalChatAgents.nodes.map((agent) => ({
            ...agent,
            foundational: true,
          })) || []
        );
      },
      variables() {
        return {
          projectId: this.projectId,
          namespaceId: this.namespaceId,
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      error(err) {
        this.onError(err);
      },
    },
    agentConfig: {
      query: getAgentFlowConfig,
      variables() {
        return { agentVersionId: this.aiCatalogItemVersionId };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      skip() {
        return !this.aiCatalogItemVersionId;
      },
      update(data) {
        return data?.aiCatalogAgentFlowConfig;
      },
    },
    hasCredits: {
      query: getGitlabCreditsStatusQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      manual: true,
      skip() {
        return this.isSubscriptionExpired;
      },
      variables() {
        return { namespaceId: this.namespaceId };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      result({ data }) {
        if (data?.gitlabCreditsUnavailableReason === ENUM_USAGE_BILLING_FORBIDDEN) {
          this.setBillingForbidden();
        } else if (data?.gitlabCreditsAvailable !== true) {
          this.setOutOfCredits();
        } else {
          this.isBillingForbidden = false;
          this.hasCredits = true;
          if (!this.isSelectedThreadInactive) {
            this.setChatState({ isEnabled: true, reason: '' });
          }
        }
      },
      error() {
        if (!this.isBillingForbidden) {
          this.setOutOfCredits();
        }
      },
    },
  },
  data() {
    const currentWorkflowRecord = getSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
    const currentWorkflowDefaultRecord = { workflowId: null };
    const { workflowId } = currentWorkflowRecord.exists
      ? currentWorkflowRecord.value
      : currentWorkflowDefaultRecord;

    const getWorkflowErrorHandlers = {
      [NO_DEFAULT_NAMESPACE_CODE]: 'handleNoDefaultNamespaceError',
      [WORKFLOW_NOT_FOUND_CODE]: 'handleWorkflowNotFound',
    };

    // Only the thread-load path fast-fails on a permission error; validateWorkflowExists
    // (the send-message pre-flight check) keeps the default onError handling instead,
    // since handleNoResourcePermissionsError wipes the transcript.
    const threadLoadErrorHandlers = {
      ...getWorkflowErrorHandlers,
      [NO_RESOURCE_PERMISSIONS]: 'handleNoResourcePermissionsError',
    };

    return {
      threadTitle: null,
      agentConfig: null,
      duoChatGlobalState,
      chatState: { isEnabled: true, reason: '' },
      hasCredits: true,
      isBillingForbidden: false,
      hasTrialOrSubscription: this.trialActive || this.subscriptionActive,
      contextPresets: [],
      availableModels: [],
      modelSelection: null,
      pinnedModel: null,
      subscriptions: [],
      eventHubController: null,
      workflowId: workflowId ? convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, workflowId) : null,
      workflowStatus: null,
      isProcessingToolApproval: false,
      selectedModel: null,
      catalogAgents: [],
      aiCatalogItemVersionId: '',
      foundationalAgents: [],
      selectedFoundationalAgent: null,
      agentOrWorkflowDeletedError: '',
      hasNoDefaultNamespaceError: false,
      isChatAvailable: true,
      isFlowLocked: false,
      // Whether a websocket is attached to this workflow right now. Workhorse holds
      // an exclusive lock on the workflow for the life of the socket, so opening the
      // next one before this clears is rejected; see canSendPrompt.
      isStreamOpen: false,
      // this is required for classic/agentic toggle
      isClassicAvailable: this.chatConfiguration?.defaultProps?.isClassicAvailable ?? false,
      duoChatTitle: s__('DuoAgenticChat|GitLab Duo'),
      isLoading: false,
      isWaitingOnPrompt: false,
      // Render mirror of the queue PromptQueue owns; see canSendPrompt.
      queuedPrompts: [],
      lastProcessedMessageId: null,
      pendingEvent: null,
      isProcessingMessage: false,
      threadLoadError: false,
      isLoadingThread: false,
      // True for the whole of hydrateActiveWorkflow. The cached snapshot is
      // painted before the checkpoint query confirms the thread is still active,
      // so the prompt stays locked until it does.
      isHydratingThread: false,
      threadLoadAbortController: null,
      isSelectedThreadInactive: false,
      hasConnectionError: false,
      getWorkflowErrorHandlers,
      threadLoadErrorHandlers,
      currentWelcomeMessage: null,
      currentPredefinedPrompts: null,
      currentPredefinedPromptTrackingLabels: null,
      // Extra additional_context envelopes supplied by the caller of
      // openDuoChatWithAgent (e.g. form_context). Merged into every
      // startWorkflow request for the session.
      commandAdditionalContext: [],
      // Mirrors the user's orbitSettings.enabled preference. Defaults to
      // false (opt-in) and is synced from OrbitToggle once its GraphQL query
      // resolves and whenever the toggle is flipped (which also writes the
      // preference).
      orbitEnabled: false,
      // Per-thread web search preference. This component owns the displayed value:
      // the footer toggle renders it and loadActiveWorkflow restores it from the
      // workflow record, which is what the flow service actually gates on. A thread
      // with no record yet starts from the stored preference (see
      // restoreWebSearchPreference), not from false.
      webSearchEnabled: false,
      // Tracks which alternative is selected for each message (by message ID).
      selectedAlternatives: {},
      // Lazily-fetched duoWorkflowBranches results, keyed by the anchoring user
      // message's thread_ts. Populated on demand from onSelectAlternative.
      branchesByThreadTs: {},
      // ID of the message currently being retried, if any.
      retryingMessageId: null,
      // ID of the message whose most recent retry attempt failed, if any.
      retryFailedMessageId: null,
      namespaceSaveError: '',
      // Attempt number of the retry currently in flight, used to attribute the
      // eventual success/failure outcome back to the retry that triggered it.
      pendingRetryAttempt: null,
      // Ids of the retry attempts the forked run left behind. They stay in the flat
      // message log so the user can still browse them, but they are not part of the
      // conversation the model sees, so context injection must ignore them.
      supersededAttemptIds: new Set(),
    };
  },
  computed: {
    ...mapState(['messages', 'currentAgent']),
    // The ids a plugin needs to scope itself to whatever the chat is pointed at.
    duoChatContext() {
      return {
        resourceId: this.resourceId,
        projectId: this.projectId,
        projectPath: this.projectPath,
        namespaceId: this.namespaceId,
      };
    },
    // Chat state a plugin cannot reach on its own, kept apart from duoChatContext: the
    // slash-command menu watches that object and reloads its commands on every identity
    // change, so state that varies at runtime does not belong in it.
    duoChatState() {
      return {
        canBuyAddon: this.canBuyAddon,
        tierUpgradePath: this.tierUpgradePath,
        isHandRaiseLeadAvailable: this.isHandRaiseLeadAvailable,
      };
    },
    // What every capability is resolved with. Passed whole even to capabilities that
    // read none of it, so there is one shape for plugin authors to learn.
    capabilityDependencies() {
      return {
        apollo: this.$apollo,
        duoChatContext: this.duoChatContext,
        duoChatState: this.duoChatState,
      };
    },
    messageRenderers() {
      return messageWidgets.resolve(
        this.duoChatPluginRegistry.plugins,
        this.capabilityDependencies,
      );
    },
    workflowIid() {
      return this.workflowId ? parseGid(this.workflowId)?.id : null;
    },
    // The conversation the next run replays, which is what decides whether a context
    // item still needs injecting. A retry forks from before the attempt it replaces,
    // so that attempt's context never reaches the model and must not count as sent.
    contextHistoryMessages() {
      return excludeSupersededMessages(this.messages, this.supersededAttemptIds);
    },
    computedTrustedUrls() {
      return computeTrustedUrls(this.trustedUrls);
    },
    // ChatModelSelector owns the model queries, except on the duoUiNext path where it
    // is not rendered and this component keeps querying for the island's model list.
    usesModelSelector() {
      return this.glFeatures.newModelSelection && !this.glFeatures.duoUiNext;
    },
    defaultModel() {
      return this.usesModelSelector
        ? this.modelSelection?.defaultModel
        : getDefaultModel(this.availableModels);
    },
    // The model is needed here for the websocket URL and tracking context. Behind
    // newModelSelection it arrives from ChatModelSelector, which owns the query.
    currentModel: {
      get() {
        if (this.usesModelSelector) {
          return this.modelSelection?.currentModel ?? null;
        }

        return this.$apollo.queries?.availableModels?.loading
          ? null
          : getCurrentModel({
              availableModels: this.availableModels,
              pinnedModel: this.pinnedModel,
              selectedModel: this.selectedModel,
            });
      },
      set(val) {
        this.selectedModel = val;
      },
    },
    isModelSelectionDisabled() {
      return checkModelSelectionDisabled(this.pinnedModel);
    },
    modelSelectionDisabledTooltipText() {
      return this.isModelSelectionDisabled
        ? s__('ModelSelection|Model has been pinned by an administrator.')
        : '';
    },
    predefinedPrompts() {
      return this.currentPredefinedPrompts ?? this.contextPresets.questions ?? [];
    },
    promptTrackingLabels() {
      return this.currentPredefinedPromptTrackingLabels ?? [];
    },
    duoAgenticModePreference: {
      get() {
        return this.duoChatGlobalState.chatMode === 'agentic';
      },
      set(value) {
        setAgenticMode({
          agenticMode: value,
          saveCookie: true,
        });
      },
    },
    agents() {
      return [...this.foundationalAgents, ...this.catalogAgents].map((agent) => ({
        ...agent,
        text: agent.name,
      }));
    },
    // The agent whose identity (name, avatar) the header should reflect. When no agent is
    // explicitly selected, fall back to the default foundational agent so the header shows the
    // same avatar the agent picker highlights by default, instead of a blank/red identicon.
    effectiveAgent() {
      if (this.currentAgent) return this.currentAgent;

      return (
        this.foundationalAgents.find((agent) => agent.id === DEFAULT_AGENT_ID) ||
        this.foundationalAgents[0]
      );
    },
    effectiveAgentId() {
      return this.effectiveAgent?.id;
    },
    effectiveAgentAvatarUrl() {
      return this.effectiveAgent?.avatarUrl;
    },
    websocketUrl() {
      return buildWebsocketUrl({
        rootNamespaceId: this.rootNamespaceId,
        namespaceId: this.namespaceId,
        projectId: this.projectId,
        userModelSelectionEnabled: this.userModelSelectionEnabled,
        currentModel: this.currentModel,
        defaultModel: this.defaultModel,
        workflowDefinition: this.selectedFoundationalAgent?.referenceWithVersion,
        aiCatalogItemVersionId: this.aiCatalogItemVersionId,
        workflowId: this.workflowIid,
      });
    },
    window() {
      return window;
    },
    hasActiveWorkflow() {
      return this.workflowId;
    },
    isNewChatRoute() {
      return this.$route?.name === AGENTIC_CHAT_NEW_ROUTE;
    },
    showErrorBannerMessage() {
      if (this.namespaceSaveError) return this.namespaceSaveError;
      if (this.agentOrWorkflowDeletedError) return this.agentOrWorkflowDeletedError;
      // A failed run never persists its last turn, so the reloaded thread can be
      // missing messages the user already saw. Clears itself when the status
      // changes: a new prompt or thread switch resets workflowStatus.
      if (this.workflowStatus === DUO_WORKFLOW_STATUS_FAILED) {
        return s__(
          "DuoAgenticChat|GitLab Duo couldn't complete this response. Recent messages might be missing or incomplete. Try sending your message again.",
        );
      }
      return '';
    },
    // True when a thread-load overlay (inactive thread, loading retry, or load
    // error) already owns the empty-state slot and other empty states must
    // yield to it.
    hasOverridingEmptyState() {
      return this.isSelectedThreadInactive || this.threadLoadError || this.isLoadingThread;
    },
    showNoNamespaceEmptyState() {
      return (
        !this.chatConfiguration?.defaultProps?.defaultNamespaceSelected ||
        this.hasNoDefaultNamespaceError
      );
    },
    shouldShowActiveTrialOrSubscriptionEmptyState() {
      return this.hasTrialOrSubscription && !this.isSelectedThreadInactive;
    },
    shouldShowFreeAddonExhaustedEmptyState() {
      return this.isFreeAddonCreditsUser && !this.hasCredits && !this.isSelectedThreadInactive;
    },
    shouldShowCustomEmptyState() {
      return (
        this.showNoNamespaceEmptyState ||
        !this.hasCredits ||
        this.shouldShowActiveTrialOrSubscriptionEmptyState ||
        this.hasOverridingEmptyState
      );
    },
    showCreditsExhaustedBanner() {
      return !this.hasCredits && this.messages?.length > 0;
    },
    // Layered over chatState rather than pushed into it via setChatState so that
    // clearing hasConnectionError re-enables the chat on its own, without having
    // to work out which of the other disabled reasons to restore.
    effectiveChatState() {
      if (this.hasConnectionError) {
        return {
          isEnabled: false,
          reason: s__('DuoAgenticChat|Reconnect to continue this conversation.'),
        };
      }
      return this.chatState;
    },
    // Whether the composer can send what the user just submitted: isChatInteractive
    // covers hydration, effectiveChatState covers reconnects, isStreamOpen covers
    // the workflow lock the previous turn still holds. Anything else the composer
    // submits is queued instead.
    canSendPrompt() {
      return (
        !this.isWaitingOnPrompt &&
        !this.isProcessingToolApproval &&
        !this.isStreamOpen &&
        this.isChatInteractive &&
        this.effectiveChatState.isEnabled &&
        !this.isFlowLocked
      );
    },
    // Sending resolves an unanswered tool approval as a denial, which is the user's
    // call to make deliberately. So the composer may send into that state and a
    // prompt queued before it appeared may not.
    canDrainQueue() {
      return (
        this.canSendPrompt &&
        this.workflowStatus !== DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED
      );
    },
    // Gated here rather than through chatState, which renders its reason as a
    // header banner: hydration is transient and has nothing to tell the user.
    isChatInteractive() {
      return this.isChatAvailable && !this.isHydratingThread;
    },
    showAgenticToggle() {
      return (
        this.isClassicAvailable && !this.forceAgenticModeForCoreDuoUsers && !this.isBillingForbidden
      );
    },
    shouldDisplayLoadingIndicator() {
      return this.isLoading && !this.messages?.length && !this.isLoadingThread;
    },
    transformedMessages() {
      // Plugin transformers run after the built-ins, so a plugin sees the log the
      // chat has already normalised rather than having to re-do that work itself.
      // alternativesTransformer must stay last: it needs the fully transformed log
      // to find each turn's terminator.
      return runMessageTransformers(this.messages, [
        ...BUILT_IN_MESSAGE_TRANSFORMERS,
        ...messageTransformers.resolve(
          this.duoChatPluginRegistry.plugins,
          this.capabilityDependencies,
        ),
        alternativesTransformer({ branchesByThreadTs: this.branchesByThreadTs }),
      ]);
    },
    isRetryEnabled() {
      return (
        Boolean(this.glFeatures.agenticManualRetryForDuoChatResponses) &&
        !this.wasCompactedSinceLastPrompt
      );
    },
    // A compaction summarizes away the history a retry would fork from, so retrying the
    // last response would replay against the compacted prompt. A new prompt re-enables it.
    wasCompactedSinceLastPrompt() {
      const messages = this.transformedMessages || [];
      for (let i = messages.length - 1; i >= 0; i -= 1) {
        const message = messages[i];
        if (isCompactionMessage(message)) return true;
        if (
          message.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user &&
          !this.isClarificationAnswerMessage(message)
        ) {
          return false;
        }
      }
      return false;
    },
    // Exposed to DuoChatConversation (via DuoAgenticChatView) as a single map, mirroring
    // the selectedAlternatives pattern. Only one message can be retried at a time, so at
    // most one key is ever present.
    retryStates() {
      if (this.isWaitingOnPrompt && this.retryingMessageId) {
        return { [this.retryingMessageId]: RETRY_STATE.PENDING };
      }
      if (this.retryFailedMessageId) {
        return { [this.retryFailedMessageId]: RETRY_STATE.FAILED };
      }
      return {};
    },
  },
  watch: {
    'duoChatGlobalState.focusChatInput': {
      handler(newVal) {
        if (newVal) {
          this.duoChatGlobalState.focusChatInput = false;
          this.focusInput();
        }
      },
      immediate: true,
    },
    messages: {
      handler: debounce(function handler(newMessages) {
        if (this.workflowId && newMessages?.length) {
          saveThreadSnapshot(this.workflowId, newMessages);
        }
      }, 500),
      deep: true,
    },
    'duoChatGlobalState.commands': {
      handler() {
        if (!this.isLoading) {
          this.processPendingCommands();
        }
      },
    },
    agents() {
      const [pendingCommand] = duoChatGlobalState.commands;
      if (pendingCommand?.agent && !this.isLoading) {
        this.processPendingCommands();
      }
    },
    workflowStatus: {
      immediate: true,
      handler(newStatus, oldStatus) {
        if (!oldStatus && newStatus === DUO_WORKFLOW_STATUS_RUNNING) {
          const lastMessage = this.messages?.[this.messages.length - 1];

          if (isToolApprovalRequest(lastMessage)) {
            this.isProcessingToolApproval = true;
          }
        }

        if (this.isProcessingToolApproval && newStatus !== DUO_WORKFLOW_STATUS_RUNNING) {
          this.isProcessingToolApproval = false;
        }
      },
    },
    currentAgent: 'syncTrackerContext',
    workflowId(newWorkflowId, oldWorkflowId) {
      if (newWorkflowId !== oldWorkflowId) {
        if (newWorkflowId) {
          saveSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY, {
            workflowId: newWorkflowId,
          });
        } else {
          removeSessionStorageValue(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
        }
        this.emitSessionIdChanged();
        this.syncTrackerContext();
      }
    },
    // SHOW and NEW share this component, so clicking "new chat" while viewing a
    // thread reuses the instance and only changes the route. Re-initialize when
    // entering the new-chat route. The show route is reached either on mount
    // (from history) or via onNewChat's own redirect - neither needs re-init.
    '$route.name': function onRouteNameChange(routeName) {
      if (routeName === AGENTIC_CHAT_NEW_ROUTE) {
        this.initializeView();
      }
    },
    selectedAgentError(newError) {
      if (newError) this.onError(newError);
    },
  },
  mounted() {
    // Before any async thread load: loadActiveWorkflow overwrites this with the
    // workflow record when an existing thread is opened, which should win.
    this.restoreWebSearchPreference();

    this.systemContextManager = new SystemContextManager();
    this.systemContextManager.registerProvider(
      new PageContextProvider({ projectPath: this.projectPath }),
    );
    this.systemContextManager.registerProvider(
      new RuleContextProvider(this.$apollo, { projectPath: this.projectPath }),
    );

    this.checkNamespaceAvailability();

    this.eventHubController = initDuoAgenticChatEventHub(workflowStreamFactory.getWorkflowStream());
    this.disposeMessageObservers = initMessageObservers(EventsTracker);
    this.loadDuoNextIfNeeded();
    this.emitSessionIdChanged();
    this.connectToStream();
  },
  beforeDestroy() {
    this.unsubscribeFromStream();

    if (!workflowStreamFactory.getWorkflowStream().getStatus().connected) {
      this.clearActiveWorkflow();
    }

    this.isLoading = false;
    this.isWaitingOnPrompt = false;
    this.threadLoadAbortController?.abort();
    this.disposeMessageObservers?.dispose();
    this.eventHubController?.dispose();
    EventsTracker.reset();
  },
  errorCaptured(err, vm, info) {
    captureExceptionForDuoChat(err, { extra: { info, component: vm?.$options?.name } });
  },
  methods: {
    ...mapActions(['addDuoChatMessage', 'setMessages', 'setCurrentAgent']),
    syncTrackerContext() {
      EventsTracker.updateContext({
        sessionId: this.workflowIid,
        flowType: this.currentAgent?.id,
        model: this.currentModel?.value,
      });
    },
    clearActiveWorkflow() {
      this.setMessages([]);
      this.lastProcessedMessageId = null;
      this.selectedAlternatives = {};
      this.branchesByThreadTs = {};
      this.retryingMessageId = null;
      this.retryFailedMessageId = null;
      this.pendingRetryAttempt = null;
      this.supersededAttemptIds = new Set();
      this.systemContextManager?.resetContextInjectionState();
    },
    async connectToStream() {
      // The route is the single source of truth for the view: initialize it
      // unconditionally, whether or not a reply is already streaming.
      await this.initializeView();

      // Stream adoption is a separate, additive step layered on top of the
      // loaded view - not an alternative to it.
      this.adoptRunningStream();

      this.subscribeToStream();
    },
    adoptRunningStream() {
      if (!workflowStreamFactory.getWorkflowStream().getStatus().connected) {
        return;
      }

      // A reply is already streaming. Anchor the dedup marker to the last loaded
      // message so the live chunks continue the transcript instead of repeating
      // what initializeView just loaded.
      const lastMessage = this.messages?.[this.messages.length - 1];
      if (lastMessage?.message_id) {
        this.lastProcessedMessageId = lastMessage.message_id;
      }
      this.isWaitingOnPrompt = true;
      this.isStreamOpen = true;
    },
    emitSessionIdChanged() {
      if (this.workflowIid) {
        this.$emit('session-id-changed', this.workflowIid);
      }
    },
    async loadDuoNextIfNeeded() {
      if (this.glFeatures.duoUiNext) {
        try {
          await import('fe_islands/duo_next/dist/main');
        } catch (err) {
          logError('Failed to load frontend islands duo_next module', err);
        }
      }
    },
    setChatState(state) {
      if (
        (state.isEnabled === false && typeof state.reason === 'string') ||
        state.isEnabled === true
      ) {
        this.chatState = state;
      } else {
        throw new Error(s__('DuoAgenticChat|Invalid chat state provided'));
      }
    },
    checkNamespaceAvailability() {
      if (!this.chatConfiguration?.defaultProps?.defaultNamespaceSelected) {
        const preferencesUrl = this.chatConfiguration?.defaultProps?.preferencesPath;
        this.setChatState({
          isEnabled: false,
          reason: sprintf(
            s__(
              'DuoAgenticChat|To use Chat, select a default namespace in your %{preferencesLinkStart}user profile preferences%{preferencesLinkEnd}. Alternatively, turn off the %{agenticModeStart}Agentic toggle%{agenticModeEnd} to return to non-agentic Chat.',
            ),
            {
              preferencesLinkStart: `<a href="${preferencesUrl}" class="gl-link" target="_blank" rel="noopener noreferrer">`,
              preferencesLinkEnd: '</a>',
              agenticModeStart: '<strong>',
              agenticModeEnd: '</strong>',
            },
            false,
          ),
        });
      }
    },
    turnOffAgenticMode() {
      setAgenticMode({
        agenticMode: false,
        saveCookie: true,
      });
    },
    // Availability flags in defaultProps are computed server-side, so a full
    // reload is required to pick up the newly saved default namespace.
    onNamespaceSelected() {
      refreshCurrentPage();
    },
    checkCreditsAvailability() {
      this.$apollo.queries.hasCredits.refetch();
    },
    setBillingForbidden() {
      this.isBillingForbidden = true;
      this.hasCredits = false;
      this.setChatState({
        isEnabled: false,
        reason: s__(
          'DuoAgenticChat|Usage billing is not available for this account. To continue using GitLab Duo Agent Platform, contact your administrator.',
        ),
      });
    },
    setOutOfCredits() {
      this.hasCredits = false;
      this.isLoading = false;
      this.isWaitingOnPrompt = false;
      this.isProcessingMessage = false;
      this.setChatState({
        isEnabled: false,
        reason: '',
      });
    },
    async initializeView() {
      // The route is the single source of truth for the view: the new-chat
      // route always starts a blank chat; otherwise (the show route) hydrate the
      // stored thread, falling back to a new chat when there isn't one.
      if (this.isNewChatRoute) {
        await this.onNewChat();
        return;
      }

      if (this.hasActiveWorkflow) {
        await this.hydrateActiveWorkflow();
      } else {
        await this.onNewChat();
      }
    },

    cleanupSocket() {
      workflowStreamFactory.getWorkflowStream().disconnect();
    },

    cleanupState(resetWorkflowId = true) {
      this.isLoading = false;
      this.isWaitingOnPrompt = false;
      // Drop any unresolved retry so a later turn's outcome is not misattributed to it,
      // and so a stale target can't be marked failed by an unrelated later error.
      this.pendingRetryAttempt = null;
      this.retryingMessageId = null;
      this.retryFailedMessageId = null;
      this.lastProcessedMessageId = null;
      this.isProcessingMessage = false;
      this.pendingEvent = null;
      this.threadLoadAbortController?.abort();
      this.threadLoadError = false;
      this.isLoadingThread = false;
      // The worker swallows the close event for a disconnect we asked for, so
      // nothing else will report this socket as gone.
      this.isStreamOpen = false;
      this.cleanupSocket();
      if (resetWorkflowId) {
        this.workflowId = null;
        this.chatState = { isEnabled: true, reason: '' };
        this.isBillingForbidden = false;
        this.hasCredits = true;
        this.restoreWebSearchPreference();
        this.checkNamespaceAvailability();
        this.checkCreditsAvailability();
      }
      this.workflowStatus = null;
      this.isChatAvailable = true;
      this.agentOrWorkflowDeletedError = '';
      this.hasNoDefaultNamespaceError = false;
      this.hasConnectionError = false;
      this.namespaceSaveError = '';
    },

    shouldStartNewChat(question) {
      return [GENIE_CHAT_NEW_MESSAGE, GENIE_CHAT_CLEAR_MESSAGE, GENIE_CHAT_RESET_MESSAGE].includes(
        question,
      );
    },
    onChatCancel() {
      this.$refs.promptQueue.clear();
      this.cleanupState(false);
    },
    onQueueChatPrompt(content) {
      this.$refs.promptQueue.enqueue(content);
    },
    onRemoveQueuedPrompt(id) {
      this.$refs.promptQueue.remove(id);
    },
    subscribeToStream() {
      this.unsubscribeFromStream();
      const stream = workflowStreamFactory.getWorkflowStream();
      this.subscriptions = [
        stream.subscribe('message', this.onMessageReceived),
        stream.subscribe('open', this.onSocketOpen),
        stream.subscribe('close', this.onSocketClose),
        stream.subscribe('error', this.onSocketError),
      ];
    },
    unsubscribeFromStream() {
      this.subscriptions.forEach((s) => s.dispose());
      this.subscriptions = [];
    },
    onSocketOpen() {
      this.isStreamOpen = true;
    },
    onSocketClose(event) {
      // Workhorse releases the workflow lock before it sends this frame, so a close
      // is the only signal that the next turn is free to connect.
      this.isStreamOpen = false;
      // Retryable closes never reach here -- the stream retries them and eventually emits
      // `error` -- but non-retryable abnormal ones do (1008, 1013, invalid request), and
      // they end the turn without routing through onError.
      if (event?.code !== WS_CLOSE_NORMAL) {
        this.failPendingRetry();
      }
      if (event?.code === WS_CLOSE_TRY_AGAIN_LATER) {
        // Soft, temporary lock: the flow is running in another tab or location.
        // Keep the input enabled so the user can queue a message that fires once
        // the flow frees up (see the result callback of the workflowStatus query).
        this.isFlowLocked = true;
      }
      if (event?.code === WS_CLOSE_POLICY_VIOLATION) {
        if (event?.reason?.includes(ENUM_USAGE_BILLING_FORBIDDEN)) {
          this.setBillingForbidden();
        } else {
          this.setOutOfCredits();
        }
      }
      // The backend rejected what we sent rather than failing transiently, so neither
      // reconnecting nor pressing retry can succeed. The retry marker set below reads as
      // "try again", so the thread has to say that this message will not go through.
      if (event?.code === WS_CLOSE_INVALID_REQUEST) {
        const error = new Error(
          s__(
            'DuoAgenticChat|Could not process the last message. Send a new message to try again.',
          ),
        );
        captureExceptionForDuoChat(error, { extra: event });
        this.addDuoChatMessage({ errors: [error.message] });
      }
      // A retry's socket can be dropped by the server (e.g. workflow service unreachable)
      // without ever emitting a distinct 'error' event, so this must be checked on close too.
      if (this.retryingMessageId && event?.code !== WS_CLOSE_NORMAL) {
        this.retryFailedMessageId = this.retryingMessageId;
        this.retryingMessageId = null;
        this.isWaitingOnPrompt = false;
        return;
      }
      if (this.workflowStatus !== DUO_WORKFLOW_STATUS_RUNNING) {
        this.isProcessingToolApproval = false;
        this.isWaitingOnPrompt = false;
      }
    },
    onSocketError(event) {
      this.isStreamOpen = false;
      // Exhausted reconnects end the turn just as any other socket error does, so the
      // retry is resolved before the early return rather than left dangling.
      this.failPendingRetry();
      if (event?.reason === 'max_retries_exceeded') {
        this.hasConnectionError = true;
        // Unconditional, unlike onSocketClose: a running workflow keeps its
        // spinner there because events are still arriving, and here they are not.
        this.isProcessingToolApproval = false;
        this.isWaitingOnPrompt = false;
        return;
      }
      this.onError(
        new Error(s__('DuoAgenticChat|Unable to connect to workflow service. Please try again.')),
        event,
      );
    },
    handleRetryConnection() {
      this.hasConnectionError = false;
      this.isWaitingOnPrompt = true;
      workflowStreamFactory.getWorkflowStream().retry();
    },
    startWorkflow({
      userPrompt = EMPTY_USER_PROMPT,
      approval = {},
      additionalContext,
      resumeCheckpointTs = null,
    } = {}) {
      this.cleanupSocket();
      // Every start opens a new connection, which resets the stream's retry
      // budget, so a "Connection lost" alert from the previous one is stale.
      this.hasConnectionError = false;

      safeRouterPush(
        this.$router,
        { name: AGENTIC_CHAT_SHOW_ROUTE },
        { component: 'DuoAgenticChat' },
      );

      // Command-scoped context (e.g. form_context from openDuoChatWithAgent) is applied to every
      // request for the current session and takes precedence over per-message context with the
      // same category. It is set when a command starts the session and cleared by onNewChat().
      const commandContextCategories = new Set(
        this.commandAdditionalContext.map((c) => c.category),
      );
      const baseContext = [
        ...this.commandAdditionalContext,
        ...(additionalContext || []).filter((c) => !commandContextCategories.has(c.category)),
      ];

      const externalContextItems = getExternalContextItems();
      const externalCategories = new Set(externalContextItems.map((item) => item.category));

      // A prompt with no text but with attachments is still a user turn, unlike an
      // approval resume, which carries neither.
      const isUserTurn = Boolean(userPrompt.text || userPrompt.attachments?.length);

      const mergedAdditionalContext =
        this.selectedFoundationalAgent && isUserTurn
          ? [
              {
                category: 'orbit_context',
                content: JSON.stringify({ orbit_enabled: this.orbitEnabled }),
                metadata: '{}',
              },
              ...externalContextItems,
              ...baseContext.filter(
                (c) => c.category !== 'orbit_context' && !externalCategories.has(c.category),
              ),
            ]
          : baseContext;

      const newAgenticChatConfig =
        this.getNewAgenticChatConfig() ?? this.selectedFoundationalAgent?.flowConfig ?? null;

      const startRequest = buildStartRequest({
        workflowId: this.workflowIid,
        workflowDefinition: this.selectedFoundationalAgent?.referenceWithVersion,
        userPrompt,
        approval,
        additionalContext: mergedAdditionalContext,
        agentConfig: this.agentConfig,
        flowConfig: newAgenticChatConfig,
        metadata: this.metadata,
        clientCapabilities: DUO_AGENTIC_CHAT_CLIENT_CAPABILITIES,
        orbitEnabled: this.orbitEnabled,
        resumeCheckpointTs,
      });

      workflowStreamFactory.getWorkflowStream().connect(this.websocketUrl, startRequest);
      this.subscribeToStream();
    },

    getNewAgenticChatConfig() {
      // If the current active workflow was created as the new chat flow,
      // keep using it regardless of `agentic_chat_flow_registry_migration` FF state
      // because the LangGraph's checkpoint schema is not compatible.
      if (
        this.selectedFoundationalAgent?.referenceWithVersion === DUO_WORKFLOW_NEW_CHAT_DEFINITION
      ) {
        return NEW_AGENTIC_CHAT_FLOW_CONFIG;
      }

      // If `agentic_chat_flow_registry_migration` FF is enabled, use the new agentic chat flow
      // when no agent is explicitly selected.
      if (
        this.glFeatures.agenticChatFlowRegistryMigration &&
        !this.agentConfig &&
        !this.selectedFoundationalAgent
      ) {
        return NEW_AGENTIC_CHAT_FLOW_CONFIG;
      }

      return null;
    },

    async onMessageReceived(event) {
      // Store the latest event
      this.pendingEvent = event;

      // If already processing, return - the event is stored and will be processed
      if (this.isProcessingMessage) {
        return;
      }

      // Start the processing loop
      await this.processMessages();
    },

    async processMessages() {
      // If there's no pending event, exit
      if (this.pendingEvent === null) {
        this.isProcessingMessage = false;
        return;
      }

      this.isProcessingMessage = true;

      try {
        const eventToProcess = this.pendingEvent;
        this.pendingEvent = null; // Clear before processing

        const workflowData = processWorkflowMessage(eventToProcess, this.lastProcessedMessageId);

        if (workflowData) {
          this.lastProcessedMessageId = workflowData.lastProcessedMessageId;

          if (workflowData.messages && workflowData.messages.length > 0) {
            workflowData.messages.forEach((msg) => {
              this.addDuoChatMessage(msg);
            });
          }

          this.workflowStatus = workflowData.status;

          if (this.workflowStatus === DUO_WORKFLOW_STATUS_INPUT_REQUIRED) {
            this.isWaitingOnPrompt = false;
          }

          this.resolvePendingRetry(this.workflowStatus);
        }

        // Check if another event arrived while we were processing
        // If so, process it recursively
        if (this.pendingEvent !== null) {
          await this.processMessages();
        }
      } catch (err) {
        this.failPendingRetry();
        this.onError(err);
      } finally {
        this.isProcessingMessage = false;
      }
    },

    async onSendChatPrompt({
      prompt,
      question,
      triggerSource = TRIGGER_SOURCE_WEB_CHAT,
      resumeCheckpointTs = null,
      isRetry = false,
      fromQueue = false,
    } = {}) {
      // Callers outside the composer -- predefined prompts, chat commands, retries,
      // clarification answers -- still hand over plain text.
      const userPrompt = prompt ?? createUserPrompt({ text: question });

      EventsTracker.updateContext({ triggerSource });

      if (this.shouldShowActiveTrialOrSubscriptionEmptyState) {
        this.trackEvent(TRACKING_EVENT_SUBMIT_MESSAGE, { label: this.isTrial ? 'trial' : 'paid' });
      }

      if (this.shouldStartNewChat(userPrompt.text)) {
        // A reset means start clean, so the shared new-chat draft goes too; the thread
        // the `/new` was typed in clears itself through the composer. Not hooked in
        // onNewChat, which also runs on ordinary init and would wipe every draft.
        removeDraft({ userId: this.userId });
        // Prompts sit behind a base command the queue drained, so they belong to the
        // chat it starts. One the user typed abandons them along with the thread.
        this.onNewChat(true, { keepQueue: fromQueue });
        return;
      }

      if (maybeDoBarrelRoll(userPrompt.text)) return;

      // A new goal on a dropped connection makes the backend replay everything the
      // client missed before starting it, which lands the replay under the new
      // message. Reconnecting first is the only ordered way through, so the prompt
      // is disabled too; this covers the callers that bypass it.
      if (this.hasConnectionError) return;

      if (!isRetry) {
        // A non-retry turn supersedes any retry that never resolved (e.g. it was
        // cancelled or ended without INPUT_REQUIRED); drop it to avoid misattribution.
        this.pendingRetryAttempt = null;
      }

      if (!this.isWaitingOnPrompt) {
        this.isWaitingOnPrompt = true;
      }

      // Attachments carry no `extras` here. The flow service echoes a payload-free
      // reference envelope back on the turn's UiChatLog, so the token arrives with
      // every other included reference rather than being pinned on the pending
      // message, where the shallow ADD_MESSAGE merge would drop it on round-trip.
      this.addDuoChatMessage({
        content: userPrompt.text,
        role: 'user',
        requestId: DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
        // Tells the alternatives transformer this resent prompt is another attempt at
        // the previous turn, not the user re-asking the same question verbatim.
        ...(isRetry && { is_retry: true }),
      });

      if (!this.workflowId) {
        try {
          const { workflowId } = await ApolloUtils.createWorkflow(this.$apollo, {
            projectId: this.projectId,
            namespaceId: this.namespaceId,
            goal: userPrompt.text,
            workflowDefinition: this.selectedFoundationalAgent?.referenceWithVersion,
            aiCatalogItemVersionId: this.aiCatalogItemVersionId,
            agenticChatFlowRegistryMigration: this.glFeatures.agenticChatFlowRegistryMigration,
            webSearchEnabled: this.webSearchEnabled,
          });

          this.workflowId = workflowId;

          if (this.glFeatures.duoChatRedesign) {
            // The new thread is titled by its goal; reflect it in the panel
            // header right away instead of holding "New chat" until the
            // thread is reopened.
            this.threadTitle = userPrompt.text;
          }
        } catch (err) {
          this.failPendingRetry();
          this.onError(err);
          this.isWaitingOnPrompt = false;
          return;
        }
      } else {
        await this.validateWorkflowExists();
      }

      // The manager memoizes what it has already injected and only reconsiders that
      // when the page path changes, so a same-page retry would otherwise inherit the
      // discarded attempt's bookkeeping. Force a recompute over the surviving branch.
      if (isRetry) {
        this.systemContextManager.resetContextInjectionState();
      }

      const contextData = await this.systemContextManager.getSystemContextItems(
        this.contextHistoryMessages,
        this.projectPath,
      );

      // The flow service reads web_search_enabled off the workflow record when the
      // turn starts (ai-assist!6397), so a preference flipped moments before this
      // send has to be committed before we open the socket.
      await this.pendingWebSearchWrite;

      this.startWorkflow({
        userPrompt,
        additionalContext: [
          ...contextData,
          ...slashCommandContextFor(userPrompt),
          ...buildAttachmentContext(userPrompt.attachments),
        ],
        resumeCheckpointTs,
      });

      // Track the event
      if (this.selectedFoundationalAgent || this.aiCatalogItemVersionId) {
        const isFoundational = Boolean(this.selectedFoundationalAgent);
        const idToTrack = isFoundational
          ? this.selectedFoundationalAgent.id
          : this.aiCatalogItemVersionId;
        const parsedId = parseGid(idToTrack).id;

        const { item, version } = isFoundational
          ? foundationalAgentToItemAndVersion(this.selectedFoundationalAgent)
          : this.customAgentItemAndVersion();

        this.trackEvent(CHAT_TRACKING_EVENT, {
          label: isFoundational ? 'foundational_agent' : 'agent',
          property: 'chat',
          value: isFoundational ? null : parseInt(parsedId, 10), // extract number from custom agent id
          foundational_item_ref: isFoundational ? parsedId : null, // extract name from foundational agent id
          ...(item?.itemType ? buildAiCatalogEventProperties(item, { version }) : {}),
        });
      }
    },
    customAgentItemAndVersion() {
      const matchesVersion = (agent) => agent?.pinnedItemVersionId === this.aiCatalogItemVersionId;

      const agent = matchesVersion(this.currentAgent)
        ? this.currentAgent
        : this.catalogAgents.find(matchesVersion);

      if (!agent) {
        return { item: null, version: null };
      }

      return { item: agent, version: agent.pinnedItemVersion };
    },
    async onQuestionAnswered(event) {
      const question = JSON.stringify({
        message_sub_type: MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER,
        selected_option: event.optionId,
        message_id: event.messageId,
      });
      await this.onSendChatPrompt({ question });
    },

    // Only honoured while the capability is actually granted, so a preference kept
    // from an allowing group is not silently sent to createWorkflow under a group
    // that forbids web search.
    restoreWebSearchPreference() {
      this.webSearchEnabled =
        isWebSearchAvailable(this.glFeatures, this.webSearchAllowedForGroup) &&
        loadWebSearchPreference();
    },

    onWebSearchToggled(webSearchEnabled) {
      const previousWebSearchEnabled = this.webSearchEnabled;
      const { workflowId } = this;

      this.webSearchEnabled = webSearchEnabled;
      saveWebSearchPreference(webSearchEnabled);

      if (!workflowId) return;

      // Serialize the writes so rapid toggling is persisted in click order, and
      // expose the tail promise so onSendChatPrompt can wait for it: the record is
      // what the flow service reads, so the turn must not outrun the write.
      this.pendingWebSearchWrite = Promise.resolve(this.pendingWebSearchWrite).then(() =>
        this.persistWebSearchEnabled({ workflowId, webSearchEnabled, previousWebSearchEnabled }),
      );
    },

    async persistWebSearchEnabled({ workflowId, webSearchEnabled, previousWebSearchEnabled }) {
      try {
        await withCaptureErrors(() =>
          ApolloUtils.updateWebSearch(this.$apollo, { workflowId, webSearchEnabled }),
        )();
      } catch {
        // Restore what the user saw before this click rather than `!webSearchEnabled`,
        // which can be a state they never selected. A thread switch mid-flight makes
        // `webSearchEnabled` describe the new thread, so leave it alone in that case.
        if (this.workflowId === workflowId) {
          this.webSearchEnabled = previousWebSearchEnabled;
          saveWebSearchPreference(previousWebSearchEnabled);
        }
        // Deliberately not onError(): a preference write is not part of the
        // conversation, and an error bubble there would be persisted into the
        // thread snapshot. The toggle snapping back is the user-facing signal.
      }
    },

    onError(err, extra) {
      if (extra) {
        captureExceptionForDuoChat(err, { extra });
      } else {
        captureExceptionForDuoChat(err);
      }
      if (this.retryingMessageId) {
        this.retryFailedMessageId = this.retryingMessageId;
        this.retryingMessageId = null;
        this.isWaitingOnPrompt = false;
        return;
      }

      this.addDuoChatMessage({ errors: [formatErrorMessage(err)] });
    },
    // Called only from errors in the conversation turn itself; `onError` is shared
    // with background queries whose failures must not be attributed to the retry.
    failPendingRetry() {
      if (this.pendingRetryAttempt === null) return;
      EventsTracker.trackRetryFailed({ attemptNumber: this.pendingRetryAttempt });
      this.pendingRetryAttempt = null;
    },
    // Only a settled checkpoint decides the retry: FAILED/STOPPED arrive as streamed
    // statuses rather than thrown errors, so processMessages' catch never sees them.
    // Any other status leaves the retry pending until the turn does settle.
    resolvePendingRetry(status) {
      if (this.pendingRetryAttempt === null) return;

      if (status === DUO_WORKFLOW_STATUS_INPUT_REQUIRED) {
        EventsTracker.trackRetrySucceeded({ attemptNumber: this.pendingRetryAttempt });
        this.pendingRetryAttempt = null;
      } else if ([DUO_WORKFLOW_STATUS_FAILED, DUO_WORKFLOW_STATUS_STOPPED].includes(status)) {
        this.failPendingRetry();
      }
    },
    handleApproveToolCall() {
      const lastMessage = this.messages?.[this.messages.length - 1];
      EventsTracker.trackApproveTool({ toolName: lastMessage?.tool_info?.name });
      this.isProcessingToolApproval = true;
      this.startWorkflow({ approval: { approval: {} }, additionalContext: [] });
    },
    handleDenyToolCall(event) {
      const lastMessage = this.messages?.[this.messages.length - 1];
      EventsTracker.trackDenyTool({ toolName: lastMessage?.tool_info?.name });
      this.isProcessingToolApproval = true;
      const message = event?.message || event;
      this.startWorkflow({
        approval: {
          approval: undefined,
          rejection: { message },
        },
        additionalContext: [],
      });
    },
    async hydrateActiveWorkflow() {
      this.threadLoadError = false;
      this.isLoadingThread = false;
      this.isLoading = true;
      this.isHydratingThread = true;

      // Snapshot the id so concurrent cleanupState() resets don't make us
      // clear the wrong cache key after our awaits.
      const id = this.workflowId;

      try {
        if (!id) return;

        const snapshot = loadThreadSnapshot(id);
        if (snapshot?.messages?.length) {
          this.setMessages(snapshot.messages);
        }

        const [loaded] = await Promise.all([
          this.loadActiveWorkflow(id),
          this.$apollo.queries.hasCredits.refetch(),
        ]);

        // A handled load error (deleted workflow, permission denied, etc.) already set its
        // own terminal state; validating the agent or reconnecting here would clobber it.
        if (!loaded) return;

        this.validateAgentExists();

        if (
          this.workflowStatus === DUO_WORKFLOW_STATUS_RUNNING &&
          !workflowStreamFactory.getWorkflowStream().getStatus().connected
        ) {
          this.startWorkflow();
        }
      } finally {
        if (this.aiCatalogItemVersionId) {
          const activeAgent = this.catalogAgents.find(
            (agent) => agent.pinnedItemVersionId === this.aiCatalogItemVersionId,
          );
          this.setCurrentAgent(activeAgent);
        } else if (this.selectedFoundationalAgent) {
          this.setCurrentAgent(this.selectedFoundationalAgent);
        } else {
          // Default Duo chat: clear any previously selected agent so OrbitToggle
          // doesn't leak the prior agent's subsetting key.
          this.setCurrentAgent(null);
        }
        this.isLoading = false;
        this.isHydratingThread = false;
        this.processPendingCommands();
      }
    },
    async loadActiveWorkflow(workflowId = this.workflowId) {
      this.threadLoadAbortController?.abort();
      this.threadLoadAbortController = new AbortController();

      let workflow;
      let workflowStatus;
      let workflowGoal;
      let messages;

      try {
        ({ workflow, workflowStatus, workflowGoal, messages } = await loadActiveWorkflowWithRetry(
          this.$apollo,
          workflowId,
          {
            signal: this.threadLoadAbortController.signal,
            onRetry: () => {
              // Clear any optimistic snapshot messages so the loading empty state is
              // shown instead of a conversation we could not confirm is complete or current.
              this.isLoadingThread = true;
              this.setMessages([]);
            },
          },
        ));
      } catch (err) {
        // The active workflow may have changed while a request was in flight
        // (e.g. the user selected another thread during a retry); ignore stale errors.
        if (isThreadLoadAborted(err) || workflowId !== this.workflowId) return false;

        const handled = await this.routeWorkflowError(err, this.threadLoadErrorHandlers);
        this.isLoadingThread = false;
        if (handled) return false;

        this.setMessages([]);
        this.threadLoadError = true;
        captureExceptionForDuoChat(err);
        return false;
      }

      // Ignore stale results for the same reason as stale errors above.
      if (workflowId !== this.workflowId) return false;

      this.isLoadingThread = false;

      // The checkpoint query returns nodes by id, so an empty result means the
      // workflow no longer exists; treat it the same as a not-found error
      // (handleWorkflowNotFound clears the snapshot itself).
      if (!workflow) {
        await this.handleWorkflowNotFound();
        return false;
      }

      // archived/stalled come from the same single-workflow checkpoint query, so
      // the inactivity check lives here rather than fetching the whole workflow list.
      if (workflow.archived || workflow.stalled) {
        clearThreadSnapshot(workflowId);
        this.setMessages([]);
        this.isSelectedThreadInactive = true;
        this.setChatState({
          isEnabled: false,
          reason: DUO_WORKFLOW_INACTIVE_CHAT_REASON,
        });
        return false;
      }

      this.workflowStatus = workflowStatus;
      this.aiCatalogItemVersionId = workflow?.aiCatalogItemVersionId;
      this.webSearchEnabled = workflow?.webSearchEnabled ?? false;

      // Open a new thread if the `agentic_chat_flow_registry_migration` feature flag is disabled and
      // user sees the new chat flow thread. So that we can quickly roll back to the previous stable version.
      if (
        workflow?.workflowDefinition === DUO_WORKFLOW_NEW_CHAT_DEFINITION &&
        !this.glFeatures.agenticChatFlowRegistryMigration
      ) {
        this.onNewChat();
        return false;
      }

      this.selectedFoundationalAgent = workflow?.workflowDefinition
        ? this.foundationalAgents.find(
            (agent) => agent.referenceWithVersion === workflow.workflowDefinition,
          )
        : null;

      const reconciledMessages = reconcileAndReportLoadedMessages({
        loaded: messages,
        pending: this.messages,
        workflowStatus,
        workflowId,
      });
      this.lastProcessedMessageId = reconciledMessages.at(-1)?.message_id;
      // The checkpoint only carries the surviving branch, so nothing in the reloaded
      // log is superseded any more.
      this.supersededAttemptIds = new Set();
      this.setMessages(reconciledMessages);
      this.threadTitle = workflowGoal;
      this.syncTrackerContext();
      return true;
    },
    retryThreadLoad() {
      this.hydrateActiveWorkflow();
    },
    processPendingCommands() {
      const [firstCommand] = duoChatGlobalState.commands;
      if (!firstCommand) return;

      if (
        firstCommand.agent &&
        (this.$apollo.queries.foundationalAgents.loading ||
          this.$apollo.queries.catalogAgents.loading)
      ) {
        return; // agents watcher will re-trigger once resolved
      }

      this.selectAgentFromCommand(firstCommand);
      this.onNewChat();
      this.commandAdditionalContext = firstCommand.additionalContext ?? [];
      if (firstCommand.autoSend === false) {
        this.currentWelcomeMessage = firstCommand.welcomeMessage ?? null;
        this.currentPredefinedPrompts = firstCommand.predefinedPrompts ?? null;
        this.currentPredefinedPromptTrackingLabels =
          firstCommand.predefinedPromptTrackingLabels ?? null;
      } else {
        this.onSendChatPrompt({
          question: firstCommand.question,
          triggerSource: TRIGGER_SOURCE_WEB_UI,
        });
      }
    },
    onBackToList() {
      // Navigating to the history route unmounts this component; the history
      // view owns the thread list from there.
      this.isSelectedThreadInactive = false;
      this.clearActiveWorkflow();

      if (this.$route?.name !== AGENTIC_CHAT_HISTORY_ROUTE) {
        safeRouterPush(
          this.$router,
          { name: AGENTIC_CHAT_HISTORY_ROUTE },
          { component: 'DuoAgenticChat' },
        ).catch(() => {});
      }
    },
    async onNewChat(selectedAgent, { keepQueue = false } = {}) {
      this.isSelectedThreadInactive = false;
      clearDuoChatCommands();
      this.clearActiveWorkflow();

      this.cleanupState();
      this.isChatAvailable = true;
      this.agentOrWorkflowDeletedError = '';
      this.hasNoDefaultNamespaceError = false;
      this.currentWelcomeMessage = null;
      this.currentPredefinedPrompts = null;
      this.currentPredefinedPromptTrackingLabels = null;
      this.commandAdditionalContext = [];
      this.threadTitle = null;

      const isReuseAgent = selectedAgent === true;
      const agent = isReuseAgent || !selectedAgent ? this.currentAgent : selectedAgent;

      // Leaving a thread in place abandons its queue; PromptQueue only works that
      // out for itself across a remount. A kept queue goes unowned here, since
      // cleanupState() has already nulled workflowId, and re-claims the new id.
      if (!keepQueue) {
        this.$refs.promptQueue.clear();
      }

      if (!isReuseAgent && selectedAgent) {
        this.setCurrentAgent(agent);
      }

      const agentState = prepareAgentSelection(agent, isReuseAgent);
      if (agentState) {
        Object.assign(this, agentState);
      }

      if (this.$route?.name !== AGENTIC_CHAT_SHOW_ROUTE) {
        safeRouterPush(
          this.$router,
          { name: AGENTIC_CHAT_SHOW_ROUTE },
          { component: 'DuoAgenticChatApp' },
        ).catch(() => {});
      }

      // Resetting `selectedFoundationalAgent` to let functions choose an appropriate workflow
      // based on the `agentic_chat_flow_registry_migration` feature flag.
      if (
        this.selectedFoundationalAgent?.referenceWithVersion === DUO_WORKFLOW_CHAT_DEFINITION ||
        this.selectedFoundationalAgent?.referenceWithVersion === DUO_WORKFLOW_NEW_CHAT_DEFINITION
      ) {
        this.selectedFoundationalAgent = null;
      }
    },
    onModelSelect(selectedModelValue) {
      const model = getModel(this.availableModels, selectedModelValue);

      if (model) {
        this.currentModel = model;
        EventsTracker.updateContext({ model: model.value });
        saveModel(model);
      }
    },
    onModelSelectionChange(modelSelection) {
      this.modelSelection = modelSelection;
      EventsTracker.updateContext({ model: modelSelection.currentModel?.value });
    },
    validateAgentExists() {
      const { isAvailable, errorMessage } = validateAgent(
        this.aiCatalogItemVersionId,
        this.catalogAgents,
      );

      this.isChatAvailable = isAvailable;
      this.agentOrWorkflowDeletedError = errorMessage;

      return isAvailable;
    },
    // `focusInput` can be called by the parent component. Ideally, we would mark this as a public
    // method via Vue's `expose` option. However, doing so would cause several tests to fail in Vue 3
    // because we wrote some assertions directly against the `vm`, which becomes private when `expose`
    // is defined. So we need to _not_ use `expose` and disable vue/no-unused-properties for now.
    async focusInput() {
      const el = this.$refs.chat;
      if (el?.focusChatInput) {
        await this.$nextTick();
        el.focusChatInput();
      }
    },
    openFilePicker() {
      this.$refs.chat?.openFilePicker();
    },
    handleNoDefaultNamespaceError() {
      this.hasNoDefaultNamespaceError = true;
      return true;
    },
    // A permission error can never be resolved by retrying, so skip straight
    // to the error state instead of burning through the retry attempts.
    handleNoResourcePermissionsError() {
      this.isLoadingThread = false;
      this.setMessages([]);
      this.threadLoadError = true;
      return true;
    },
    async handleWorkflowNotFound() {
      if (this.workflowId) {
        clearThreadSnapshot(this.workflowId);
      }
      // Messages can come from an active session or a restored snapshot on the first
      // hydration attempt; either way a deleted workflow is never transient, so fail fast.
      if (this.messages.length > 0) {
        this.isChatAvailable = false;
        this.agentOrWorkflowDeletedError = s__('DuoAgenticChat|This chat was deleted.');
        return true;
      }
      await this.$nextTick();
      this.onNewChat();
      return true;
    },
    async routeWorkflowError(errorData, handlers = this.getWorkflowErrorHandlers) {
      const errorCode = Object.keys(handlers).find((code) => hasGraphQLErrorCode(errorData, code));

      if (!errorCode) return false;

      return this[handlers[errorCode]]();
    },
    async validateWorkflowExists() {
      if (!this.workflowId) {
        return false;
      }

      try {
        await ApolloUtils.fetchWorkflowEvents(this.$apollo, this.workflowId);
        return true;
      } catch (errorData) {
        const handled = await this.routeWorkflowError(errorData);
        if (!handled) {
          this.failPendingRetry();
          this.onError(errorData);
        }
        return false;
      }
    },
    trackBinaryFeedbackEvent(event) {
      this.trackEvent(FEEDBACK_TRACKING_EVENT, {
        label: event.feedbackType,
        value: this.workflowIid ? Number(this.workflowIid) : undefined,
        property: event.feedbackReason,
      });
    },
    selectAgentFromCommand(command) {
      if (!command?.agent) {
        return;
      }

      const { agent } = command;
      const foundAgent = this.agents.find((a) => {
        if (agent.id) return a?.id === agent.id;
        if (agent.name) return a?.name === agent.name;
        return false;
      });

      if (foundAgent) {
        this.setCurrentAgent(foundAgent);
      }
    },
    isClarificationAnswerMessage(message) {
      if (typeof message?.content !== 'string') return false;
      try {
        return (
          JSON.parse(message.content)?.message_sub_type === MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER
        );
      } catch {
        return false;
      }
    },
    async onRetryMessage({ id } = {}) {
      if (!this.isRetryEnabled || !id || this.isWaitingOnPrompt) return;

      const messages = this.transformedMessages || [];
      const failedIndex = messages.findIndex((m) => m.id === id);
      if (failedIndex <= 0) return;

      const targetMessage = messages[failedIndex];
      if (targetMessage.role?.toLowerCase() !== GENIE_CHAT_MODEL_ROLES.assistant) return;

      let promptMessage = null;
      for (let i = failedIndex - 1; i >= 0; i -= 1) {
        const msg = messages[i];
        if (msg.role?.toLowerCase() !== GENIE_CHAT_MODEL_ROLES.user) continue;
        if (this.isClarificationAnswerMessage(msg)) continue;
        promptMessage = msg;
        break;
      }
      if (!promptMessage?.content) return;

      this.retryingMessageId = id;
      this.retryFailedMessageId = null;
      this.pendingRetryAttempt = (targetMessage.alternatives?.length || 0) + 1;
      EventsTracker.trackRetryMessage({ attemptNumber: this.pendingRetryAttempt });
      this.supersededAttemptIds = new Set([
        ...this.supersededAttemptIds,
        ...collectSupersededAttemptIds(this.messages, promptMessage),
      ]);

      await this.onSendChatPrompt({
        question: promptMessage.content,
        triggerSource: TRIGGER_SOURCE_WEB_CHAT,
        resumeCheckpointTs: await this.resolveRetryCheckpointTs(promptMessage),
        isRetry: true,
      });
    },
    /**
     * Resolve the checkpoint the retry forks from: the parent of the checkpoint that
     * introduced the resubmitted user message. Messages streamed over the websocket
     * carry no checkpoint metadata, so fall back to re-reading the session until the
     * service sends it inline (https://gitlab.com/gitlab-org/gitlab/-/issues/593008).
     * A null result means the run appends to the latest checkpoint, as it does today.
     */
    async resolveRetryCheckpointTs({ parent_ts: parentTs, message_id: messageId }) {
      if (parentTs) return parentTs;
      if (!messageId || !this.workflowId) return null;

      try {
        const data = await ApolloUtils.fetchWorkflowEvents(this.$apollo, this.workflowId);
        const duoMessages = WorkflowUtils.parseWorkflowData(data)?.duoMessages ?? [];

        return WorkflowUtils.findParentTs(
          WorkflowUtils.normalizeDuoMessages(duoMessages),
          messageId,
        );
      } catch {
        return null;
      }
    },
    /**
     * Handle selection of an alternative response variant.
     * Updates the selectedAlternatives map to track which variant is displayed.
     * Lazily fetches the branch content for a historical (pre-session) alternative
     * the first time it is selected; alternatives from retries made in the current
     * session are already fully loaded, so no fetch is needed for those.
     * @param {Object} payload - { messageId: string, index: number }
     */
    async onSelectAlternative({ messageId, index }) {
      // No navigation while a retry is in flight: switching what is displayed
      // mid-retry is disorienting, and fetching branches now would cache a
      // result that already includes the branch the retry is still creating.
      if (this.isWaitingOnPrompt && this.retryingMessageId) return;

      const nextIndex = Number(index);
      if (!Number.isInteger(nextIndex)) return;
      // Index 0 (canonical response) is the implicit default, so treat it as no-op too.
      if ((this.selectedAlternatives[messageId] ?? 0) === nextIndex) return;

      if (nextIndex > 0) {
        const terminator = this.transformedMessages.find((m) => m.id === messageId);
        const target = terminator?.alternatives?.[nextIndex - 1];

        if (target && target.user_message === null && terminator.alternativesThreadTs) {
          await this.ensureBranchesLoaded(terminator.alternativesThreadTs);
        }
      }

      EventsTracker.trackNavigateRetryAlternative({ index: nextIndex });
      this.selectedAlternatives = { ...this.selectedAlternatives, [messageId]: nextIndex };
    },
    // Fetches and caches the alternative branches anchored at `threadTs` (a user
    // message's thread_ts) so `transformedMessages` can replace the placeholder
    // alternatives it shows before this resolves.
    async ensureBranchesLoaded(threadTs) {
      if (this.branchesByThreadTs[threadTs]) return;

      try {
        const branches = await ApolloUtils.fetchWorkflowBranches(
          this.$apollo,
          this.workflowId,
          threadTs,
        );
        this.branchesByThreadTs = { ...this.branchesByThreadTs, [threadTs]: branches };
      } catch (err) {
        captureExceptionForDuoChat(err);
      }
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-min-h-0 gl-grow gl-flex-col" data-testid="duo-agentic-chat">
    <prompt-queue
      ref="promptQueue"
      :can-send="canDrainQueue"
      :workflow-id="workflowId"
      @change="queuedPrompts = $event"
      @send="onSendChatPrompt({ prompt: $event, fromQueue: true })"
    />
    <div v-if="glFeatures.duoUiNext" class="gl-border-l gl-absolute gl-bg-default">
      <!--
        In order to correctly pass data down to the <next-chat> Custom Element, follow the following principle:
        - as an **attribute** for primitives (string/number)
        - as a **DOM property with a `.prop` modifier** for complex data structures like objects/arrays/functions/etc
      -->
      <fe-island-duo-next
        :avatar-url="window.gon ? window.gon.current_user_avatar_url : null"
        :user-name="window.gon ? window.gon.current_user_fullname : null"
        :models.prop="availableModels"
        @change-model="({ detail: models }) => window.alert(models[0])"
      />
    </div>
    <chat-loading-state v-else-if="shouldDisplayLoadingIndicator" />
    <duo-agentic-chat-view
      v-else
      id="duo-chat"
      ref="chat"
      :user-id="userId"
      :thread-id="workflowIid"
      :chat-state="effectiveChatState"
      :title="currentAgent ? currentAgent.name : duoChatTitle"
      :agent-id="effectiveAgentId"
      :agent-avatar-url="effectiveAgentAvatarUrl"
      :messages="transformedMessages"
      :duo-chat-context="duoChatContext"
      :is-loading="isWaitingOnPrompt"
      :predefined-prompts="predefinedPrompts"
      :predefined-prompt-tracking-labels="promptTrackingLabels"
      :tracking-agent-name="currentAgent ? currentAgent.name : ''"
      :empty-state-title="currentWelcomeMessage"
      :enable-code-insertion="false"
      :with-feedback="glFeatures.duoChatBinaryFeedback"
      :show-header="!glFeatures.duoChatRedesign"
      :message-renderers="messageRenderers"
      :is-saas="isSaas"
      :is-tool-approval-processing="isProcessingToolApproval"
      :is-chat-available="isChatInteractive"
      :is-flow-locked="isFlowLocked"
      :can-send-prompt="canSendPrompt"
      :error="showErrorBannerMessage"
      :trusted-urls="computedTrustedUrls"
      :is-binary-feedback-enabled="glFeatures.duoChatBinaryFeedback"
      :is-retry-enabled="isRetryEnabled"
      :selected-alternatives="selectedAlternatives"
      :retry-states="retryStates"
      :queued-prompts="queuedPrompts"
      class="gl-h-full gl-w-full"
      @send-chat-prompt="onSendChatPrompt({ prompt: $event })"
      @queue-chat-prompt="onQueueChatPrompt"
      @remove-queued-prompt="onRemoveQueuedPrompt"
      @chat-cancel="onChatCancel"
      @approve-tool="handleApproveToolCall"
      @deny-tool="handleDenyToolCall"
      @track-feedback="trackBinaryFeedbackEvent"
      @question-answered="onQuestionAnswered"
      @retry-message="onRetryMessage"
      @select-alternative="onSelectAlternative"
    >
      <template v-if="!glFeatures.duoChatRedesign" #subheader>
        <orbit-toggle v-model="orbitEnabled" :current-agent="currentAgent" />
        <slot name="header"></slot>
      </template>
      <template v-if="!glFeatures.newModelSelection" #agentic-model>
        <div
          v-if="userModelSelectionEnabled && hasCredits"
          v-gl-tooltip
          :title="modelSelectionDisabledTooltipText"
          data-testid="model-dropdown-container"
        >
          <model-select-dropdown
            class="-gl-my-3 -gl-ml-3"
            button-class="!gl-border-0 gl-bg-transparent !gl-px-3 !gl-text-subtle"
            :disabled="isModelSelectionDisabled || isSelectedThreadInactive"
            :is-loading="$apollo.queries.availableModels.loading"
            :items="availableModels"
            :selected-option="currentModel"
            :placeholder-dropdown-text="s__('ModelSelection|Select a model')"
            @select="onModelSelect"
          />
        </div>
      </template>
      <!-- The raw log goes in, not `transformedMessages`: the compact plugin drops the
      prompt that tells TurnProgress what this turn is doing. -->
      <template #turn-progress>
        <turn-progress :is-loading="isWaitingOnPrompt" :messages="messages" />
      </template>
      <!-- `dispatchAction` comes from the prompt composer's slot scope. Called
           optionally because the toolbar also renders where that scope is empty. -->
      <template #textarea-toolbar="slotProps">
        <prompt-input-actions
          class="gl-mr-auto"
          :web-search-enabled="webSearchEnabled"
          :disabled="!isChatAvailable || !chatState.isEnabled"
          :goal-available="Boolean(slotProps?.goalAvailable)"
          @update:web-search-enabled="onWebSearchToggled"
          @attach-files="openFilePicker"
          @dispatch-action="(...args) => slotProps?.dispatchAction?.(...args)"
        />
        <template v-if="glFeatures.newModelSelection">
          <chat-model-selector
            v-if="userModelSelectionEnabled && hasCredits"
            class="gl-mr-2"
            :project-id="projectId"
            :namespace-id="namespaceId"
            :root-namespace-id="rootNamespaceId"
            :disabled="isSelectedThreadInactive"
            :show-classic-chat-button="showAgenticToggle"
            :agentic-mode-enabled="duoAgenticModePreference"
            @change="onModelSelectionChange"
            @switch-to-classic="duoAgenticModePreference = false"
            @error="onError"
          />
          <gl-button
            v-else-if="showAgenticToggle"
            category="tertiary"
            class="gl-mr-2"
            :disabled="isSelectedThreadInactive"
            data-testid="use-classic-chat-button"
            @click="duoAgenticModePreference = false"
          >
            {{ s__('DuoChat|Use Non-Agentic Chat') }}
          </gl-button>
        </template>
      </template>
      <template v-if="showAgenticToggle && !glFeatures.newModelSelection" #agentic-switch>
        <agentic-mode-toggle
          v-model="duoAgenticModePreference"
          :disabled="isSelectedThreadInactive"
        />
      </template>
      <template #before-footer>
        <transition name="fade">
          <connection-error-alert
            v-if="hasConnectionError"
            class="gl-mx-4 gl-mb-3"
            @retry="handleRetryConnection"
          />
          <credits-exhausted-alert
            v-else-if="showCreditsExhaustedBanner"
            class="gl-mx-4 gl-mb-3"
            :is-trial="isTrial"
            :is-free-addon-credits-user="isFreeAddonCreditsUser"
            :has-agentic-toggle="showAgenticToggle"
            :purchase-credits-path="purchaseCreditsPath"
            :can-buy-addon="canBuyAddon"
          />
        </transition>
      </template>
      <template v-if="shouldShowCustomEmptyState" #custom-empty-state>
        <thread-inactive-empty-state
          v-if="isSelectedThreadInactive"
          key="thread-inactive-empty-state"
          @back-to-list="onBackToList"
          @new-chat="onNewChat"
        />
        <thread-loading-empty-state v-else-if="isLoadingThread" key="thread-loading-empty-state" />
        <thread-load-error-empty-state
          v-else-if="threadLoadError"
          key="thread-load-error-empty-state"
          @retry-thread-load="retryThreadLoad"
          @new-chat="onNewChat"
        />
        <no-namespace-empty-state
          v-else-if="showNoNamespaceEmptyState"
          key="no-namespace-empty-state"
          :is-classic-available="isClassicAvailable"
          @return-to-classic="turnOffAgenticMode"
          @namespace-selected="onNamespaceSelected"
          @save-error="namespaceSaveError = $event"
        />
        <no-billing-forbidden-empty-state
          v-else-if="isBillingForbidden"
          key="no-billing-forbidden-empty-state"
        />
        <free-addon-exhausted-empty-state
          v-else-if="shouldShowFreeAddonExhaustedEmptyState"
          key="free-addon-exhausted-empty-state"
          :purchase-credits-path="purchaseCreditsPath"
          :can-buy-addon="canBuyAddon"
        />
        <no-credits-empty-state
          v-else-if="!hasCredits"
          key="no-credits-empty-state"
          :is-trial="isTrial"
          :has-agentic-toggle="showAgenticToggle"
          :purchase-credits-path="purchaseCreditsPath"
          :can-buy-addon="canBuyAddon"
        />
        <active-trial-or-subscription-empty-state
          v-else-if="shouldShowActiveTrialOrSubscriptionEmptyState"
          key="has-trial-or-subscription"
          :agents="agents"
          :predefined-prompts="predefinedPrompts"
          :explore-ai-catalog-path="exploreAiCatalogPath"
          @new-chat="onNewChat"
          @send-chat-prompt="onSendChatPrompt({ question: $event })"
        />
      </template>
    </duo-agentic-chat-view>
    <duo-agentic-chat-header
      v-model="orbitEnabled"
      :single-header="glFeatures.duoChatRedesign"
      :thread-title="threadTitle"
      :current-agent="currentAgent"
      @change-title="$emit('change-title', $event)"
      @change-subtitle="$emit('change-subtitle', $event)"
    >
      <template v-if="glSlots().header" #default><slot name="header"></slot></template>
    </duo-agentic-chat-header>
  </div>
</template>
