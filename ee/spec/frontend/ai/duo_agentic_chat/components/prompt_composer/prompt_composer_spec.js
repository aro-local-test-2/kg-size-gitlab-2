import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlForm, GlFormTextarea } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import waitForPromises from 'helpers/wait_for_promises';
import PromptComposer from 'ee/ai/duo_agentic_chat/components/prompt_composer/prompt_composer.vue';
import PromptTextarea from 'ee/ai/duo_agentic_chat/components/prompt_composer/prompt_textarea.vue';
import SlashCommandsMenu from 'ee/ai/duo_agentic_chat/components/prompt_composer/slash_commands_menu/slash_commands_menu.vue';
import FileAttachments from 'ee/ai/duo_agentic_chat/components/prompt_composer/file_attachments.vue';
import GoalToken from 'ee/ai/duo_agentic_chat/components/prompt_composer/goal_token.vue';
import { createUserPrompt } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { slashCommands } from 'ee/ai/duo_agentic_chat/services/plugin_capabilities';
import { initializePlugins } from 'ee/ai/duo_agentic_chat/plugins';
import { goalPlugin } from 'ee/ai/duo_agentic_chat/plugins/goal';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import {
  MAX_PROMPT_LENGTH,
  CHAT_RESET_MESSAGE,
  CHAT_CLEAR_MESSAGE,
  CHAT_NEW_MESSAGE,
} from 'ee/ai/tanuki_bot/constants';
import { MOCK_RESPONSE_MESSAGE, MOCK_USER_PROMPT_MESSAGE } from '../../../tanuki_bot/mock_data';

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

Vue.use(VueApollo);

// Helper function for waiting for async chat submission operations
const waitForChatSubmission = async () => {
  // Wait for all async operations in sendChatPrompt:
  // 1. Initial form submission
  // 2. setPromptAndFocus() await (includes its own nextTick)
  // 3. $nextTick() before setting canSubmit
  // 4. Additional nextTicks for reactive updates to propagate

  await nextTick();
  await nextTick();
  await nextTick();
};

describe('PromptComposer', () => {
  // Every mount reads a draft and every keystroke writes one, so the whole file needs
  // a per-test store to stay isolated.
  useLocalStorageSpy();

  let wrapper;

  const createComponent = ({
    propsData = {},
    slots = {},
    scopedSlots = {},
    provide = {},
    apolloProvider,
    mountFn = shallowMountExtended,
  } = {}) => {
    wrapper = mountFn(PromptComposer, {
      propsData,
      slots,
      scopedSlots,
      provide: { glFeatures: {}, ...provide },
      apolloProvider,
    });

    return wrapper;
  };

  // Goal mode needs a flow to run, which the composer looks up for itself.
  const GOAL_CHAT_CONTEXT = { projectId: 'gid://gitlab/Project/1' };

  const goalFlowQueryHandler = (consumerId) =>
    jest.fn().mockResolvedValue({
      data: {
        aiCatalogConfiguredItems: {
          nodes: consumerId
            ? [
                {
                  id: `gid://gitlab/Ai::Catalog::ItemConsumer/${consumerId}`,
                  __typename: 'AiCatalogItemConsumer',
                },
              ]
            : [],
          __typename: 'AiCatalogItemConsumerConnection',
        },
      },
    });

  const goalFlowAvailable = (consumerId = 7) => {
    window.gon = { features: { duoChatGoalCommand: true } };

    return createMockApollo([[getConfiguredFlows, goalFlowQueryHandler(consumerId)]]);
  };

  const findChatInput = () => wrapper.findComponent(PromptTextarea);
  const findChatInputNative = () => wrapper.findComponent(GlFormTextarea).find('textarea');
  const findSubmitButton = () => wrapper.findComponent('[data-testid="chat-prompt-submit-button"]');
  const findCancelButton = () => wrapper.find('[data-testid="chat-prompt-cancel-button"]');
  const findPromptForm = () => wrapper.findComponent(GlForm);

  const setPromptInput = (val) => findChatInput().vm.$emit('input', val);

  const clickSubmit = () =>
    findPromptForm().vm.$emit('submit', {
      preventDefault: jest.fn(),
      stopPropagation: jest.fn(),
    });

  const setFocusAndSubmitMessage = async (message) => {
    await findChatInputNative().trigger('focusin');
    findChatInputNative().element.value = message;
    await findChatInputNative().trigger('input');
    clickSubmit();
    await waitForChatSubmission();
  };

  // The bundled plugins are what production registers, and the composer's own tests
  // are about what it does with a command rather than where the list came from.
  const registryWithBundledPlugins = () => {
    const registry = new DuoChatPluginRegistry();
    initializePlugins(registry);
    return registry;
  };

  const promptStr = 'foo';
  const sent = (text) => createUserPrompt({ text });
  // `/compact` is a real registered command, so the payload carries it alongside
  // the text -- that is the whole point of the structured prompt.
  const sentWithCompact = createUserPrompt({
    text: '/compact',
    slashCommands: [expect.objectContaining({ value: '/compact' })],
  });

  describe('rendering', () => {
    describe('prompt placeholder', () => {
      it.each`
        chatPromptPlaceholder   | expectedPlaceholder
        ${undefined}            | ${"Let's work through this together..."}
        ${''}                   | ${"Let's work through this together..."}
        ${'custom placeholder'} | ${'custom placeholder'}
      `(
        'displays "$expectedPlaceholder" when chatPromptPlaceholder is "$chatPromptPlaceholder"',
        ({ chatPromptPlaceholder, expectedPlaceholder }) => {
          createComponent({ propsData: { chatPromptPlaceholder } });
          expect(findChatInput().props('placeholder')).toBe(expectedPlaceholder);
        },
      );
    });
  });

  describe('header row', () => {
    const findHeader = () => wrapper.find('.duo-model-switcher');

    it('renders no header row when the parent supplies neither slot', () => {
      createComponent();

      expect(findHeader().exists()).toBe(false);
    });

    // The state manager stops and starts supplying `agentic-switch` at runtime, e.g.
    // when a billing error clears. Reading the slot map from a cached computed would
    // pin the first answer and strand the toggle for the rest of the page's life.
    it('picks up a slot the parent starts supplying after mount', async () => {
      const Parent = {
        components: { PromptComposer },
        props: { withSwitch: { type: Boolean, required: true } },
        template: `
          <prompt-composer>
            <template v-if="withSwitch" #agentic-switch><button>Switch</button></template>
          </prompt-composer>
        `,
      };
      const parent = mountExtended(Parent, { propsData: { withSwitch: false } });
      expect(parent.find('.duo-model-switcher').exists()).toBe(false);

      await parent.setProps({ withSwitch: true });

      expect(parent.find('.duo-model-switcher').exists()).toBe(true);
    });
  });

  describe('chat', () => {
    it('does render the prompt input by default', () => {
      createComponent({});
      expect(findChatInput().exists()).toBe(true);
    });

    // Whether a disabled textarea actually renders as one is the textarea's own test;
    // what matters here is the composer deciding it from the two props that gate it.
    it.each`
      desc                            | propsData                                                    | disabled
      ${'chat is available'}          | ${{}}                                                        | ${false}
      ${'chat is unavailable'}        | ${{ isChatAvailable: false }}                                | ${true}
      ${'the chat state is disabled'} | ${{ chatState: { isEnabled: false, reason: 'No credits' } }} | ${true}
    `('disables the prompt input when $desc: $disabled', ({ propsData, disabled }) => {
      createComponent({ propsData });

      expect(findChatInput().props('disabled')).toBe(disabled);
    });

    describe('chatState', () => {
      it('disables the submit button when chatState.isEnabled is false', async () => {
        createComponent({
          propsData: { chatState: { isEnabled: false, reason: 'No credits' } },
        });
        setPromptInput('TEST!');
        await nextTick();

        expect(findSubmitButton().props('disabled')).toBe(true);
      });
    });

    describe('submit/cancel button', () => {
      beforeEach(() => {
        createComponent({ propsData: {}, mountFn: mountExtended });
      });

      it('renders the submitButton initially', () => {
        expect(findSubmitButton().exists()).toBe(true);
        expect(findCancelButton().exists()).toBe(false);
      });

      it('disables the submit button if the prompt is empty', async () => {
        setPromptInput('');
        expect(findSubmitButton().props('disabled')).toBe(true);

        findChatInputNative().element.value = 'TEST!';
        await findChatInputNative().trigger('input');
        await nextTick();

        expect(findSubmitButton().props('disabled')).toBe(false);
      });

      // The button and the Enter key read the same `isDraftSubmittable`, so this pins
      // the button's half of it -- the two used to disagree.
      it.each`
        desc                       | prompt                               | disabled
        ${'is only whitespace'}    | ${'   '}                             | ${true}
        ${'is over the limit'}     | ${'a'.repeat(MAX_PROMPT_LENGTH + 1)} | ${true}
        ${'sits on the limit'}     | ${'a'.repeat(MAX_PROMPT_LENGTH)}     | ${false}
        ${'has something to send'} | ${'hello'}                           | ${false}
      `(
        'disables the submit button when the prompt $desc: $disabled',
        async ({ prompt, disabled }) => {
          setPromptInput(prompt);
          await nextTick();

          expect(findSubmitButton().props('disabled')).toBe(disabled);
        },
      );

      it('renders the cancel button once the submitted prompt starts a turn', async () => {
        wrapper.vm.prompt = 'TEST!';
        clickSubmit();
        await waitForChatSubmission();
        // The state manager reports the turn it just started.
        await wrapper.setProps({ isLoading: true });

        expect(findSubmitButton().exists()).toBe(false);
        expect(findCancelButton().exists()).toBe(true);
      });

      it('renders submit button after request was canceled', async () => {
        setPromptInput('TEST!');
        clickSubmit();
        await waitForChatSubmission();
        await wrapper.setProps({ isLoading: true });

        const cancelButton = findCancelButton();
        await cancelButton.trigger('click');
        // Cancelling runs cleanupState in the state manager, which ends the turn.
        await wrapper.setProps({ isLoading: false });

        expect(findSubmitButton().exists()).toBe(true);
        expect(findCancelButton().exists()).toBe(false);
      });

      describe('Loading', () => {
        it('renders submit button when chat is not loading and cancel otherwise', async () => {
          wrapper = createComponent({
            propsData: {
              isLoading: false,
            },
            mountFn: mountExtended,
          });

          await nextTick();

          expect(findSubmitButton().exists()).toBe(true);
          expect(findCancelButton().exists()).toBe(false);

          findChatInputNative().element.value = 'TEST!';
          await findChatInputNative().trigger('input');

          clickSubmit();

          await nextTick();

          await waitForChatSubmission();

          wrapper.setProps({ isLoading: true });
          await nextTick();

          expect(findCancelButton().exists()).toBe(true);
          expect(findSubmitButton().exists()).toBe(false);

          wrapper.setProps({ isLoading: false });
          await nextTick();

          expect(findCancelButton().exists()).toBe(false);
          expect(findSubmitButton().exists()).toBe(true);
        });
      });
    });

    describe('submit', () => {
      // Enter used to bypass the two conditions that disable the submit button.
      it.each`
        desc                    | prompt
        ${'is only whitespace'} | ${'   '}
        ${'is over the limit'}  | ${'a'.repeat(MAX_PROMPT_LENGTH + 1)}
      `('sends nothing when the prompt $desc', ({ prompt }) => {
        createComponent({ propsData: { isChatAvailable: true } });

        setPromptInput(prompt);
        findChatInput().vm.$emit('submit');

        expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
        expect(wrapper.emitted('queue-chat-prompt')).toBeUndefined();
      });

      it('sends a prompt sitting exactly on the limit', () => {
        const prompt = 'a'.repeat(MAX_PROMPT_LENGTH);
        createComponent({ propsData: { isChatAvailable: true } });

        setPromptInput(prompt);
        findChatInput().vm.$emit('submit');

        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(prompt)]]);
      });

      it('trims the prompt', () => {
        const question = ' foo bar ';
        const expectedPrompt = 'foo bar';
        createComponent({
          propsData: { isChatAvailable: true },
        });
        setPromptInput(question);
        clickSubmit();
        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(expectedPrompt)]]);
      });

      // Which keystrokes count as a submit is the textarea's business; the composer
      // only sees the `submit` it decided to emit.
      it.each`
        trigger                                     | event
        ${() => clickSubmit()}                      | ${'Submit button click'}
        ${() => findChatInput().vm.$emit('submit')} | ${'the textarea asking to submit'}
      `('sends the prompt on $event', ({ trigger } = {}) => {
        createComponent({
          propsData: { isChatAvailable: true },
        });
        setPromptInput(promptStr);
        trigger();
        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(promptStr)]]);
      });

      it.each`
        desc                                              | msgs
        ${''}                                             | ${[]}
        ${'with just a user message'}                     | ${[MOCK_USER_PROMPT_MESSAGE]}
        ${'with a user message, and a complete response'} | ${[MOCK_USER_PROMPT_MESSAGE, MOCK_RESPONSE_MESSAGE]}
      `(
        'queues rather than sends a second submission when loading $desc',
        async ({ msgs } = {}) => {
          createComponent({
            propsData: { isChatAvailable: true, lastMessage: msgs[msgs.length - 1] ?? null },
          });

          setPromptInput(promptStr);
          clickSubmit();

          await waitForChatSubmission();

          expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(promptStr)]]);

          // The state manager marks the chat busy the moment the turn starts.
          await wrapper.setProps({ canSendPrompt: false });
          setPromptInput(promptStr);
          clickSubmit();

          await waitForChatSubmission();

          expect(wrapper.emitted('send-chat-prompt')).toHaveLength(1);
          expect(wrapper.emitted('queue-chat-prompt')).toEqual([[sent(promptStr)]]);
        },
      );

      it.each([
        [[{ ...MOCK_RESPONSE_MESSAGE, content: undefined, chunks: [''] }]],
        [
          [
            MOCK_USER_PROMPT_MESSAGE,
            { ...MOCK_RESPONSE_MESSAGE, content: undefined, chunks: [''] },
          ],
        ],
        [[{ ...MOCK_RESPONSE_MESSAGE, chunkId: 1 }]],
      ])(
        'queues rather than sends a second submission when streaming (messages = "%o")',
        async (msgs = []) => {
          const lastMsg = msgs[msgs.length - 1];
          createComponent({
            propsData: { isChatAvailable: true, lastMessage: lastMsg },
          });

          setPromptInput(promptStr);
          clickSubmit();

          await waitForChatSubmission();

          expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(promptStr)]]);

          // The state manager marks the chat busy the moment the turn starts.
          await wrapper.setProps({ canSendPrompt: false });
          setPromptInput(promptStr);
          clickSubmit();

          await waitForChatSubmission();

          expect(wrapper.emitted('send-chat-prompt')).toHaveLength(1);
          expect(wrapper.emitted('queue-chat-prompt')).toEqual([[sent(promptStr)]]);
        },
      );

      it('resets the prompt after form submission', async () => {
        createComponent();
        await setPromptInput(promptStr);
        expect(findChatInput().props('value')).toBe(promptStr);

        clickSubmit();
        await nextTick();

        expect(findChatInput().props('value')).toBe('');
      });

      it('focuses on prompt after form submission', async () => {
        const focusSpy = jest.fn();
        jest.spyOn(HTMLElement.prototype, 'focus').mockImplementation(function focusMockImpl() {
          focusSpy(this);
        });
        createComponent({
          mountFn: mountExtended,
        });
        findChatInputNative().element.value = 'TEST!';
        await findChatInputNative().trigger('input');

        clickSubmit();
        await nextTick();

        expect(focusSpy).toHaveBeenCalledWith(findChatInputNative().element);
      });

      it('restores focus to prompt when isLoading becomes false after sending with focus', async () => {
        createComponent({
          propsData: { isChatAvailable: true },
          mountFn: mountExtended,
        });

        await setFocusAndSubmitMessage('test message');

        const focusSpy = jest.fn();
        jest.spyOn(HTMLElement.prototype, 'focus').mockImplementation(function focusMockImpl() {
          focusSpy(this);
        });

        await wrapper.setProps({ isLoading: true });
        await wrapper.setProps({ isLoading: false });
        await nextTick();

        expect(focusSpy).toHaveBeenCalledWith(findChatInputNative().element);
      });

      it('does not restore focus when isLoading becomes false if input was not focused before send', async () => {
        createComponent({
          propsData: { isLoading: true, isChatAvailable: true },
          mountFn: mountExtended,
        });

        const focusSpy = jest.fn();
        jest.spyOn(HTMLElement.prototype, 'focus').mockImplementation(function focusMockImpl() {
          focusSpy(this);
        });

        await wrapper.setProps({ isLoading: false });
        await nextTick();

        expect(focusSpy).not.toHaveBeenCalled();
      });

      it('restores focus to prompt when isStreaming becomes false after sending with focus', async () => {
        const streamingMessage = { role: 'assistant', chunks: ['partial'], content: undefined };
        const completedMessage = { role: 'assistant', chunks: ['partial'], content: 'done' };
        createComponent({
          propsData: { isChatAvailable: true },
          mountFn: mountExtended,
        });

        await setFocusAndSubmitMessage('test message');

        const focusSpy = jest.fn();
        jest.spyOn(HTMLElement.prototype, 'focus').mockImplementation(function focusMockImpl() {
          focusSpy(this);
        });

        await wrapper.setProps({ lastMessage: streamingMessage });
        await wrapper.setProps({ lastMessage: completedMessage });
        await nextTick();

        expect(focusSpy).toHaveBeenCalledWith(findChatInputNative().element);
      });
    });

    describe('clear', () => {
      it('does not render cancel button on clear', async () => {
        createComponent({
          propsData: { isChatAvailable: true },
          mountFn: mountExtended,
        });
        setPromptInput(CHAT_CLEAR_MESSAGE);
        clickSubmit();

        await nextTick();
        expect(findSubmitButton().exists()).toBe(true);
        expect(findCancelButton().exists()).toBe(false);
      });
    });

    describe('new', () => {
      it('does not render cancel button on new', async () => {
        createComponent({
          propsData: { isChatAvailable: true },
          mountFn: mountExtended,
        });
        setPromptInput(CHAT_NEW_MESSAGE);
        clickSubmit();

        await nextTick();
        expect(findSubmitButton().exists()).toBe(true);
        expect(findCancelButton().exists()).toBe(false);
      });
    });

    describe('reset', () => {
      it('emits the event with the reset prompt', async () => {
        createComponent({
          propsData: { isChatAvailable: true },
          mountFn: mountExtended,
        });

        findChatInputNative().element.value = CHAT_RESET_MESSAGE;
        await findChatInputNative().trigger('input');
        clickSubmit();
        await waitForPromises();

        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent(CHAT_RESET_MESSAGE)]]);
        await nextTick();
        expect(findSubmitButton().exists()).toBe(true);
        expect(findCancelButton().exists()).toBe(false);
      });
    });

    describe('cancel', () => {
      it('emits cancel event on cancel button click', async () => {
        createComponent({ propsData: { isLoading: true }, mountFn: mountExtended });
        findChatInputNative().element.value = 'TEST!';
        await findChatInputNative().trigger('input');
        clickSubmit();
        await waitForChatSubmission();

        const cancelButton = findCancelButton();
        expect(cancelButton.exists()).toBe(true);
        await cancelButton.trigger('click');
        expect(wrapper.emitted('chat-cancel')).toHaveLength(1);
      });
    });
  });

  describe('textarea-toolbar slot', () => {
    it('renders the toolbar content next to the submit button', () => {
      createComponent({
        slots: { 'textarea-toolbar': '<div data-testid="toolbar-content">Actions</div>' },
      });

      expect(wrapper.findByTestId('toolbar-content').exists()).toBe(true);
    });

    it('renders nothing in the toolbar by default', () => {
      createComponent();

      expect(wrapper.findByTestId('toolbar-content').exists()).toBe(false);
    });
  });

  describe('input availability during an active turn', () => {
    it('keeps the input enabled after submitting so further prompts can be queued', async () => {
      createComponent({ mountFn: mountExtended });

      const testPrompt = 'Hello world!';
      findChatInputNative().element.value = testPrompt;
      await findChatInputNative().trigger('input');

      expect(findChatInputNative().attributes('disabled')).toBeUndefined();

      clickSubmit();

      // Prompt is cleared but the input stays enabled during the turn.
      await nextTick();
      expect(findChatInputNative().element.value).toBe('');
      expect(findChatInputNative().attributes('disabled')).toBeUndefined();

      await waitForChatSubmission();
      expect(findChatInputNative().element.value).toBe('');
      expect(findChatInputNative().attributes('disabled')).toBeUndefined();
    });
  });

  describe('queueing during an active turn', () => {
    // Sending an initial prompt starts a turn, which the state manager reports
    // back as isLoading=true and canSendPrompt=false.
    const startTurn = async () => {
      findChatInputNative().element.value = 'first prompt';
      await findChatInputNative().trigger('input');
      clickSubmit();
      await waitForChatSubmission();
      await wrapper.setProps({ isLoading: true, canSendPrompt: false });
    };

    beforeEach(() => {
      createComponent({ propsData: { isChatAvailable: true }, mountFn: mountExtended });
    });

    it('keeps the input enabled', async () => {
      await startTurn();

      expect(findChatInputNative().attributes('disabled')).toBeUndefined();
    });

    it('shows the stop button when empty and the submit button once text is entered', async () => {
      await startTurn();

      expect(findCancelButton().exists()).toBe(true);
      expect(findSubmitButton().exists()).toBe(false);

      findChatInputNative().element.value = 'queued prompt';
      await findChatInputNative().trigger('input');

      expect(findSubmitButton().exists()).toBe(true);
      expect(findCancelButton().exists()).toBe(false);

      findChatInputNative().element.value = '';
      await findChatInputNative().trigger('input');

      expect(findCancelButton().exists()).toBe(true);
      expect(findSubmitButton().exists()).toBe(false);
    });

    it('emits queue-chat-prompt instead of send-chat-prompt', async () => {
      await startTurn();

      findChatInputNative().element.value = 'queued prompt';
      await findChatInputNative().trigger('input');
      clickSubmit();
      await waitForChatSubmission();

      expect(wrapper.emitted('queue-chat-prompt')).toEqual([[sent('queued prompt')]]);
      expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent('first prompt')]]);
    });
  });

  describe('when the chat cannot take a prompt', () => {
    // canSendPrompt is false for a turn running anywhere, a flow locked in
    // another tab, or a tool call waiting on the user. The composer does not
    // work out which: it queues whenever the state manager says it cannot send.
    beforeEach(() => {
      createComponent({
        propsData: { isChatAvailable: true, canSendPrompt: false },
        mountFn: mountExtended,
      });
    });

    it('keeps the input enabled', () => {
      expect(findChatInputNative().attributes('disabled')).toBeUndefined();
    });

    it('queues the prompt instead of sending it', async () => {
      findChatInputNative().element.value = 'queued prompt';
      await findChatInputNative().trigger('input');
      clickSubmit();
      await waitForChatSubmission();

      expect(wrapper.emitted('queue-chat-prompt')).toEqual([[sent('queued prompt')]]);
      expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
    });

    it('queues a turn it did not start itself, such as one streaming from a queued prompt', async () => {
      // The regression: canSubmit stays true when the composer did not submit
      // the running turn, so it used to send straight into the stream.
      await wrapper.setProps({
        isLoading: true,
        lastMessage: { chunks: ['partial'], chunkId: 0 },
      });

      findChatInputNative().element.value = 'typed while streaming';
      await findChatInputNative().trigger('input');
      clickSubmit();
      await waitForChatSubmission();

      expect(wrapper.emitted('queue-chat-prompt')).toEqual([[sent('typed while streaming')]]);
      expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
    });
  });

  describe('slash commands', () => {
    const findSlashCommandsMenu = () => wrapper.findComponent(SlashCommandsMenu);

    beforeEach(() => {
      createComponent({
        mountFn: mountExtended,
        provide: {
          duoChatPluginRegistry: registryWithBundledPlugins(),
          duoChatContext: { projectId: 'gid://gitlab/Project/1' },
        },
      });
    });

    it('wraps the textarea in the menu and feeds it the current prompt', async () => {
      await findChatInputNative().setValue('hello');

      expect(findSlashCommandsMenu().exists()).toBe(true);
      expect(findSlashCommandsMenu().props('value')).toBe('hello');
    });

    // Picking a command never sends on its own: a command that should submit will say so
    // with a named action, and none does yet.
    it('inserts a trailing space and waits for a command with no action', async () => {
      await findChatInputNative().setValue('/dr');
      findSlashCommandsMenu().vm.$emit(
        'select',
        { value: '/draft' },
        { triggerIndex: 0, token: '/dr' },
      );
      await waitForChatSubmission();

      expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
      expect(findChatInputNative().element.value).toBe('/draft ');
    });

    describe('a command that names an action', () => {
      const selectDraftCommand = async (action) => {
        await findChatInputNative().setValue('/dr');
        findSlashCommandsMenu().vm.$emit(
          'select',
          { value: '/draft', action },
          { triggerIndex: 0, token: '/dr' },
        );
        await waitForChatSubmission();
      };

      // `insert` is also the default, so naming it explicitly has to behave the same as
      // leaving it off.
      it('inserts the token for the insert action', async () => {
        await selectDraftCommand('insert');

        expect(findChatInputNative().element.value).toBe('/draft ');
        expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
      });

      // A command naming an action the composer does not implement never reaches the menu
      // -- the capability drops it -- so this is the backstop for one that skipped it.
      // The pick is dropped rather than guessed at, so the prompt keeps what was typed.
      it('reports an action it does not implement and leaves the prompt alone', async () => {
        await selectDraftCommand('summonBadger');

        expect(findChatInputNative().element.value).toBe('/dr');
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          new Error('Unknown Duo Chat slash command action `summonBadger`'),
        );
      });

      it('reports nothing for a command with no action', async () => {
        await selectDraftCommand(undefined);

        expect(findChatInputNative().element.value).toBe('/draft ');
        expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
      });
    });

    // Typing a command runs its action. What must not run is one whose whole effect is
    // putting the token in the text, since typing it already did that.
    describe('a command typed rather than picked', () => {
      const typeCommand = async (text, command) => {
        const registry = new DuoChatPluginRegistry();
        registry.registerPlugin({
          name: 'typed_for_test',
          slashCommands: [{ getCommands: () => [command] }],
        });
        createComponent({ mountFn: mountExtended, provide: { duoChatPluginRegistry: registry } });
        await waitForPromises();

        await findChatInputNative().setValue(text);
        await waitForPromises();
        await waitForChatSubmission();
      };

      it.each`
        desc           | command
        ${'insert'}    | ${{ value: '/draft', action: 'insert' }}
        ${'no action'} | ${{ value: '/draft' }}
      `('leaves the prompt alone for a command naming $desc', async ({ command }) => {
        await typeCommand('/draft the release post', command);

        expect(findChatInputNative().element.value).toBe('/draft the release post');
        expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
      });
    });

    describe('the startGoal action', () => {
      const GOAL_COMMAND = {
        value: '/goal',
        label: 'Goal',
        description: 'Work towards a goal',
        startOnly: true,
        action: 'startGoal',
      };

      const findGoalToken = () => wrapper.findComponent(GoalToken);

      const registryOfferingGoal = () => {
        const registry = new DuoChatPluginRegistry();
        registry.registerPlugin({
          name: 'goal_for_test',
          slashCommands: [{ getCommands: () => [GOAL_COMMAND] }],
        });
        return registry;
      };

      const createWithGoalCommand = async ({ goalConsumerId = 7 } = {}) => {
        createComponent({
          mountFn: mountExtended,
          provide: { duoChatPluginRegistry: registryOfferingGoal() },
          propsData: { duoChatContext: GOAL_CHAT_CONTEXT },
          apolloProvider: goalFlowAvailable(goalConsumerId),
        });
        await waitForPromises();
      };

      const pickGoalFromMenu = async () => {
        await findChatInputNative().setValue('/go');
        findSlashCommandsMenu().vm.$emit('select', GOAL_COMMAND, {
          triggerIndex: 0,
          token: '/go',
        });
        await waitForChatSubmission();
      };

      // The goal token stands in for the command, so the prompt is left for the goal.
      it('shows the goal token and leaves no command in the prompt', async () => {
        await createWithGoalCommand();

        await pickGoalFromMenu();

        expect(findGoalToken().exists()).toBe(true);
        expect(findChatInputNative().element.value).toBe('');
      });

      // Nothing about the mode depends on the menu, so a token typed by hand is taken
      // out of the text the same way, leaving the goal behind it.
      it('enters goal mode for a token typed by hand', async () => {
        await createWithGoalCommand();

        await findChatInputNative().setValue('/goal keep the pipeline green');
        await waitForPromises();

        expect(findGoalToken().exists()).toBe(true);
        expect(findChatInputNative().element.value).toBe('keep the pipeline green');
      });

      it('swaps the placeholder for the goal prompt', async () => {
        await createWithGoalCommand();
        expect(findChatInput().props('placeholder')).toBe("Let's work through this together...");

        await pickGoalFromMenu();

        expect(findChatInput().props('placeholder')).toBe(
          'Define a condition Duo should work until it achieves...',
        );
      });

      // The command's token is already gone, so dismissing keeps whatever goal was
      // typed rather than putting it back.
      it('leaves goal mode when the token is dismissed', async () => {
        await createWithGoalCommand();
        await pickGoalFromMenu();
        await findChatInputNative().setValue('keep the pipeline green');

        findGoalToken().vm.$emit('remove');
        await nextTick();

        expect(findGoalToken().exists()).toBe(false);
        expect(findChatInputNative().element.value).toBe('keep the pipeline green');
        expect(findChatInput().props('placeholder')).toBe("Let's work through this together...");
      });

      // Reported as the flow rather than the command, so the payload reads the same
      // however goal mode was turned on.
      it('reports the goal flow on the sent prompt, and no command', async () => {
        await createWithGoalCommand();
        await pickGoalFromMenu();

        await findChatInputNative().setValue('keep the pipeline green');
        clickSubmit();
        await waitForChatSubmission();

        expect(wrapper.emitted('send-chat-prompt')).toEqual([
          [createUserPrompt({ text: 'keep the pipeline green', goalFlow: { consumerId: 7 } })],
        ]);
      });

      it('leaves goal mode after sending', async () => {
        await createWithGoalCommand();
        await pickGoalFromMenu();

        await findChatInputNative().setValue('keep the pipeline green');
        clickSubmit();
        await waitForChatSubmission();

        expect(findGoalToken().exists()).toBe(false);
      });

      // Picking a command is how goal mode starts, so once it is on there is nothing
      // left for the menu to offer: a slash belongs to the goal itself.
      describe('once goal mode is on', () => {
        it('shuts the suggestion menu', async () => {
          await createWithGoalCommand();
          expect(findSlashCommandsMenu().props('disabled')).toBe(false);

          await pickGoalFromMenu();

          expect(findSlashCommandsMenu().props('disabled')).toBe(true);
        });

        it('opens the menu again once goal mode is left', async () => {
          await createWithGoalCommand();
          await pickGoalFromMenu();

          findGoalToken().vm.$emit('remove');
          await nextTick();

          expect(findSlashCommandsMenu().props('disabled')).toBe(false);
        });

        // Nothing would read the answer, so the fetch is not worth making.
        it('does not resolve commands for a slash typed into the goal', async () => {
          const getCommands = jest.fn().mockReturnValue([GOAL_COMMAND]);
          const registry = new DuoChatPluginRegistry();
          registry.registerPlugin({ name: 'goal_for_test', slashCommands: [{ getCommands }] });
          createComponent({
            mountFn: mountExtended,
            provide: { duoChatPluginRegistry: registry },
          });
          await waitForPromises();

          await pickGoalFromMenu();
          getCommands.mockClear();

          await findChatInputNative().setValue('handle /flow: paths too');
          await waitForPromises();

          expect(getCommands).not.toHaveBeenCalled();
        });
      });

      // Answered here rather than in the toolbar, since this is also what runs the
      // action: the row cannot offer what the composer would refuse.
      describe('availability', () => {
        const findToolbarGoalAvailable = () => wrapper.findByTestId('toolbar-goal-available');

        const TOOLBAR_SLOT = {
          'textarea-toolbar':
            '<span data-testid="toolbar-goal-available">{{ props.goalAvailable }}</span>',
        };

        const mountWithAvailability = async ({ enabled = true, handler, registry } = {}) => {
          window.gon = { features: { duoChatGoalCommand: enabled } };

          createComponent({
            mountFn: mountExtended,
            provide: { duoChatPluginRegistry: registry ?? registryOfferingGoal() },
            propsData: { duoChatContext: GOAL_CHAT_CONTEXT },
            apolloProvider: createMockApollo([[getConfiguredFlows, handler]]),
            scopedSlots: TOOLBAR_SLOT,
          });
          await waitForPromises();

          return handler;
        };

        it('tells the toolbar goal mode can run once a flow resolves', async () => {
          await mountWithAvailability({ handler: goalFlowQueryHandler(7) });

          expect(findToolbarGoalAvailable().text()).toBe('true');
        });

        it('tells the toolbar it cannot when no flow is configured', async () => {
          await mountWithAvailability({ handler: goalFlowQueryHandler(null) });

          expect(findToolbarGoalAvailable().text()).toBe('false');
        });

        it('offers nothing, and asks nothing, with the feature off', async () => {
          const handler = await mountWithAvailability({
            enabled: false,
            handler: goalFlowQueryHandler(7),
          });

          expect(handler).not.toHaveBeenCalled();
          expect(findToolbarGoalAvailable().text()).toBe('false');
        });

        // The real goal plugin asks the same question to gate its command, and the query
        // is cache-first, so the two of them cost one request.
        it('shares one request with the goal plugin', async () => {
          const registry = new DuoChatPluginRegistry();
          registry.registerPlugin(goalPlugin);

          const handler = await mountWithAvailability({
            handler: goalFlowQueryHandler(7),
            registry,
          });

          // Opens the suggestion menu, which is what asks the plugin for its commands.
          await findChatInputNative().setValue('/go');
          await waitForPromises();

          expect(wrapper.findComponent(SlashCommandsMenu).props('commands')).toEqual([
            expect.objectContaining({ value: '/goal' }),
          ]);
          expect(handler).toHaveBeenCalledTimes(1);
        });

        // A chat panel must not raise an error over an optional flow.
        it('reports a failed lookup and leaves the row hidden', async () => {
          await mountWithAvailability({ handler: jest.fn().mockRejectedValue(new Error('nope')) });

          expect(captureExceptionForDuoChat).toHaveBeenCalled();
          expect(findToolbarGoalAvailable().text()).toBe('false');
        });
      });

      // Entering on no flow would send an ordinary turn dressed up as a goal.
      it('refuses to start without a flow, and reports it', async () => {
        await createWithGoalCommand({ goalConsumerId: null });

        await pickGoalFromMenu();

        expect(findGoalToken().exists()).toBe(false);
        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          new Error('Duo Chat cannot start goal mode without a configured flow'),
        );
      });

      describe('dispatched from the textarea-toolbar slot', () => {
        const dispatching = (args) => ({
          'textarea-toolbar': `<button
            type="button"
            data-testid="toolbar-goal"
            @click="props.dispatchAction(${args})"
          />`,
        });

        const clickToolbar = async (scopedSlots, registry = registryOfferingGoal()) => {
          createComponent({
            mountFn: mountExtended,
            provide: { duoChatPluginRegistry: registry },
            propsData: { duoChatContext: GOAL_CHAT_CONTEXT },
            apolloProvider: goalFlowAvailable(),
            scopedSlots,
          });
          await waitForPromises();

          await wrapper.findByTestId('toolbar-goal').trigger('click');
          await waitForChatSubmission();
        };

        // Single-quoted: the expression is interpolated into a double-quoted attribute.
        const dispatchGoal =
          "'startGoal', { command: { value: '/goal', startOnly: true, action: 'startGoal' } }";

        // The toolbar has no typed token, and the command acts on the whole prompt, so
        // it goes in at the start rather than after what the user has written.
        it('enters goal mode ahead of the text already typed', async () => {
          createComponent({
            mountFn: mountExtended,
            provide: { duoChatPluginRegistry: registryOfferingGoal() },
            propsData: { duoChatContext: GOAL_CHAT_CONTEXT },
            apolloProvider: goalFlowAvailable(),
            scopedSlots: dispatching(dispatchGoal),
          });
          await waitForPromises();
          await findChatInputNative().setValue('half a thought');

          await wrapper.findByTestId('toolbar-goal').trigger('click');
          await waitForChatSubmission();

          expect(findGoalToken().exists()).toBe(true);
          expect(findChatInputNative().element.value).toBe('half a thought');
          expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
        });

        // The toolbar can be the first thing touched, so the catalogue the draft reads
        // the command back off is only fetched once the token lands in the text.
        it('enters goal mode with no command resolved beforehand', async () => {
          await clickToolbar(dispatching(dispatchGoal));

          expect(findGoalToken().exists()).toBe(true);
          expect(findChatInputNative().element.value).toBe('');
        });

        it('reports an action this composer does not implement', async () => {
          await clickToolbar(dispatching("'summonBadger'"));

          expect(findGoalToken().exists()).toBe(false);
          expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
            new Error('Unknown Duo Chat prompt composer action `summonBadger`'),
          );
        });
      });
    });

    // The end-to-end path -- menu opens, Enter selects, the command reaches the
    // websocket -- lives in the frontend integration spec, which can see that /new is
    // handled locally while /compact starts a workflow. What is left here is the
    // composer's own contract with the menu.
    describe('Enter while the menu is open', () => {
      const openMenuOn = async (text, caret = text.length) => {
        const textarea = findChatInputNative().element;
        textarea.value = text;
        textarea.setSelectionRange(caret, caret);
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
        await nextTick();
        // The commands are resolved from the plugin registry, so the options are one
        // microtask behind the keystroke that asked for them.
        await waitForPromises();
      };

      const pressEnter = async () => {
        const textarea = findChatInputNative().element;
        const options = { key: 'Enter', bubbles: true, cancelable: true };

        textarea.dispatchEvent(new KeyboardEvent('keydown', options));
        await nextTick();
        textarea.dispatchEvent(new KeyboardEvent('keyup', options));
        await waitForChatSubmission();
      };

      // Choosing a command fills the composer rather than sending, so this also
      // covers that the Enter which took the command did not send anything.
      it('inserts the command and sends nothing', async () => {
        await openMenuOn('/co');

        await pressEnter();

        expect(findChatInputNative().element.value).toBe('/compact ');
        expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
      });

      // Replacing the whole prompt used to discard whatever the user had
      // already written after the command.
      it('keeps text that follows the command', async () => {
        await openMenuOn('/co hello world', 3);

        await pressEnter();

        expect(findChatInputNative().element.value).toBe('/compact hello world');
        expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
      });

      // The menu swallows the keyup, so the reset at the end of onInputKeyup is
      // skipped and onSlashCommandSelect has to clear the flag instead. Asserted
      // through a later Enter rather than the flag itself: a stuck flag is only a
      // bug because it silently discards the next send.
      it('leaves a later Enter able to send after composing', async () => {
        await openMenuOn('/co');
        await findChatInputNative().trigger('compositionend');

        await pressEnter();

        await findChatInputNative().trigger('keyup', { key: 'Enter' });
        await waitForChatSubmission();

        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sentWithCompact]]);
      });
    });

    // The menu is the only thing that knows a command's metadata, but the user can
    // always type the token themselves. Both routes have to produce the same payload,
    // or a consumer cannot trust `slashCommands` to describe the prompt.
    it('carries a command the user typed without ever opening the menu', async () => {
      const textarea = findChatInputNative().element;
      // Trailing space closes the menu, so this is a plain Enter, not a selection.
      textarea.value = '/compact ';
      textarea.setSelectionRange(9, 9);
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      await nextTick();

      textarea.dispatchEvent(
        new KeyboardEvent('keyup', { key: 'Enter', bubbles: true, cancelable: true }),
      );
      await waitForChatSubmission();

      expect(wrapper.emitted('send-chat-prompt')).toEqual([[sentWithCompact]]);
    });

    describe('resolving the commands', () => {
      let getCommands;

      const COMMANDS = [{ value: '/compact', description: 'Compact this conversation' }];
      const A_PROJECT = { projectId: 'gid://gitlab/Project/1' };
      const ANOTHER_PROJECT = { projectId: 'gid://gitlab/Project/2' };

      // `answer` takes over from `commands` to control *when* a provider replies.
      const createWithPlugin = ({ commands = COMMANDS, answer = null, withPlugin = true } = {}) => {
        getCommands = jest.fn(answer ?? (() => Promise.resolve(commands)));

        const registry = new DuoChatPluginRegistry();
        if (withPlugin) {
          registry.registerPlugin({ name: 'a_plugin', slashCommands: [{ getCommands }] });
        }

        createComponent({
          propsData: { duoChatContext: A_PROJECT },
          provide: { duoChatPluginRegistry: registry },
        });
      };

      const type = async (text) => {
        setPromptInput(text);
        await waitForPromises();
      };

      const moveContext = async () => {
        await wrapper.setProps({ duoChatContext: ANOTHER_PROJECT });
        await waitForPromises();
      };

      it('asks the plugins for the commands of the current chat context', async () => {
        createWithPlugin();

        await type('/');

        expect(getCommands).toHaveBeenCalledWith(
          expect.objectContaining({ duoChatContext: A_PROJECT }),
        );
      });

      it('hands the commands to the menu once they arrive', async () => {
        createWithPlugin();

        await type('/');

        expect(findSlashCommandsMenu().props('commands')).toEqual(COMMANDS);
      });

      it('gives the menu an empty list when the plugins offer nothing', async () => {
        createWithPlugin({ withPlugin: false });

        await type('/');

        expect(findSlashCommandsMenu().props('commands')).toEqual([]);
      });

      // A provider may go to the network to answer, and most messages hold no command.
      describe('waiting until a command could be wanted', () => {
        it('asks for nothing while the prompt holds no command', async () => {
          createWithPlugin();

          await waitForPromises();

          expect(getCommands).not.toHaveBeenCalled();
        });

        it.each(['hello', 'https://example.com', 'and/or'])(
          'stays quiet for %p, which holds no command',
          async (text) => {
            createWithPlugin();

            await type(text);

            expect(getCommands).not.toHaveBeenCalled();
          },
        );

        it('asks once for a command typed one character at a time', async () => {
          createWithPlugin();

          await type('/');
          await type('/co');
          await type('/compact');

          expect(getCommands).toHaveBeenCalledTimes(1);
        });

        it('tells the menu it is waiting, so a trigger does not look ignored', async () => {
          let answer;
          createWithPlugin({
            answer: () =>
              new Promise((resolve) => {
                answer = resolve;
              }),
          });

          await type('/');
          expect(findSlashCommandsMenu().props('isLoading')).toBe(true);

          answer(COMMANDS);
          await waitForPromises();
          expect(findSlashCommandsMenu().props('isLoading')).toBe(false);
        });
      });

      it('carries the command when the prompt is sent before the plugins answer', async () => {
        let answer;
        createWithPlugin({
          answer: () =>
            new Promise((resolve) => {
              answer = resolve;
            }),
        });

        setPromptInput('/compact');
        await nextTick();

        clickSubmit();
        answer(COMMANDS);
        await waitForPromises();

        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sentWithCompact]]);
      });

      it('asks once for a send in the same context as the menu', async () => {
        createWithPlugin();
        await type('/compact');

        clickSubmit();
        await waitForPromises();

        expect(getCommands).toHaveBeenCalledTimes(1);
        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sentWithCompact]]);
      });

      // `resolve` contains provider failures itself, so this is the unexpected case.
      describe('when resolving fails', () => {
        const failOnce = () =>
          jest.spyOn(slashCommands, 'resolve').mockRejectedValueOnce(new Error('exploded'));

        it('asks again on the next trigger rather than staying empty', async () => {
          createWithPlugin();
          failOnce();
          await type('/');

          await type('/co');
          await waitForPromises();

          expect(findSlashCommandsMenu().props('commands')).toEqual(COMMANDS);
        });

        it('still sends, with whatever it holds', async () => {
          createWithPlugin();
          jest.spyOn(slashCommands, 'resolve').mockRejectedValue(new Error('exploded'));
          await type('/compact');

          clickSubmit();
          await waitForPromises();

          expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent('/compact')]]);
        });
      });

      it('sends a prompt with no command without asking the plugins', async () => {
        createWithPlugin();
        await type('hello');

        clickSubmit();
        await waitForPromises();

        expect(getCommands).not.toHaveBeenCalled();
        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent('hello')]]);
      });

      describe('when the chat moves to another context', () => {
        it('asks the plugins again, for the context the chat is now on', async () => {
          createWithPlugin();
          await type('/');

          await moveContext();

          expect(getCommands).toHaveBeenLastCalledWith(
            expect.objectContaining({ duoChatContext: ANOTHER_PROJECT }),
          );
        });

        it('drops the commands of the context the chat has left', async () => {
          createWithPlugin();
          await type('/');

          wrapper.setProps({ duoChatContext: ANOTHER_PROJECT });
          await nextTick();

          expect(findSlashCommandsMenu().props('commands')).toEqual([]);
        });
      });
    });

    describe('Enter with no menu open', () => {
      it('still sends the prompt', async () => {
        const textarea = findChatInputNative().element;
        textarea.value = 'hello there';
        textarea.setSelectionRange(11, 11);
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
        await nextTick();

        textarea.dispatchEvent(
          new KeyboardEvent('keyup', { key: 'Enter', bubbles: true, cancelable: true }),
        );
        await waitForChatSubmission();

        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sent('hello there')]]);
      });
    });
  });
  // The composer owns the draft, so it is what decides whether a draft holding images
  // is worth sending and what happens when it cannot be. The file handling itself is
  // <file-attachments>'s, and is covered by its own spec.
  describe('attachments', () => {
    const attachment = { id: 'a-1', filename: 'a.png', byteSize: 1, mimeType: 'image/png' };

    const findFileAttachments = () => wrapper.findComponent(FileAttachments);
    const attach = async (...attachments) => {
      findFileAttachments().vm.$emit('add', attachments);
      await nextTick();
    };

    const createWithFlag = (propsData = {}) =>
      createComponent({
        propsData,
        provide: { glFeatures: { dapWebChatFileAttachments: true } },
      });

    it('folds the accepted files into the draft', async () => {
      createWithFlag();

      await attach(attachment);

      expect(findFileAttachments().props('attachments')).toEqual([attachment]);
    });

    it('takes an attachment back out of the draft on request', async () => {
      createWithFlag();
      await attach(attachment, { ...attachment, id: 'a-2', filename: 'b.png' });

      findFileAttachments().vm.$emit('remove', 'a-1');
      await nextTick();

      expect(
        findFileAttachments()
          .props('attachments')
          .map((a) => a.filename),
      ).toEqual(['b.png']);
    });

    // `goal` has no presence validation and the flow service appends image blocks
    // independently of the prompt text, so an image on its own is a message.
    it('sends an attachment with no prompt text', async () => {
      createWithFlag();
      await attach(attachment);

      clickSubmit();
      await waitForChatSubmission();

      expect(wrapper.emitted('send-chat-prompt')).toEqual([
        [createUserPrompt({ text: '', attachments: [attachment] })],
      ]);
    });

    it('keeps submit disabled with neither text nor attachments', () => {
      createWithFlag();

      expect(findSubmitButton().props('disabled')).toBe(true);
    });

    it('enables submit once an attachment arrives', async () => {
      createWithFlag();

      await attach(attachment);

      expect(findSubmitButton().props('disabled')).toBe(false);
    });

    it('clears the attachments after sending', async () => {
      createWithFlag();
      await attach(attachment);

      clickSubmit();
      await waitForChatSubmission();

      expect(findFileAttachments().props('attachments')).toEqual([]);
    });

    describe('when the chat cannot take the prompt', () => {
      let rejectQueueing;

      beforeEach(async () => {
        createWithFlag({ canSendPrompt: false });
        setPromptInput('with an image');
        await attach(attachment);

        rejectQueueing = jest.fn();
        findFileAttachments().vm.rejectQueueing = rejectQueueing;

        clickSubmit();
        await waitForChatSubmission();
      });

      // The queue persists to sessionStorage and cannot carry base64 payloads. Queueing
      // the text alone would detach the images from the message they belong to.
      it('neither queues nor sends', () => {
        expect(wrapper.emitted('queue-chat-prompt')).toBeUndefined();
        expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
      });

      it('holds the whole submission in the composer', () => {
        expect(findFileAttachments().props('attachments')).toEqual([attachment]);
        expect(findChatInput().props('value')).toBe('with an image');
      });

      it('asks the attachments to explain why nothing was sent', () => {
        expect(rejectQueueing).toHaveBeenCalled();
      });
    });

    // The form owns the elements these land on and forwards them to <file-attachments>.
    // Mounted for real, because the whole point is that the listeners are bound and that
    // the events reach the child -- a stub would assert nothing.
    describe('event wiring', () => {
      const fileDrag = () => ({
        dataTransfer: { types: ['Files'], files: [] },
        preventDefault: jest.fn(),
      });

      beforeEach(() => {
        createComponent({
          mountFn: mountExtended,
          provide: { glFeatures: { dapWebChatFileAttachments: true } },
        });
      });

      it('routes a drag over the form to the attachments', async () => {
        findPromptForm().vm.$emit('dragenter', fileDrag());
        await nextTick();

        expect(wrapper.findByTestId('attachment-drop-overlay').exists()).toBe(true);
      });

      it('routes a paste on the form to the attachments', () => {
        const onPaste = jest.fn();
        findFileAttachments().vm.onPaste = onPaste;
        const event = { clipboardData: { files: [] }, preventDefault: jest.fn() };

        findPromptForm().vm.$emit('paste', event);

        expect(onPaste).toHaveBeenCalledWith(event);
      });

      it('routes a drop on the form to the attachments', () => {
        const onDrop = jest.fn();
        findFileAttachments().vm.onDrop = onDrop;
        const event = fileDrag();

        findPromptForm().vm.$emit('drop', event);

        expect(onDrop).toHaveBeenCalledWith(event);
      });
    });

    it('opens the file picker for the parent', () => {
      createWithFlag();
      const openFilePicker = jest.fn();
      findFileAttachments().vm.openFilePicker = openFilePicker;

      wrapper.vm.openFilePicker();

      expect(openFilePicker).toHaveBeenCalled();
    });
  });

  describe('draft persistence', () => {
    const userId = 'user-42';
    const threadId = '99';
    const storageKey = 'autosave/duo_chat_draft_user-42_99';

    const createWithDraftProps = (propsData = {}) =>
      createComponent({ propsData: { userId, threadId, ...propsData }, mountFn: mountExtended });

    describe('when a draft is stored for the thread', () => {
      beforeEach(() => {
        localStorage.setItem(storageKey, 'my saved draft');
        createWithDraftProps();
      });

      it('restores it into the textarea', () => {
        expect(findChatInputNative().element.value).toBe('my saved draft');
      });
    });

    describe('when no draft is stored', () => {
      beforeEach(() => {
        createWithDraftProps();
      });

      it('leaves the textarea empty', () => {
        expect(findChatInputNative().element.value).toBe('');
      });

      it('stores what the user types', async () => {
        findChatInputNative().element.value = 'hello world';
        await findChatInputNative().trigger('input');

        expect(localStorage.getItem(storageKey)).toBe('hello world');
      });
    });

    // Only the text is persisted. Goal mode left standing over restored text would send a
    // prompt the user never turned it on for, so restoring leaves it.
    describe('with goal mode on', () => {
      const GOAL = { value: '/goal', label: 'Goal', startOnly: true, action: 'startGoal' };

      const goalModeThen = async (act) => {
        createComponent({
          propsData: { userId, threadId, duoChatContext: GOAL_CHAT_CONTEXT },
          apolloProvider: goalFlowAvailable(),
          mountFn: mountExtended,
          provide: {
            duoChatPluginRegistry: (() => {
              const registry = new DuoChatPluginRegistry();
              registry.registerPlugin({
                name: 'goal_for_test',
                slashCommands: [{ getCommands: () => [GOAL] }],
              });
              return registry;
            })(),
          },
        });
        await waitForPromises();

        await findChatInputNative().setValue('/go');
        wrapper
          .findComponent(SlashCommandsMenu)
          .vm.$emit('select', GOAL, { triggerIndex: 0, token: '/go' });
        await waitForChatSubmission();
        expect(wrapper.findComponent(GoalToken).exists()).toBe(true);

        await act();
      };

      it('leaves goal mode when another thread\u2019s draft is restored', async () => {
        localStorage.setItem('autosave/duo_chat_draft_user-42_100', 'a different thread');

        await goalModeThen(async () => {
          await wrapper.setProps({ threadId: '100' });
        });

        expect(wrapper.findComponent(GoalToken).exists()).toBe(false);
        expect(findChatInputNative().element.value).toBe('a different thread');
      });
    });

    describe('when the thread has no id yet', () => {
      beforeEach(() => {
        localStorage.setItem('autosave/duo_chat_draft_user-42_new', 'draft for a new thread');
        createWithDraftProps({ threadId: null });
      });

      it('falls back to the new-thread key', () => {
        expect(findChatInputNative().element.value).toBe('draft for a new thread');
      });
    });

    // The composer restores text before the slash-command catalogue has resolved, so a
    // restored command is only recognised once `commands` lands and the draft is
    // reconciled against it. Without that the payload would carry the text alone.
    describe('when the stored draft contains a slash command', () => {
      beforeEach(async () => {
        localStorage.setItem(storageKey, '/compact');
        createComponent({
          propsData: { userId, threadId },
          mountFn: mountExtended,
          provide: {
            duoChatPluginRegistry: registryWithBundledPlugins(),
            duoChatContext: { projectId: 'gid://gitlab/Project/1' },
          },
        });
        await waitForPromises();

        clickSubmit();
        await waitForChatSubmission();
      });

      it('sends it as a command, not just text', () => {
        expect(wrapper.emitted('send-chat-prompt')).toEqual([[sentWithCompact]]);
      });
    });

    describe('when a new chat is assigned its thread id', () => {
      // The first send creates the workflow, so the key changes under a live composer.
      // A follow-up being typed belongs to that thread now.
      beforeEach(async () => {
        createWithDraftProps({ threadId: null });

        findChatInputNative().element.value = 'my follow-up message';
        await findChatInputNative().trigger('input');

        await wrapper.setProps({ threadId: '99' });
        jest.runAllTimers();
      });

      it('keeps the text in the textarea', () => {
        expect(findChatInputNative().element.value).toBe('my follow-up message');
      });

      it('moves it to the thread key', () => {
        expect(localStorage.getItem(storageKey)).toBe('my follow-up message');
      });

      it('leaves nothing behind under the new-chat key', () => {
        expect(localStorage.getItem('autosave/duo_chat_draft_user-42_new')).toBe(null);
      });
    });

    describe('when the user leaves a thread for a new chat', () => {
      // The opposite direction is a navigation, not an id assignment, so the thread's
      // text stays with the thread and the new chat shows its own draft.
      beforeEach(async () => {
        localStorage.setItem('autosave/duo_chat_draft_user-42_new', 'draft left in the new chat');
        createWithDraftProps();

        findChatInputNative().element.value = 'text typed in the thread';
        await findChatInputNative().trigger('input');

        await wrapper.setProps({ threadId: null });
        jest.runAllTimers();
      });

      it('shows the new chat draft rather than carrying text over', () => {
        expect(findChatInputNative().element.value).toBe('draft left in the new chat');
      });

      it('leaves the thread draft where it was', () => {
        expect(localStorage.getItem(storageKey)).toBe('text typed in the thread');
      });
    });

    describe('when the composer is torn down while a command lookup is pending', () => {
      // Teardown persists the draft. The in-flight send must not carry on afterwards,
      // because its emit lands nowhere and its cleanup would delete that draft.
      beforeEach(async () => {
        createWithDraftProps();

        findChatInputNative().element.value = '/some-command';
        await findChatInputNative().trigger('input');
        jest.runAllTimers();

        clickSubmit();
        wrapper.destroy();
        await waitForPromises();
      });

      it('keeps the persisted draft', () => {
        expect(localStorage.getItem(storageKey)).toBe('/some-command');
      });

      it('does not emit a prompt nobody can receive', () => {
        expect(wrapper.emitted('send-chat-prompt')).toBeUndefined();
      });
    });

    describe('when the user switches to another thread', () => {
      beforeEach(async () => {
        localStorage.setItem('autosave/duo_chat_draft_user-42_100', 'draft for the other thread');
        createWithDraftProps();

        await wrapper.setProps({ threadId: '100' });
      });

      it('swaps in the draft belonging to that thread', () => {
        expect(findChatInputNative().element.value).toBe('draft for the other thread');
      });
    });

    describe('when the user sends the prompt', () => {
      beforeEach(async () => {
        createWithDraftProps();
        await setFocusAndSubmitMessage('hello world');
      });

      it('drops the stored draft', () => {
        expect(localStorage.getItem(storageKey)).toBe(null);
      });
    });

    describe('when the user cancels the prompt', () => {
      beforeEach(async () => {
        // The cancel button replaces submit only while a turn is running and the input is empty,
        // so there is no draft left to seed here.
        createWithDraftProps({ isLoading: true });

        await findCancelButton().trigger('click');
      });

      it('drops the stored draft', () => {
        expect(localStorage.removeItem).toHaveBeenCalledWith(storageKey);
      });
    });
  });
});
