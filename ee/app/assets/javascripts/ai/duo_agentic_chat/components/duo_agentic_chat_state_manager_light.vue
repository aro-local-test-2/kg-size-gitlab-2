<script>
// eslint-disable-next-line no-restricted-imports
import { mapActions, mapState } from 'vuex';
import { debounce } from 'lodash-es';
import getFlowStatus from 'ee/ai/graphql/get_flow_status.query.graphql';
import ChatLoadingState from 'ee/ai/components/chat_loading_state.vue';
import getUserWorkflows from 'ee/ai/graphql/get_user_workflow.query.graphql';
import getConfiguredAgents from 'ee/ai/graphql/get_configured_agents.query.graphql';
import getFoundationalChatAgents from 'ee/ai/graphql/get_foundational_chat_agents.graphql';
import getAgentFlowConfig from 'ee/ai/graphql/get_agent_flow_config.query.graphql';
import getGitlabCreditsStatusQuery from 'ee/ai/graphql/get_gitlab_credits_status.query.graphql';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
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
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_CURRENT_WORKFLOW_STORAGE_KEY,
  DUO_CHAT_VIEWS,
  DUO_AGENTIC_CHAT_PENDING_USER_MESSAGE_ID,
  DUO_WORKFLOW_INACTIVE_CHAT_REASON,
  DUO_WORKFLOW_CHAT_DEFINITION,
  DUO_WORKFLOW_NEW_CHAT_DEFINITION,
  NEW_AGENTIC_CHAT_FLOW_CONFIG,
} from 'ee/ai/constants';
import getAiChatContextPresets from 'ee/ai/graphql/get_ai_chat_context_presets.query.graphql';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import { fetchPolicies } from '~/lib/graphql';
import { logError } from '~/lib/logger';
import { s__, sprintf } from '~/locale';
import { formatDefaultModelData } from 'ee/ai/shared/utils/model_selection_utils';
import {
  AGENTIC_CHAT_SHOW_ROUTE,
  AGENTIC_CHAT_HISTORY_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { safeRouterPush } from 'ee/ai/duo_agents_platform/utils/router_utils';
import DuoChatDeleteThreadModal from 'ee/ai/components/duo_chat_delete_thread_modal.vue';
import { buildAiCatalogEventProperties } from 'ee/ai/catalog/event_properties';
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
import { getCurrentModel, getDefaultModel } from '../utils/model_selection_utils';
import {
  buildWebsocketUrl,
  buildStartRequest,
  processWorkflowMessage,
} from '../websocket/workflow_utils';
import {
  validateAgentExists as validateAgent,
  prepareAgentSelection,
  catalogAgentsFromResponse,
  foundationalAgentToItemAndVersion,
} from '../utils/agent_utils';
import { formatErrorMessage } from '../utils/error_handler';
import { buildAttachmentContext } from '../utils/attachment_utils';
import { runMessageTransformers } from '../transformers/index';
import { clarificationQuestionTransformer } from '../transformers/clarification_question_transformer';
import { toolDenialTransformer } from '../transformers/tool_denial_transformer';
import { alternativesTransformer } from '../transformers/alternatives_transformer';
import { isCompactionMessage } from '../plugins/compact/utils';
import {
  WS_CLOSE_POLICY_VIOLATION,
  WS_CLOSE_TRY_AGAIN_LATER,
  WORKFLOW_NOT_FOUND_CODE,
  FEEDBACK_TRACKING_EVENT,
  CHAT_TRACKING_EVENT,
  NO_DEFAULT_NAMESPACE_CODE,
  NO_RESOURCE_PERMISSIONS,
  TRACKING_EVENT_SUBMIT_MESSAGE,
  TRIGGER_SOURCE_WEB_CHAT,
  TRIGGER_SOURCE_WEB_UI,
  MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER,
  MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED,
  DEFAULT_AGENT_ID,
} from '../constants';
import {
  saveThreadSnapshot,
  loadThreadSnapshot,
  clearThreadSnapshot,
} from '../utils/chat_thread_snapshot';
import { loadActiveWorkflowWithRetry, isThreadLoadAborted } from '../services/load_active_workflow';
import { SystemContextManager } from '../context/system_context_manager';
import { PageContextProvider } from '../context/page_context_provider';
import { RuleContextProvider } from '../context/rule_context_provider';
import { isToolApprovalRequest } from '../utils/messages_utils';
import { createUserPrompt, EMPTY_USER_PROMPT } from '../services/user_prompt';
import { getExternalContextItems } from '../context/external_context_store';
import StartFlowToolMessage from '../plugins/start_flow/components/message_tool_start_flow.vue';
import MessageTierAccessDenied from '../plugins/tier_access_denied/components/message_tier_access_denied.vue';
import NoNamespaceEmptyState from './no_namespace_empty_state.vue';
import NoCreditsEmptyState from './no_credits_empty_state.vue';
import CreditsExhaustedAlert from './credits_exhausted_alert.vue';
import NoBillingForbiddenEmptyState from './no_billing_forbidden_empty_state.vue';
import FreeAddonExhaustedEmptyState from './free_addon_exhausted_empty_state.vue';
import DuoAgenticChatView from './duo_agentic_chat_view.vue';
import PromptInputActions from './prompt_input_actions.vue';
import ThreadInactiveEmptyState from './thread_inactive_empty_state.vue';
import ThreadLoadErrorEmptyState from './thread_load_error_empty_state.vue';
import ThreadLoadingEmptyState from './thread_loading_empty_state.vue';

const MESSAGE_TRANSFORMERS = [clarificationQuestionTransformer, toolDenialTransformer];

const hasGraphQLErrorCode = (errorData, code) =>
  errorData?.graphQLErrors?.some((e) => e?.extensions?.code === code);

// A reduced-presentation duplicate of duo_agentic_chat_state_manager.vue (forked at
// e73cc4111602) for page embeds: no chat header, welcome empty state, or prompt controls.
// The fork keeps the panel component conflict-free during its restructure; reconcile after.
export default {
  name: 'DuoAgenticChatStateManagerLight',
  components: {
    DuoAgenticChatView,
    PromptInputActions,
    DuoChatDeleteThreadModal,
    ChatLoadingState,
    NoNamespaceEmptyState,
    NoCreditsEmptyState,
    CreditsExhaustedAlert,
    FreeAddonExhaustedEmptyState,
    NoBillingForbiddenEmptyState,
    ThreadInactiveEmptyState,
    ThreadLoadErrorEmptyState,
    ThreadLoadingEmptyState,
  },
  mixins: [glFeatureFlagsMixin(), InternalEvents.mixin()],
  inject: {
    chatConfiguration: {
      default: () => ({
        title: s__('DuoAgenticChat|GitLab Duo Agentic Chat'),
      }),
    },
  },
  provide() {
    return { renderGFM };
  },
  props: {
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
    mode: {
      type: String,
      required: false,
      default: 'active',
    },
    // Placeholder override for embedding surfaces; empty string falls back
    // to the prompt input's own default copy.
    chatPromptPlaceholder: {
      type: String,
      required: false,
      default: '',
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
  emits: ['change-title', 'session-id-changed', 'switch-to-active-tab'],
  apollo: {
    workflowStatus: {
      query: getFlowStatus,
      pollInterval: 3000,
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
    },
    agenticWorkflows: {
      query: getUserWorkflows,
      variables() {
        return {
          type: 'foundational_chat_agents',
          first: 99999,
          environment: 'WEB',
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.map((edge) => edge.node) || [];
      },
      error(err) {
        this.onError(err);
      },
    },
    contextPresets: {
      query: getAiChatContextPresets,
      variables() {
        return {
          resourceId: this.resourceId,
          projectId: this.projectId,
          url: typeof window !== 'undefined' && window.location ? window.location.href : '',
          questionCount: 4,
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        return data?.aiChatContextPresets || {};
      },
      error(err) {
        this.onError(err);
      },
    },
    availableModels: {
      query: getAiChatAvailableModels,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      skip() {
        if (!this.userModelSelectionEnabled) return true;
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
      agentConfig: null,
      duoChatGlobalState,
      chatState: { isEnabled: true, reason: '' },
      hasCredits: true,
      isBillingForbidden: false,
      hasTrialOrSubscription: this.trialActive || this.subscriptionActive,
      contextPresets: [],
      availableModels: [],
      pinnedModel: null,
      subscriptions: [],
      socketManager: null,
      workflowId: workflowId ? convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, workflowId) : null,
      workflowStatus: null,
      isProcessingToolApproval: false,
      agenticWorkflows: [],
      deleteModalVisible: false,
      pendingDeleteThreadId: null,
      isDeletingThread: false,
      selectedModel: null,
      catalogAgents: [],
      aiCatalogItemVersionId: '',
      foundationalAgents: [],
      selectedFoundationalAgent: null,
      agentOrWorkflowDeletedError: '',
      hasNoDefaultNamespaceError: false,
      isChatAvailable: true,
      isFlowLocked: false,
      // this is required for classic/agentic toggle
      isClassicAvailable: this.chatConfiguration?.defaultProps?.isClassicAvailable ?? false,
      duoChatTitle: s__('DuoAgenticChat|GitLab Duo'),
      isLoading: false,
      isWaitingOnPrompt: false,
      lastProcessedMessageId: null,
      pendingEvent: null,
      isProcessingMessage: false,
      threadLoadError: false,
      isLoadingThread: false,
      threadLoadAbortController: null,
      isSelectedThreadInactive: false,
      getWorkflowErrorHandlers,
      threadLoadErrorHandlers,
      currentWelcomeMessage: null,
      currentPredefinedPrompts: null,
      currentPredefinedPromptTrackingLabels: null,
      // Extra additional_context envelopes supplied by the caller of
      // openDuoChatWithAgent (e.g. form_context). Merged into every
      // startWorkflow request for the session.
      commandAdditionalContext: [],
      // Mirrors the user's orbitSettings.enabled preference. This surface
      // renders no Orbit toggle, so it stays at the opt-in default; kept
      // because the workflow payloads send it.
      orbitEnabled: false,
      // Per-thread web search preference. This component owns the displayed value:
      // the footer toggle renders it and loadActiveWorkflow restores it from the
      // workflow record, which is what the flow service actually gates on.
      webSearchEnabled: false,
      // Tracks which alternative is selected for each message (by message ID).
      selectedAlternatives: {},
      // Lazily-fetched duoWorkflowBranches results, keyed by the anchoring user
      // message's thread_ts. Populated on demand from onSelectAlternative.
      branchesByThreadTs: {},
    };
  },
  computed: {
    ...mapState(['messages', 'currentAgent']),
    // The history route maps to LIST, show/new to CHAT, mirroring ROUTE_TO_TAB.
    multithreadedView() {
      return this.$route?.name === AGENTIC_CHAT_HISTORY_ROUTE
        ? DUO_CHAT_VIEWS.LIST
        : DUO_CHAT_VIEWS.CHAT;
    },
    messageRenderers() {
      return [
        {
          component: StartFlowToolMessage,
          matchMessage: (message) => {
            if (message.message_sub_type !== 'start_flow') return false;
            const content = message.tool_info?.tool_response?.content;
            try {
              const parsed = JSON.parse(content);
              return (
                parsed !== null &&
                typeof parsed === 'object' &&
                'flow_name' in parsed &&
                'status' in parsed &&
                'workflow_id' in parsed
              );
            } catch {
              return false;
            }
          },
        },
        {
          component: MessageTierAccessDenied,
          matchMessage: (message) =>
            message.message_sub_type === MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED,
          // duo-ui replaces the default { message, workingDirectory } props with
          // whatever this returns, so `message` must be forwarded explicitly.
          defaultProps: (message) => ({
            message,
            canBuyAddon: this.canBuyAddon,
            tierUpgradePath: this.tierUpgradePath,
            isHandRaiseLeadAvailable: this.isHandRaiseLeadAvailable,
          }),
        },
      ];
    },
    workflowIid() {
      return this.workflowId ? parseGid(this.workflowId)?.id : null;
    },
    computedTrustedUrls() {
      return computeTrustedUrls(this.trustedUrls);
    },
    defaultModel() {
      return getDefaultModel(this.availableModels);
    },
    currentModel: {
      get() {
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
    isLoadingThreadList() {
      return this.$apollo.queries?.agenticWorkflows?.loading;
    },
    predefinedPrompts() {
      return this.currentPredefinedPrompts ?? this.contextPresets.questions ?? [];
    },
    promptTrackingLabels() {
      return this.currentPredefinedPromptTrackingLabels ?? [];
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
    showErrorBannerMessage() {
      if (this.multithreadedView === DUO_CHAT_VIEWS.CHAT) {
        if (this.agentOrWorkflowDeletedError) {
          return this.agentOrWorkflowDeletedError;
        }
        // A failed run never persists its last turn, so the reloaded thread can be
        // missing messages the user already saw. Clears itself when the status
        // changes: a new prompt or thread switch resets workflowStatus.
        if (this.workflowStatus === DUO_WORKFLOW_STATUS_FAILED) {
          return s__(
            "DuoAgenticChat|GitLab Duo couldn't complete this response. Recent messages might be missing or incomplete. Try sending your message again.",
          );
        }
      }
      return '';
    },
    showNoNamespaceEmptyState() {
      return (
        this.multithreadedView === DUO_CHAT_VIEWS.CHAT &&
        (!this.chatConfiguration?.defaultProps?.defaultNamespaceSelected ||
          this.hasNoDefaultNamespaceError)
      );
    },
    shouldShowActiveTrialOrSubscriptionEmptyState() {
      return this.hasTrialOrSubscription && !this.isSelectedThreadInactive;
    },
    shouldShowFreeAddonExhaustedEmptyState() {
      return this.isFreeAddonCreditsUser && !this.hasCredits && !this.isSelectedThreadInactive;
    },
    showCreditsExhaustedBanner() {
      return !this.hasCredits && this.messages?.length > 0;
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
      // alternativesTransformer must stay last: it needs the fully transformed log
      // to find each turn's terminator.
      return runMessageTransformers(this.messages, [
        ...MESSAGE_TRANSFORMERS,
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

        if (this.isFlowLocked && newStatus) {
          this.isFlowLocked = false;
          this.setChatState({
            isEnabled: true,
          });
          this.hydrateActiveWorkflow();
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
    mode(newMode) {
      this.switchMode(newMode);
    },
    selectedAgentError(newError) {
      if (newError) this.onError(newError);
    },
  },
  mounted() {
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
    this.$emit('change-title');
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
      this.systemContextManager?.resetContextInjectionState();
    },
    connectToStream() {
      if (workflowStreamFactory.getWorkflowStream().getStatus().connected) {
        const lastMessage = this.messages?.[this.messages.length - 1];
        if (lastMessage?.message_id) {
          this.lastProcessedMessageId = lastMessage.message_id;
        }
        this.isWaitingOnPrompt = true;
      } else {
        this.switchMode(this.mode);
      }

      this.subscribeToStream();
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
    switchMode(mode) {
      if (mode === 'active') {
        if (this.isLoading) {
          return;
        }

        if (this.hasActiveWorkflow) {
          this.hydrateActiveWorkflow();
        } else {
          this.onNewChat();
        }
      }
      if (mode === 'new') {
        this.onNewChat();
      }
      if (mode === 'history') {
        this.onBackToList();
        this.$emit('change-title', '');
      }
    },

    cleanupSocket() {
      workflowStreamFactory.getWorkflowStream().disconnect();
    },

    cleanupState(resetWorkflowId = true) {
      this.isLoading = false;
      this.isWaitingOnPrompt = false;
      this.lastProcessedMessageId = null;
      this.isProcessingMessage = false;
      this.pendingEvent = null;
      this.threadLoadAbortController?.abort();
      this.threadLoadError = false;
      this.isLoadingThread = false;
      this.cleanupSocket();
      if (resetWorkflowId) {
        this.workflowId = null;
        this.chatState = { isEnabled: true, reason: '' };
        this.isBillingForbidden = false;
        this.hasCredits = true;
        this.webSearchEnabled = false;
        this.checkNamespaceAvailability();
        this.checkCreditsAvailability();
      }
      this.workflowStatus = null;
      this.isChatAvailable = true;
      this.agentOrWorkflowDeletedError = '';
      this.hasNoDefaultNamespaceError = false;
    },

    shouldStartNewChat(question) {
      return [GENIE_CHAT_NEW_MESSAGE, GENIE_CHAT_CLEAR_MESSAGE, GENIE_CHAT_RESET_MESSAGE].includes(
        question,
      );
    },
    onChatCancel() {
      this.cleanupState(false);
    },
    subscribeToStream() {
      this.unsubscribeFromStream();
      const stream = workflowStreamFactory.getWorkflowStream();
      this.subscriptions = [
        stream.subscribe('message', this.onMessageReceived),
        stream.subscribe('close', this.onSocketClose),
        stream.subscribe('error', this.onSocketError),
      ];
    },
    unsubscribeFromStream() {
      this.subscriptions.forEach((s) => s.dispose());
      this.subscriptions = [];
    },
    onSocketClose(event) {
      if (event?.code === WS_CLOSE_TRY_AGAIN_LATER) {
        this.isFlowLocked = true;
        this.setChatState({
          isEnabled: false,
          reason: s__(
            'DuoAgenticChat|GitLab Duo is already responding to this chat in another tab or location. Start a new chat, or wait for GitLab Duo to finish before sending a new message.',
          ),
        });
      }
      if (event?.code === WS_CLOSE_POLICY_VIOLATION) {
        if (event?.reason?.includes(ENUM_USAGE_BILLING_FORBIDDEN)) {
          this.setBillingForbidden();
        } else {
          this.setOutOfCredits();
        }
      }
      if (this.workflowStatus !== DUO_WORKFLOW_STATUS_RUNNING) {
        this.isProcessingToolApproval = false;
        this.isWaitingOnPrompt = false;
      }
    },
    onSocketError(event) {
      this.onError(
        new Error(s__('DuoAgenticChat|Unable to connect to workflow service. Please try again.')),
        event,
      );
    },
    startWorkflow({
      userPrompt = EMPTY_USER_PROMPT,
      approval = {},
      additionalContext,
      isRetry = false,
      selectedRegenerateMessageId = null,
    } = {}) {
      this.cleanupSocket();

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
        isRetry,
        selectedRegenerateMessageId,
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

        const workflowData = await processWorkflowMessage(
          eventToProcess,
          this.lastProcessedMessageId,
        );

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
        }

        // Check if another event arrived while we were processing
        // If so, process it recursively
        if (this.pendingEvent !== null) {
          await this.processMessages();
        }
      } catch (err) {
        this.onError(err);
      } finally {
        this.isProcessingMessage = false;
      }
    },

    async onSendChatPrompt({
      prompt,
      question,
      triggerSource = TRIGGER_SOURCE_WEB_CHAT,
      isRetry = false,
    } = {}) {
      // Callers outside the composer -- predefined prompts, chat commands, retries,
      // clarification answers -- still hand over plain text.
      const userPrompt = prompt ?? createUserPrompt({ text: question });

      EventsTracker.updateContext({ triggerSource });

      if (this.shouldShowActiveTrialOrSubscriptionEmptyState) {
        this.trackEvent(TRACKING_EVENT_SUBMIT_MESSAGE, { label: this.isTrial ? 'trial' : 'paid' });
      }

      if (this.shouldStartNewChat(userPrompt.text)) {
        this.onNewChat(true);
        return;
      }

      if (maybeDoBarrelRoll(userPrompt.text)) return;

      if (!this.isWaitingOnPrompt) {
        this.isWaitingOnPrompt = true;
      }

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
        } catch (err) {
          this.onError(err);
          this.isWaitingOnPrompt = false;
          return;
        }
      } else {
        await this.validateWorkflowExists();
      }

      const contextData = await this.systemContextManager.getSystemContextItems(
        this.messages,
        this.projectPath,
      );

      // Check if user has selected an alternative that should be promoted to canonical
      const selectedRegenerateMessageId = this.getSelectedRegenerateMessageId();

      // The flow service reads web_search_enabled off the workflow record when the
      // turn starts (ai-assist!6397), so a preference flipped moments before this
      // send has to be committed before we open the socket.
      await this.pendingWebSearchWrite;

      this.startWorkflow({
        userPrompt,
        additionalContext: [...contextData, ...buildAttachmentContext(userPrompt.attachments)],
        isRetry,
        selectedRegenerateMessageId,
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

    onWebSearchToggled(webSearchEnabled) {
      const previousWebSearchEnabled = this.webSearchEnabled;
      const { workflowId } = this;

      this.webSearchEnabled = webSearchEnabled;

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
      this.addDuoChatMessage({ errors: [formatErrorMessage(err)] });
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
    async onThreadSelected(thread) {
      this.isSelectedThreadInactive = false;

      if (thread.archived || thread.stalled) {
        this.isSelectedThreadInactive = true;
        this.workflowId = thread.id;
        // This branch skips cleanupState()/loadActiveWorkflow(), so thread-scoped
        // state has to be reset here or the footer toggle keeps rendering the
        // previously viewed thread's preference.
        this.webSearchEnabled = false;
        if (this.$route?.name !== AGENTIC_CHAT_SHOW_ROUTE) {
          safeRouterPush(
            this.$router,
            { name: AGENTIC_CHAT_SHOW_ROUTE },
            { component: 'DuoAgenticChat' },
          ).catch(() => {});
        }
        this.setChatState({
          isEnabled: false,
          reason: DUO_WORKFLOW_INACTIVE_CHAT_REASON,
        });
        return;
      }

      this.clearActiveWorkflow();
      this.cleanupState();
      this.workflowId = thread.id;

      this.$emit('switch-to-active-tab', DUO_CHAT_VIEWS.CHAT);

      if (this.$route?.name !== AGENTIC_CHAT_SHOW_ROUTE) {
        safeRouterPush(
          this.$router,
          { name: AGENTIC_CHAT_SHOW_ROUTE },
          { component: 'DuoAgenticChat' },
        ).catch(() => {});
      }
    },
    async waitForAgenticWorkflowsReady() {
      const query = this.$apollo.queries?.agenticWorkflows;
      if (!query || !query.loading) return;
      await new Promise((resolve) => {
        const unwatch = this.$watch(
          () => this.$apollo.queries.agenticWorkflows.loading,
          (loading) => {
            if (!loading) {
              unwatch();
              resolve();
            }
          },
          { immediate: true },
        );
      });
    },
    async hydrateActiveWorkflow() {
      this.threadLoadError = false;
      this.isLoadingThread = false;
      this.isLoading = true;

      // Snapshot the id so concurrent cleanupState() / onThreadSelected() resets
      // don't make us clear the wrong cache key after our awaits.
      const id = this.workflowId;

      try {
        if (!id) return;

        await this.waitForAgenticWorkflowsReady();

        const thread = this.agenticWorkflows.find((w) => w.id === id);

        if (!thread) {
          clearThreadSnapshot(id);
          await this.handleWorkflowNotFound();
          return;
        }

        if (thread.archived || thread.stalled) {
          clearThreadSnapshot(id);
          this.isSelectedThreadInactive = true;
          this.setChatState({
            isEnabled: false,
            reason: DUO_WORKFLOW_INACTIVE_CHAT_REASON,
          });
          return;
        }

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
          // Default Duo chat: clear any previously selected agent so the prior
          // agent's subsetting key doesn't leak into the next session.
          this.setCurrentAgent(null);
        }
        this.isLoading = false;
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
      this.setMessages(reconciledMessages);
      this.$emit('change-title', workflowGoal);
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
      this.isSelectedThreadInactive = false;
      this.clearActiveWorkflow();

      if (this.$route?.name !== AGENTIC_CHAT_HISTORY_ROUTE) {
        safeRouterPush(
          this.$router,
          { name: AGENTIC_CHAT_HISTORY_ROUTE },
          { component: 'DuoAgenticChat' },
        ).catch(() => {});
      }

      try {
        if (this.$apollo?.queries?.agenticWorkflows) {
          this.$apollo.queries.agenticWorkflows.refetch();
        }
      } catch (err) {
        this.onError(err);
      }
    },
    onDeleteThread(threadId) {
      // Confirm before deleting; the request runs from onConfirmDeleteThread.
      this.pendingDeleteThreadId = threadId;
      this.deleteModalVisible = true;
    },
    async onConfirmDeleteThread() {
      const threadId = this.pendingDeleteThreadId;
      if (!threadId) {
        return;
      }

      this.isDeletingThread = true;

      try {
        const success = await ApolloUtils.deleteWorkflow(this.$apollo, threadId);
        if (success) {
          // Drop the workflow from the displayed list instead of refetching, which
          // would flash the loading state and refresh the view. The list query is
          // `network-only`, so it isn't driven reactively by the cache - filter the
          // local list directly.
          this.agenticWorkflows = this.agenticWorkflows.filter(
            (workflow) => workflow.id !== threadId,
          );
          clearThreadSnapshot(threadId);
        }
      } catch (err) {
        this.onError(err);
      } finally {
        this.isDeletingThread = false;
        this.deleteModalVisible = false;
        this.pendingDeleteThreadId = null;
      }
    },
    async onNewChat(selectedAgent) {
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
      this.$emit('change-title');

      const isReuseAgent = selectedAgent === true;
      const agent = isReuseAgent || !selectedAgent ? this.currentAgent : selectedAgent;

      if (!isReuseAgent && selectedAgent) {
        this.setCurrentAgent(agent);
      }

      const agentState = prepareAgentSelection(agent, isReuseAgent);
      if (agentState) {
        Object.assign(this, agentState);
      }

      this.$emit('switch-to-active-tab', DUO_CHAT_VIEWS.CHAT);

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

      let prompt = null;
      for (let i = failedIndex - 1; i >= 0; i -= 1) {
        const msg = messages[i];
        if (msg.role?.toLowerCase() !== GENIE_CHAT_MODEL_ROLES.user) continue;
        if (this.isClarificationAnswerMessage(msg)) continue;
        prompt = msg.content;
        break;
      }
      if (!prompt) return;

      await this.onSendChatPrompt({
        question: prompt,
        triggerSource: TRIGGER_SOURCE_WEB_CHAT,
        isRetry: true,
      });
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
      // No navigation while a turn (including a retry) is in flight: switching
      // what is displayed mid-retry is disorienting, and fetching branches now
      // would cache a result that already includes the branch the retry is
      // still creating. This surface tracks no per-message retry state, so the
      // in-flight turn is the closest signal.
      if (this.isWaitingOnPrompt) return;

      const nextIndex = Number(index);

      if (nextIndex > 0) {
        const terminator = this.transformedMessages.find((m) => m.id === messageId);
        const target = terminator?.alternatives?.[nextIndex - 1];

        if (target && target.user_message === null && terminator.alternativesThreadTs) {
          await this.ensureBranchesLoaded(terminator.alternativesThreadTs);
        }
      }

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
    /**
     * Get the message ID to promote as canonical when user has selected an alternative.
     * Returns the last agent response's message_id from the selected alternative,
     * or null if no alternative is selected (index 0 = current/canonical).
     * @returns {string|null} The message ID to send as selectedRegenerateMessageId
     */
    getSelectedRegenerateMessageId() {
      const messages = this.transformedMessages || [];

      // Find messages with alternatives where user has selected a non-zero index
      for (let i = messages.length - 1; i >= 0; i -= 1) {
        const msg = messages[i];
        if (!msg.alternatives?.length) continue;

        const selectedIndex = this.selectedAlternatives[msg.id] ?? 0;
        if (selectedIndex === 0) continue; // 0 = current canonical, no promotion needed

        if (selectedIndex > msg.alternatives.length) continue;

        const alternative = msg.alternatives[selectedIndex - 1];
        if (!alternative?.agent_responses?.length) continue;

        // Return the last agent response's ID (the final message in that alternative attempt)
        const lastResponse = alternative.agent_responses[alternative.agent_responses.length - 1];
        return lastResponse?.message_id || null;
      }

      return null;
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-min-h-0 gl-grow gl-flex-col" data-testid="duo-agentic-chat">
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
      :chat-state="chatState"
      :title="currentAgent ? currentAgent.name : duoChatTitle"
      :agent-id="effectiveAgentId"
      :agent-avatar-url="effectiveAgentAvatarUrl"
      :messages="transformedMessages"
      :is-loading="isWaitingOnPrompt"
      :loading-thread-list="isLoadingThreadList"
      :predefined-prompts="predefinedPrompts"
      :predefined-prompt-tracking-labels="promptTrackingLabels"
      :tracking-agent-name="currentAgent ? currentAgent.name : ''"
      :empty-state-title="currentWelcomeMessage"
      :thread-list="agenticWorkflows"
      :multi-threaded-view="multithreadedView"
      :is-multithreaded="true"
      :enable-code-insertion="false"
      :with-feedback="glFeatures.duoChatBinaryFeedback"
      :message-renderers="messageRenderers"
      :is-saas="isSaas"
      :is-tool-approval-processing="isProcessingToolApproval"
      :is-chat-available="isChatAvailable"
      :show-header="false"
      :chat-prompt-placeholder="chatPromptPlaceholder"
      :error="showErrorBannerMessage"
      :trusted-urls="computedTrustedUrls"
      :is-binary-feedback-enabled="glFeatures.duoChatBinaryFeedback"
      :is-retry-enabled="isRetryEnabled"
      :selected-alternatives="selectedAlternatives"
      class="gl-h-full gl-w-full"
      @new-chat="onNewChat"
      @send-chat-prompt="onSendChatPrompt({ prompt: $event })"
      @chat-cancel="onChatCancel"
      @approve-tool="handleApproveToolCall"
      @deny-tool="handleDenyToolCall"
      @thread-selected="onThreadSelected"
      @back-to-list="onBackToList"
      @delete-thread="onDeleteThread"
      @track-feedback="trackBinaryFeedbackEvent"
      @question-answered="onQuestionAnswered"
      @retry-message="onRetryMessage"
      @select-alternative="onSelectAlternative"
    >
      <template #textarea-toolbar>
        <prompt-input-actions
          class="gl-mr-auto"
          :web-search-enabled="webSearchEnabled"
          :disabled="!isChatAvailable || !chatState.isEnabled"
          @update:web-search-enabled="onWebSearchToggled"
          @attach-files="openFilePicker"
        />
      </template>
      <template #before-footer>
        <transition name="fade">
          <credits-exhausted-alert
            v-if="showCreditsExhaustedBanner"
            class="gl-mx-4 gl-mb-3"
            :is-trial="isTrial"
            :is-free-addon-credits-user="isFreeAddonCreditsUser"
            :has-agentic-toggle="showAgenticToggle"
            :purchase-credits-path="purchaseCreditsPath"
            :can-buy-addon="canBuyAddon"
          />
        </transition>
      </template>
      <template #custom-empty-state>
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
          :preferences-path="chatConfiguration.defaultProps.preferencesPath"
          :is-classic-available="isClassicAvailable"
          @return-to-classic="turnOffAgenticMode"
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
        <!--
          Must be a real element: Vue 2 normalizes a slot that renders only
          comment nodes to undefined, which would fall back to the view's
          built-in welcome empty state. This surface never shows the welcome
          state, so the opt-out is the terminal branch.
        -->
        <div v-else key="empty-state-opt-out" data-testid="duo-chat-empty-state-opt-out"></div>
      </template>
    </duo-agentic-chat-view>
    <duo-chat-delete-thread-modal
      v-model="deleteModalVisible"
      :loading="isDeletingThread"
      @confirm="onConfirmDeleteThread"
    />
  </div>
</template>
