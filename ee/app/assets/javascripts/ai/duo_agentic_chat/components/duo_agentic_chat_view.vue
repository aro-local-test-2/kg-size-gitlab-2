<script>
import {
  DuoChatPredefinedPrompts,
  DuoChatContextConversation as DuoChatConversation,
} from '@gitlab/duo-ui';
import { DUO_CHAT_VIEWS } from 'ee/ai/constants';
import { CHAT_RESET_MESSAGE } from 'ee/ai/tanuki_bot/constants';
import { s__, sprintf } from '~/locale';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { InternalEvents } from '~/tracking';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED,
  TRACKING_EVENT_SELECT_PREDEFINED_PROMPT,
} from '../constants';
import DuoChatAlerts from './duo_chat_alerts.vue';
import DuoChatHeader from './duo_chat_header.vue';
import DuoChatScrollRegion from './duo_chat_scroll_region.vue';
import SessionPillsBar from './session_pills/session_pills_bar.vue';
import PromptComposer from './prompt_composer/prompt_composer.vue';
import QueuedPromptMessage from './queued_prompt_message.vue';

export const i18n = {
  CHAT_DEFAULT_TITLE: s__('DuoAgenticChat|GitLab Duo Agentic Chat'),
  CHAT_DISCLAIMER: s__('DuoAgenticChat|Responses may be inaccurate. Verify before use.'),
  CHAT_EMPTY_STATE_EMOJI: '👋',
  CHAT_EMPTY_STATE_TITLE: s__(
    'DuoAgenticChat|I am GitLab Duo Agentic Chat, your personal AI-powered assistant.',
  ),
  CHAT_EMPTY_STATE_DESCRIPTION: s__('DuoAgenticChat|How can I help you today?'),
  CHAT_PROMPT_PLACEHOLDER_DEFAULT: s__("DuoAgenticChat|Let's work through this together..."),
  CHAT_MODEL_PLACEHOLDER: s__('DuoAgenticChat|GitLab Duo Agentic Chat'),
  CHAT_PROMPT_PLACEHOLDER_WITH_COMMANDS: s__('DuoAgenticChat|Type /help to learn more'),
  CHAT_SUBMIT_LABEL: s__('DuoAgenticChat|Send chat message.'),
  CHAT_CANCEL_LABEL: s__('DuoAgenticChat|Cancel'),
  CHAT_FLOW_LOCKED: s__(
    'DuoAgenticChat|GitLab Duo is responding to this chat in another tab or location. Messages you send will be queued and delivered once it finishes.',
  ),
  CHAT_DEFAULT_PREDEFINED_PROMPTS: [
    s__('DuoAgenticChat|How do I change my password in GitLab?'),
    s__('DuoAgenticChat|How do I fork a project?'),
    s__('DuoAgenticChat|How do I clone a repository?'),
    s__('DuoAgenticChat|How do I create a template?'),
  ],
};

const isMessage = (item) => Boolean(item) && item?.role;

const itemsValidator = (items) => items.every(isMessage);

export default {
  name: 'DuoAgenticChatView',
  components: {
    DuoChatPredefinedPrompts,
    DuoChatConversation,
    DuoChatAlerts,
    DuoChatHeader,
    DuoChatScrollRegion,
    SessionPillsBar,
    PromptComposer,
    QueuedPromptMessage,
  },
  mixins: [glSlotsMixin, InternalEvents.mixin(), glFeatureFlagsMixin()],
  provide() {
    return {
      markdownClass: 'md',
    };
  },
  props: {
    /**
     * The name of the agent to display in the empty state.
     */
    agentName: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * The title of the chat/feature.
     */
    title: {
      type: String,
      required: false,
      default: i18n.CHAT_DEFAULT_TITLE,
    },
    /**
     * The GraphQL global id of the active agent, used to derive a stable avatar color.
     */
    agentId: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * The avatar image URL of the active agent (if any).
     */
    agentAvatarUrl: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * Array of messages to display in the chat.
     */
    messages: {
      type: Array,
      required: false,
      default: () => [],
      validator: itemsValidator,
    },
    /**
     * A non-recoverable error message to display in the chat.
     */
    error: {
      type: String,
      required: false,
      default: '',
    },
    /**
     * Chat state object that contains enablement state and optional reason message.
     * When chat is disabled (isEnabled: false), a reason message must be provided.
     */
    chatState: {
      type: Object,
      required: false,
      default: () => ({ isEnabled: true, reason: null }),
      validator: (value) => {
        // If chat is disabled, reason must be provided
        if (!value.isEnabled && !value.reason) {
          return false;
        }
        return true;
      },
    },
    /**
     * Whether the chat is currently fetching a response from AI.
     */
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Whether the conversational interfaces should be enabled.
     */
    isChatAvailable: {
      type: Boolean,
      required: false,
      default: true,
    },
    /**
     * Whether the flow is locked because it is running in another tab or location.
     * A soft, temporary lock: the input stays enabled and submissions are queued.
     */
    isFlowLocked: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Whether the chat can take a prompt right now. When false the composer
     * queues what the user submits instead of sending it.
     */
    canSendPrompt: {
      type: Boolean,
      required: false,
      default: true,
    },
    /**
     * Whether the insertCode feature should be available.
     */
    enableCodeInsertion: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Array of predefined prompts to display in the chat to start a conversation.
     */
    predefinedPrompts: {
      type: Array,
      required: false,
      default: () => i18n.CHAT_DEFAULT_PREDEFINED_PROMPTS,
    },
    /**
     * Tracking labels for predefinedPrompts, aligned by index. Lets callers
     * report a prompt's config template instead of its displayed text, which
     * may have customer data (for example a namespace path) interpolated in.
     */
    predefinedPromptTrackingLabels: {
      type: Array,
      required: false,
      default: () => [],
    },
    /**
     * Untranslated agent name reported as the tracking property for prompt
     * clicks. The title prop falls back to a localized string, which would
     * fragment the analytics dimension by locale.
     */
    trackingAgentName: {
      type: String,
      required: false,
      default: '',
    },
    /**
     * Whether the chat's own header should be displayed. When false only the
     * info/error alerts render: the redesigned panel header already shows the
     * title, so a second one here would duplicate it.
     */
    showHeader: {
      type: Boolean,
      required: false,
      default: true,
    },
    /**
     * Override the default empty state title text.
     */
    emptyStateTitle: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * Override the default chat prompt placeholder text.
     */
    chatPromptPlaceholder: {
      type: String,
      required: false,
      default: '',
    },
    /**
     * Whether the chat should show the feedback link on the assistant messages.
     */
    withFeedback: {
      type: Boolean,
      required: false,
      default: true,
    },
    /**
     * Whether the tool call is currently being processed.
     */
    isToolApprovalProcessing: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Optional parameter to pass in the working directory - needed for MessageMap Tool type
     */
    workingDirectory: {
      type: String,
      required: false,
      default: '',
    },
    /**
     * Array of trusted hostnames (e.g., ['gitlab.com', 'example.com'])
     * that are allowed to render as clickable links in markdown content.
     * Links to other domains will not be clickable.
     */
    trustedUrls: {
      type: Array,
      required: false,
      default: () => [],
      validator: (urls) => urls.every((url) => typeof url === 'string'),
    },
    /**
     * The current user's ID, used to scope draft storage keys.
     */
    userId: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * The active thread's ID, used to scope draft storage keys.
     */
    threadId: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * Whether to show agentic binary feedback (thumbs up/down) instead of the full feedback modal.
     */
    isBinaryFeedbackEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Whether the manual retry action on assistant messages is enabled. Forwarded
     * to DuoChatConversation which gates the retry button on the latest assistant
     * message. Gated by the `agentic_manual_retry_for_duo_chat_responses` flag.
     */
    isRetryEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Prompts submitted during an active turn, awaiting their turn to fire.
     * Each entry is `{ id, prompt }`, where `prompt` is a `UserPrompt`.
     */
    queuedPrompts: {
      type: Array,
      required: false,
      default: () => [],
    },
    /**
     * Map of messageId to selected alternative index.
     * Used to track which alternative is currently displayed for each message.
     */
    selectedAlternatives: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    /**
     * Map of messageId to retry state: 'pending' while a retry is in flight,
     * 'failed' when the most recent retry attempt for that message failed.
     */
    retryStates: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    /**
     * Optional array of custom message renderers passed through to MessageMap.
     * Each entry is an object with `component` (Vue component) and `matchMessage` (Function).
     */
    isSaas: {
      type: Boolean,
      required: false,
      default: false,
    },
    messageRenderers: {
      type: Array,
      required: false,
      default() {
        return [];
      },
      validator: (renderers) =>
        renderers.every(
          (r) =>
            r !== null &&
            typeof r === 'object' &&
            typeof r.component === 'object' &&
            typeof r.matchMessage === 'function',
        ),
    },
    duoChatContext: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: [
    'approve-tool',
    'chat-cancel',
    'copy-code-snippet',
    'copy-message',
    'deny-tool',
    'get-context-item-content',
    'insert-code-snippet',
    'open-file-path',
    'queue-chat-prompt',
    'remove-queued-prompt',
    'retry-message',
    'select-alternative',
    'send-chat-prompt',
    'track-feedback',
    'question-answered',
  ],
  computed: {
    hasMessages() {
      return this.messages?.length > 0;
    },
    hasAssistantMessages() {
      return this.messages?.some((msg) => msg.role?.toLowerCase() === 'assistant');
    },
    headerInfo() {
      if (this.isFlowLocked) return this.$options.i18n.CHAT_FLOW_LOCKED;
      return this.hasMessages ? this.chatState.reason : '';
    },
    conversations() {
      if (!this.hasMessages) return [];

      return this.messages.reduce(
        (acc, message) => {
          if (message.content === CHAT_RESET_MESSAGE) {
            acc.push([]);
          } else {
            // Rewrite `tier_access_denied` messages to use 'tool' role + 'tool' type so they
            // fall through to MessageMap and render via MessageTierAccessDenied in SaaS.
            acc[acc.length - 1].push(
              this.isSaas && message.message_sub_type === MESSAGE_SUB_TYPE_TIER_ACCESS_DENIED
                ? { ...message, role: 'tool', message_type: 'tool' }
                : message,
            );
          }
          return acc;
        },
        [[]],
      );
    },
    lastMessage() {
      return this.messages?.[this.messages.length - 1];
    },
    messageTransitionName() {
      // An empty name doesn't disable this transition; Vue 2 falls back to the default "v"
      // prefix. The slide-in translateY would offset the position the pin measures, so the
      // `css` binding below is what actually turns the transition off during a pin.
      if (this.glSlots()['custom-empty-state'] || this.glFeatures.duoChatRedesign) {
        return '';
      }
      return 'message';
    },
    historyLayoutClasses() {
      if (this.glSlots()['custom-empty-state'] && !this.hasMessages && !this.isLoading) {
        return 'gl-m-auto';
      }
      if (this.glFeatures.duoChatRedesign) {
        // Top-anchored so each request pins to the top of the window and its
        // response streams in below it.
        return 'gl-pb-4 gl-pt-6';
      }
      return 'gl-mt-auto gl-pb-4 gl-pt-6';
    },
    emptyStateGreeting() {
      return sprintf(s__('DuoAgenticChat|Hello, I am %{agentName}!'), {
        agentName: this.agentName,
      });
    },
    emptyStateMainText() {
      if (this.emptyStateTitle) {
        return this.emptyStateTitle;
      }
      return i18n.CHAT_EMPTY_STATE_TITLE;
    },
    emptyStateSubText() {
      return i18n.CHAT_EMPTY_STATE_DESCRIPTION;
    },
  },
  methods: {
    sendPredefinedPrompt(prompt) {
      const promptIndex = this.predefinedPrompts.indexOf(prompt);

      this.trackEvent(TRACKING_EVENT_SELECT_PREDEFINED_PROMPT, {
        label: this.predefinedPromptTrackingLabels[promptIndex] ?? prompt,
        property: this.trackingAgentName,
      });
      this.$refs.promptComposer?.sendPredefinedPrompt(prompt);
    },
    onPillsBarHeightChange() {
      this.$refs.scrollRegion?.rePinIfAtBottom();
    },
    // `focusChatInput` can be called by the parent component via $refs. Ideally, we would mark this
    // as a public method via Vue's `expose` option. However, doing so would cause several tests to
    // fail in Vue 3 because we wrote some assertions directly against the `vm`, which becomes
    // private when `expose` is defined. So we need to _not_ use `expose` and disable
    // vue/no-unused-properties for now.
    // eslint-disable-next-line vue/no-unused-properties
    focusChatInput() {
      this.$refs.promptComposer?.focusChatInput();
    },
    // `openFilePicker` can be called by the parent component via $refs, for the same
    // `expose`-avoidance reason as `focusChatInput` above.
    // eslint-disable-next-line vue/no-unused-properties
    openFilePicker() {
      this.$refs.promptComposer?.openFilePicker();
    },
    onTrackFeedback(event) {
      /**
       * Notify listeners about the feedback form submission on a response message.
       * @param {*} event An event, containing the feedback choices and the extended feedback text.
       */
      this.$emit('track-feedback', event);
    },
    onInsertCodeSnippet(e) {
      /**
       * Emit insert-code-snippet event that clients can use to interact with a suggested code.
       * @param {*} event An event containing code string in the "detail.code" field.
       */
      this.$emit('insert-code-snippet', e);
    },
    onCopyCodeSnippet(e) {
      /**
       * Emit copy-code-snippet event that clients can use to interact with a suggested code.
       * @param {*} event An event containing code string in the "detail.code" field.
       */
      this.$emit('copy-code-snippet', e);
    },
    onCopyMessage(e) {
      /**
       * Emit copy-message event that clients can use to copy chat message content.
       * @param {*} event An event containing code string in the "detail.message" field.
       */
      this.$emit('copy-message', e);
    },
    onGetContextItemContent(event) {
      /**
       * Emit get-context-item-content event that tells clients to load the full file content for a selected context item.
       * The fully hydrated context item should be updated in the chat message context item.
       * @param {*} event An event containing the message ID and context item to hydrate
       */
      this.$emit('get-context-item-content', event);
    },
    onApproveToolCall() {
      /**
       * Emitted when a user approves a tool call.
       */
      this.$emit('approve-tool');
    },
    onDenyToolCall(reason) {
      /**
       * Emitted when a user denies a tool call.
       * @param {String} reason The reason for denying the tool call.
       */
      this.$emit('deny-tool', reason);
    },
    onOpenFilePath(filePath) {
      /**
       * Emitted when a file path link is clicked in a chat message.
       * @param {String} filePath The file path to open
       */
      this.$emit('open-file-path', filePath);
    },
    onQuestionAnswered($event) {
      this.$emit('question-answered', $event);
    },
  },
  i18n,
  DUO_CHAT_VIEWS,
};
</script>
<template>
  <div
    id="chat-component"
    class="duo-chat web-only gl-bottom-0 gl-flex gl-max-h-full gl-min-h-0 gl-flex-grow gl-flex-col"
    role="complementary"
    data-testid="chat-component"
  >
    <duo-chat-scroll-region
      ref="scrollRegion"
      :last-message="lastMessage"
      :content-class="historyLayoutClasses"
      :transition-name="messageTransitionName"
    >
      <template #header>
        <duo-chat-header
          v-if="showHeader"
          ref="header"
          :title="title"
          :agent-id="agentId"
          :agent-avatar-url="agentAvatarUrl"
          :error="error"
          :info="headerInfo"
          :current-view="$options.DUO_CHAT_VIEWS.CHAT"
        >
          <template v-if="glSlots().subheader" #subheader>
            <slot name="subheader"></slot>
          </template>
        </duo-chat-header>
        <duo-chat-alerts
          v-else
          class="gl-sticky gl-top-0 gl-z-9999 gl-shrink-0 gl-bg-default"
          :info="headerInfo"
          :error="error"
        />
      </template>

      <duo-chat-conversation
        v-for="(conversation, index) in conversations"
        :key="`conversation-${index}`"
        :enable-code-insertion="enableCodeInsertion"
        :messages="conversation"
        :show-delimiter="index > 0"
        :with-feedback="withFeedback"
        :is-tool-approval-processing="isToolApprovalProcessing"
        :working-directory="workingDirectory"
        :trusted-urls="trustedUrls"
        :is-binary-feedback-enabled="isBinaryFeedbackEnabled"
        :is-retry-enabled="isRetryEnabled"
        :message-renderers="messageRenderers"
        :selected-alternatives="selectedAlternatives"
        :retry-states="retryStates"
        @track-feedback="onTrackFeedback"
        @insert-code-snippet="onInsertCodeSnippet"
        @copy-code-snippet="onCopyCodeSnippet"
        @copy-message="onCopyMessage"
        @get-context-item-content="onGetContextItemContent"
        @approve-tool="onApproveToolCall"
        @deny-tool="onDenyToolCall"
        @open-file-path="onOpenFilePath"
        @question-answered="onQuestionAnswered"
        @retry-message="$emit('retry-message', $event)"
        @select-alternative="$emit('select-alternative', $event)"
      />
      <template v-if="!hasMessages && !isLoading">
        <div key="empty-state-container">
          <slot name="custom-empty-state">
            <div
              key="empty-state-message"
              class="duo-chat-message gl-rounded-bl-none gl-leading-20 gl-text-default gl-break-anywhere"
              data-testid="gl-duo-chat-empty-state"
            >
              <div
                class="gl-mb-[3.75rem] gl-flex gl-flex-col gl-items-center gl-justify-center gl-gap-3 gl-text-center"
              >
                <h1 class="gl-my-0 gl-text-[3.5rem]" data-testid="gl-duo-chat-empty-state-emoji">
                  {{ $options.i18n.CHAT_EMPTY_STATE_EMOJI }}
                </h1>
                <h2
                  v-if="agentName"
                  class="gl-heading-2 gl-my-0"
                  data-testid="gl-duo-chat-empty-state-greeting"
                >
                  {{ emptyStateGreeting }}
                </h2>
                <h2 class="gl-my-0 gl-text-size-h2" data-testid="gl-duo-chat-empty-state-title">
                  {{ emptyStateMainText }}
                </h2>
                <p
                  class="gl-text-base gl-text-subtle"
                  data-testid="gl-duo-chat-empty-state-subtitle"
                >
                  {{ emptyStateSubText }}
                </p>
              </div>
              <duo-chat-predefined-prompts
                key="predefined-prompts"
                :prompts="predefinedPrompts"
                @click="sendPredefinedPrompt"
              />
            </div>
          </slot>
        </div>
      </template>
      <!-- Keyed wrapper, not a bare slot: transition-group reads its direct children
        and needs a keyed element for each. Whatever fills this may render nothing, and
        an unkeyed comment node there makes the move check throw on `cloneNode`. -->
      <div v-if="glSlots()['turn-progress']" key="turn-progress" data-testid="turn-progress">
        <slot name="turn-progress"></slot>
      </div>
      <queued-prompt-message
        v-for="item in queuedPrompts"
        :key="`queued-${item.id}`"
        class="gl-mt-5"
        :content="item.prompt.text"
        @remove="$emit('remove-queued-prompt', item.id)"
      />
    </duo-chat-scroll-region>
    <footer
      data-testid="chat-footer"
      class="gl-relative gl-z-2 gl-mx-auto gl-w-full gl-max-w-4xl gl-shrink-0 gl-px-3 gl-pb-3"
    >
      <session-pills-bar
        :messages="messages"
        class="gl-mb-2"
        @height-change="onPillsBarHeightChange"
      />
      <slot name="before-footer"></slot>
      <prompt-composer
        ref="promptComposer"
        :user-id="userId"
        :thread-id="threadId"
        :is-chat-available="isChatAvailable"
        :can-send-prompt="canSendPrompt"
        :chat-state="chatState"
        :should-auto-focus-input="false"
        :is-loading="isLoading"
        :last-message="lastMessage"
        :chat-prompt-placeholder="chatPromptPlaceholder"
        :duo-chat-context="duoChatContext"
        @send-chat-prompt="$emit('send-chat-prompt', $event)"
        @queue-chat-prompt="$emit('queue-chat-prompt', $event)"
        @chat-cancel="$emit('chat-cancel')"
      >
        <template v-if="glSlots()['agentic-model']" #agentic-model>
          <slot name="agentic-model"></slot>
        </template>
        <template v-if="glSlots()['agentic-switch']" #agentic-switch>
          <slot name="agentic-switch"></slot>
        </template>
        <!-- Forwards the composer's slot props, which is how `dispatchAction` reaches
             a control the state manager put in the toolbar. -->
        <template v-if="glSlots()['textarea-toolbar']" #textarea-toolbar="slotProps">
          <slot name="textarea-toolbar" v-bind="slotProps"></slot>
        </template>
      </prompt-composer>
      <p
        class="gl-mb-0 gl-ml-2 gl-mt-3 gl-text-sm gl-text-subtle"
        :class="{ 'gl-hidden': !hasAssistantMessages }"
        data-testid="chat-disclaimer"
      >
        {{ $options.i18n.CHAT_DISCLAIMER }}
      </p>
    </footer>
  </div>
</template>
