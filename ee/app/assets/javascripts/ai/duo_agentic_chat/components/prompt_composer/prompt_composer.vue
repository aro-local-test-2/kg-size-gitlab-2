<script>
import { GlButton, GlForm } from '@gitlab/ui';
import { s__ } from '~/locale';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { buildDraftStorageKey, createDraftStorage } from 'ee/ai/utils/chat_draft_storage';
import { UserPromptBuilder } from '../../services/user_prompt';
import { PROMPT_COMPOSER_ACTIONS } from '../../constants';
import { slashCommands } from '../../services/plugin_capabilities';
import { DuoChatPluginRegistry } from '../../services/plugin_registry';
import { captureExceptionForDuoChat } from '../../observability/sentry_utils';
import { getGoalFlow } from '../../services/goal_flow';
import GoalToken from './goal_token.vue';
import SlashCommandsMenu from './slash_commands_menu/slash_commands_menu.vue';
import PromptTextarea from './prompt_textarea.vue';
import FileAttachments from './file_attachments.vue';

// Leading boundary so a pasted URL does not trigger a fetch.
const MAYBE_TRIGGERED = /(?:^|\s)\//;

const i18n = {
  CHAT_PROMPT_PLACEHOLDER_DEFAULT: s__("DuoAgenticChat|Let's work through this together..."),
  CHAT_SUBMIT_LABEL: s__('DuoAgenticChat|Send chat message.'),
  CHAT_CANCEL_LABEL: s__('DuoAgenticChat|Cancel'),
  GOAL_PROMPT_PLACEHOLDER: s__(
    'DuoAgenticChat|Define a condition Duo should work until it achieves...',
  ),
};

export default {
  name: 'PromptComposer',
  components: {
    GlButton,
    GlForm,
    GoalToken,
    SlashCommandsMenu,
    PromptTextarea,
    FileAttachments,
  },
  mixins: [glSlotsMixin],
  inject: {
    duoChatPluginRegistry: {
      default: () => new DuoChatPluginRegistry(),
    },
  },
  props: {
    /**
     * The current user's ID, used to scope the draft storage key.
     */
    userId: {
      type: String,
      required: false,
      default: null,
    },
    /**
     * The active thread's ID, used to scope the draft storage key.
     */
    threadId: {
      type: String,
      required: false,
      default: null,
    },
    isChatAvailable: {
      type: Boolean,
      required: false,
      default: true,
    },
    /**
     * Whether the chat can take a prompt right now. Owned by the state manager,
     * which is the only thing that knows about turns this composer did not start.
     */
    canSendPrompt: {
      type: Boolean,
      required: false,
      default: true,
    },
    chatState: {
      type: Object,
      required: false,
      default: () => ({ isEnabled: true, reason: null }),
    },
    shouldAutoFocusInput: {
      type: Boolean,
      required: false,
      default: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    lastMessage: {
      type: Object,
      required: false,
      default: null,
    },
    chatPromptPlaceholder: {
      type: String,
      required: false,
      default: '',
    },
    duoChatContext: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['send-chat-prompt', 'queue-chat-prompt', 'chat-cancel'],
  data() {
    return {
      draft: UserPromptBuilder.empty(),
      // The flow goal mode would run here, or null where it cannot run at all.
      availableGoalFlow: null,
      commands: [],
      isLoadingCommands: false,
      hadFocusBeforeSend: false,
      inputHasFocus: false,
    };
  },
  computed: {
    draftStorageKey() {
      return buildDraftStorageKey({
        userId: this.userId,
        threadId: this.threadId,
      });
    },
    newChatDraftStorageKey() {
      return buildDraftStorageKey({ userId: this.userId });
    },
    isStreaming() {
      return Boolean(
        (this.lastMessage?.chunks?.length > 0 && !this.lastMessage?.content) ||
        typeof this.lastMessage?.chunkId === 'number',
      );
    },
    showSubmitButton() {
      // When idle the submit button always shows. During a turn it only comes
      // back once the user has typed something to queue; an empty input keeps
      // the stop button available to cancel the running turn.
      return !this.isLoading || !this.draft.isTextEmpty;
    },
    isDisabled() {
      return !this.isChatAvailable || !this.chatState.isEnabled;
    },
    hasAttachments() {
      return this.draft.attachments.length > 0;
    },
    /**
     * Whether the draft is worth sending. The single place that decides it, so the
     * submit button and the Enter key cannot drift apart -- they did, and Enter sent
     * whitespace-only and over-length prompts the button refused. An image on its own
     * is a message: `goal` has no presence validation and the flow service appends
     * image blocks independently of the prompt text.
     */
    isDraftSubmittable() {
      return (!this.draft.isTextEmpty || this.hasAttachments) && this.draft.isTextWithinLengthLimit;
    },
    // The toolbar is told whether, not which: this component runs the action, so the
    // row has no use for the flow itself.
    isGoalAvailable() {
      return Boolean(this.availableGoalFlow);
    },
    inputPlaceholder() {
      // Goal mode overrides whatever the parent asked for: the goal token has replaced
      // the command, so the placeholder is the only thing left saying what to write.
      if (this.draft.goalFlow) return i18n.GOAL_PROMPT_PLACEHOLDER;

      return this.chatPromptPlaceholder || i18n.CHAT_PROMPT_PLACEHOLDER_DEFAULT;
    },
  },
  watch: {
    isLoading: 'onResponseComplete',
    isStreaming: 'onResponseComplete',
    duoChatContext() {
      // Commands can be scoped to the project or resource the chat is pointed at, so
      // what we are holding no longer applies.
      this.commands = [];
      this.commandsRequest = null;
      this.loadIfTriggered();
      this.loadGoalAvailability();
    },
    commands(commands) {
      this.draft = this.draft.withCatalogue(commands);
    },
    // Typing a command runs its action, the same one the toolbar dispatches. `INSERT` is
    // excluded because it would insert a second copy of the token just typed.
    'draft.slashCommands': function onRecordedCommands(commands, previous = []) {
      const fresh = commands.find(
        (command) =>
          command.action &&
          command.action !== PROMPT_COMPOSER_ACTIONS.INSERT &&
          !previous.includes(command),
      );

      if (fresh) this.dispatchAction(fresh.action, { command: fresh });
    },
    // Every path that changes the text runs through here -- typing, a spliced slash
    // command, a predefined prompt -- so this is the only place that needs to persist
    // or re-check whether a command was triggered.
    'draft.text': function onDraftText(text) {
      this.saveDraft(text);
      this.loadIfTriggered();
    },
    draftStorageKey(newKey, oldKey) {
      // The only way this composer sees the new-chat bucket turn into a thread key is its
      // own conversation being assigned an id by the first send, because reaching any
      // other thread goes through the history view and unmounts it. So text on screen
      // belongs to the thread now, and restoring the empty thread key would strand it.
      if (this.draft.text && oldKey && oldKey === this.newChatDraftStorageKey) {
        this.draftStorage.carryOver(oldKey, newKey, this.draft.text);
        return;
      }

      this.restoreDraft();
    },
  },
  created() {
    // Not in `data()`: a promise has nothing to render, and the same one is kept once
    // settled so a menu and a send in the same context join one resolution.
    this.commandsRequest = null;
    this.isTornDown = false;
    this.draftStorage = createDraftStorage(() => this.draftStorageKey);
  },
  mounted() {
    // In `mounted`, not `created`: swapping between agentic and classic runs the incoming
    // component's `created` before the outgoing one's `beforeDestroy` flushes its pending
    // draft, so reading that early would miss text typed in the last debounce window.
    this.restoreDraft();
    this.loadGoalAvailability();
  },
  beforeDestroy() {
    this.isTornDown = true;
    this.draftStorage.destroy();
  },
  methods: {
    restoreDraft() {
      // Only the text is stored, so a restore has to leave goal mode rather than let it
      // stand over text it was never turned on for -- which is what switching threads
      // would otherwise do.
      this.draft = this.draft.withoutGoalFlow().withText(this.draftStorage.read());
    },
    saveDraft(text) {
      this.draftStorage.save(text);
    },
    // A method, not a computed: `glSlots()` is not a reactive dependency, so a cached
    // computed would go stale when the state manager starts or stops supplying a slot.
    hasHeaderRow() {
      return Boolean(this.glSlots()['agentic-model'] || this.glSlots()['agentic-switch']);
    },
    // The goal plugin asks the same question to gate its command. The shared query is
    // cache-first, so the pair costs one request.
    async loadGoalAvailability() {
      const context = this.duoChatContext;

      try {
        const goalFlow = await getGoalFlow({
          apollo: this.$apollo,
          projectId: context?.projectId,
        });

        // The context moved on while this was in flight, so this answer is for a chat
        // that is no longer on screen.
        if (context !== this.duoChatContext) return;

        this.availableGoalFlow = goalFlow;
      } catch (error) {
        // A chat panel must not raise an error over an optional flow. The row stays
        // hidden, which is the safe side to fail on.
        captureExceptionForDuoChat(error);
      }
    },
    loadIfTriggered() {
      // Goal mode is on, so the menu cannot open and nothing would read the answer.
      // Checked here as well as on the menu to keep the fetch off the wire.
      if (this.draft.goalFlow) return;

      if (this.commandsRequest || !MAYBE_TRIGGERED.test(this.draft.text)) return;

      this.loadCommands();
    },
    async loadCommands() {
      const context = this.duoChatContext;
      const request = slashCommands.resolve(this.duoChatPluginRegistry.plugins, {
        apollo: this.$apollo,
        duoChatContext: context,
      });

      this.commandsRequest = request;
      this.isLoadingCommands = true;

      try {
        const commands = await request;

        // The context moved on while this was in flight, so these commands are for a
        // chat that is no longer on screen.
        if (context !== this.duoChatContext) return;

        this.commands = commands;
      } catch {
        // `resolve` contains provider failures itself, so this is the unexpected case.
        // Forgotten rather than kept, or the menu would stay empty for the session.
        if (this.commandsRequest === request) this.commandsRequest = null;
      } finally {
        if (context === this.duoChatContext) this.isLoadingCommands = false;
      }
    },
    // A prompt sent before the plugins answer would otherwise carry no command.
    pendingCommands() {
      this.loadIfTriggered();

      return this.isLoadingCommands ? this.commandsRequest.catch(() => {}) : undefined;
    },
    onInput(text) {
      this.draft = this.draft.withText(text);
    },
    async sendChatPrompt() {
      if (!this.isDraftSubmittable) return;

      // A queued prompt is persisted to sessionStorage, which cannot carry base64
      // image payloads, so a draft holding one waits in the composer instead of
      // going in with its images stripped off.
      if (!this.canSendPrompt && this.hasAttachments) {
        this.$refs.fileAttachments?.rejectQueueing?.();
        return;
      }

      // Store this before any async operation that might clear the draft.
      this.hadFocusBeforeSend = this.inputHasFocus;

      if (MAYBE_TRIGGERED.test(this.draft.text)) {
        await this.pendingCommands();

        // Teardown while the catalogue loaded has already persisted this draft. Sending
        // on would emit into a destroyed component, then clear the text nobody received.
        if (this.isTornDown) return;

        this.draft = this.draft.withCatalogue(this.commands);
      }

      // The input stays enabled whenever the chat cannot take a prompt — a turn
      // is running, the flow is locked in another tab, a tool call is waiting on
      // the user — so queue the prompt instead of sending it. It fires once the
      // chat is ready again.
      this.$emit(this.canSendPrompt ? 'send-chat-prompt' : 'queue-chat-prompt', this.draft.build());

      await this.clearAndFocus();
    },
    // The form owns the element these land on, so the listeners have to be bound
    // here; what to do with them is <file-attachments>'s business. `paste` and the
    // drag events all bubble, so binding on the form covers the textarea too.
    onPaste(event) {
      this.$refs.fileAttachments?.onPaste?.(event);
    },
    onDragEnter(event) {
      this.$refs.fileAttachments?.onDragEnter?.(event);
    },
    onDragOver(event) {
      this.$refs.fileAttachments?.onDragOver?.(event);
    },
    onDragLeave(event) {
      this.$refs.fileAttachments?.onDragLeave?.(event);
    },
    onDrop(event) {
      this.$refs.fileAttachments?.onDrop?.(event);
    },
    onAttachmentsAdd(attachments) {
      this.draft = attachments.reduce(
        (draft, attachment) => draft.withAttachment(attachment),
        this.draft,
      );
    },
    onAttachmentRemove(id) {
      this.draft = this.draft.withoutAttachment(id);
    },
    // Called by the parent via $refs, so the "+" menu's attach action can reach the
    // file input this composer owns.
    // eslint-disable-next-line vue/no-unused-properties
    openFilePicker() {
      this.$refs.fileAttachments?.openFilePicker?.();
    },
    cancelPrompt() {
      this.$emit('chat-cancel');
      this.clearAndFocus();
    },
    // `sendPredefinedPrompt` is called by the parent via $refs.
    // eslint-disable-next-line vue/no-unused-properties
    sendPredefinedPrompt(text) {
      this.draft = this.draft.withText(text);
      this.sendChatPrompt();
    },
    focusChatInput() {
      // Optional calls throughout: children are stubbed without their methods in some tests.
      this.$refs.textarea?.focus?.();
    },
    async clearAndFocus() {
      this.draft = this.draft.cleared();
      this.$refs.fileAttachments?.clearErrors?.();
      this.draftStorage.clear();
      await this.$nextTick();
      this.focusChatInput();
    },
    async onResponseComplete() {
      if (this.isLoading || this.isStreaming) return;
      await this.$nextTick();
      this.restoreFocusAfterSend();
    },
    restoreFocusAfterSend() {
      if (!this.hadFocusBeforeSend) return;
      this.hadFocusBeforeSend = false;
      if (this.isDisabled) return;
      this.focusChatInput();
    },
    /**
     * The draft to hold after running `action`.
     *
     * @param {string} action - A value of `PROMPT_COMPOSER_ACTIONS`.
     * @param {Object} context
     * @param {{ triggerIndex: number, token: string }} context.position - Where in the
     *   text the action runs. An empty token means there is nothing to replace.
     * @param {import('../../services/plugin_capabilities/slash_commands').SlashCommand}
     *   context.command - The command that asked for the action.
     * @returns {UserPromptBuilder}
     */
    draftForAction(action, { position, command }) {
      switch (action) {
        // This puts nothing in the prompt, so instead it erases however the command was
        // named -- the partial token that opened the menu, or the whole one if it was
        // typed out. What is left of the prompt is the goal itself.
        case PROMPT_COMPOSER_ACTIONS.START_GOAL:
          // Entering on no flow would send an ordinary turn dressed up as a goal.
          if (!this.availableGoalFlow) {
            captureExceptionForDuoChat(
              // eslint-disable-next-line @gitlab/require-i18n-strings -- a Sentry title
              new Error('Duo Chat cannot start goal mode without a configured flow'),
            );
            return this.draft;
          }

          return this.draft
            .withoutTriggerToken(position)
            .withoutCommandToken(command)
            .withGoalFlow(this.availableGoalFlow);
        case PROMPT_COMPOSER_ACTIONS.INSERT:
          return this.draft.withSlashCommand(command, position);
        default:
          // Only reachable if a command skipped the capability, which drops an action
          // outside `PROMPT_COMPOSER_ACTIONS`. Reported and otherwise ignored: guessing at
          // insertion would put text the command never asked for into the prompt.
          captureExceptionForDuoChat(
            new Error(`Unknown Duo Chat slash command action \`${action}\``),
          );
          return this.draft;
      }
    },
    clearGoalMode() {
      this.draft = this.draft.withoutGoalFlow();
      this.focusChatInput();
    },
    /**
     * Runs an action from an entry point that is not the suggestion menu, which means
     * there is no typed token to replace. Exposed on the `textarea-toolbar` slot so a
     * control there reaches an action without the state manager above it having to own
     * the draft.
     *
     * @param {string} name - A value of `PROMPT_COMPOSER_ACTIONS`.
     * @param {Object} [payload] - What the action needs, e.g. `{ command }`.
     * @returns {boolean} Whether `name` is an action this composer implements.
     */
    dispatchAction(name, payload = {}) {
      if (!Object.values(PROMPT_COMPOSER_ACTIONS).includes(name)) {
        captureExceptionForDuoChat(
          new Error(`Unknown Duo Chat prompt composer action \`${name}\``),
        );
        return false;
      }

      // Nothing typed asked for this, so an action that inserts appends.
      this.draft = this.draftForAction(name, {
        ...payload,
        position: { triggerIndex: this.draft.text.length, token: '' },
      });
      return true;
    },
    async onSlashCommandSelect(command, position) {
      // The menu swallows the keyup for the key that triggered this, so the
      // reset at the end of the textarea's keyup handler never runs for it.
      this.$refs.textarea?.resetComposition?.();

      this.draft = this.draftForAction(command.action ?? PROMPT_COMPOSER_ACTIONS.INSERT, {
        position,
        command,
      });

      await this.$nextTick();
      this.focusChatInput();
    },
  },
  i18n,
};
</script>
<template>
  <gl-form
    class="gl-relative"
    data-testid="chat-prompt-form"
    @submit.stop.prevent="sendChatPrompt"
    @paste="onPaste"
    @dragenter="onDragEnter"
    @dragover="onDragOver"
    @dragleave="onDragLeave"
    @drop="onDrop"
  >
    <div
      class="agentic-chat-input gl-min-h-8 gl-max-w-full gl-grow gl-flex-col gl-overflow-auto gl-rounded-lg gl-align-top gl-transition-box-shadow forced-colors:gl-border"
    >
      <div
        v-if="hasHeaderRow()"
        class="gl-flex gl-items-center gl-justify-between gl-gap-5 gl-border-0 gl-border-b-1 gl-border-solid gl-border-strong gl-px-4 gl-py-4 forced-colors:gl-border-none"
      >
        <div class="duo-model-switcher gl-min-w-0 gl-max-w-full">
          <slot name="agentic-model"></slot>
        </div>
        <div class="duo-agent-mode-switcher gl-min-w-0 gl-max-w-full gl-shrink-0">
          <slot name="agentic-switch"></slot>
        </div>
      </div>
      <div v-if="draft.goalFlow" class="gl-flex gl-px-4 gl-pt-4">
        <goal-token @remove="clearGoalMode" />
      </div>
      <file-attachments
        ref="fileAttachments"
        :attachments="draft.attachments"
        :disabled="isDisabled"
        @add="onAttachmentsAdd"
        @remove="onAttachmentRemove"
      />
      <div>
        <slash-commands-menu
          :commands="commands"
          :value="draft.text"
          :is-loading="isLoadingCommands"
          :disabled="Boolean(draft.goalFlow)"
          @select="onSlashCommandSelect"
        >
          <prompt-textarea
            ref="textarea"
            :value="draft.text"
            :disabled="isDisabled"
            :placeholder="inputPlaceholder"
            :autofocus="shouldAutoFocusInput"
            :has-header-row="hasHeaderRow()"
            @input="onInput"
            @submit="sendChatPrompt"
            @focus-change="inputHasFocus = $event"
          />
        </slash-commands-menu>
      </div>
      <div class="gl-flex gl-items-center gl-justify-end gl-px-3 gl-pb-3">
        <slot
          name="textarea-toolbar"
          :dispatch-action="dispatchAction"
          :goal-available="isGoalAvailable"
        ></slot>
        <gl-button
          v-if="showSubmitButton"
          icon="arrow-up"
          category="primary"
          variant="confirm"
          type="submit"
          :disabled="isDisabled || !isDraftSubmittable"
          data-testid="chat-prompt-submit-button"
          :aria-label="$options.i18n.CHAT_SUBMIT_LABEL"
        />
        <gl-button
          v-else
          icon="stop"
          category="primary"
          variant="default"
          data-testid="chat-prompt-cancel-button"
          :aria-label="$options.i18n.CHAT_CANCEL_LABEL"
          @click="cancelPrompt"
        />
      </div>
    </div>
  </gl-form>
</template>
