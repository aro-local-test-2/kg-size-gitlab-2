import { nextTick } from 'vue';
import { GlEmptyState, GlPopover } from '@gitlab/ui';
import {
  DuoChatPredefinedPrompts,
  DuoChatContextConversation as DuoChatConversation,
  MESSAGE_MODEL_ROLES,
} from '@gitlab/duo-ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { stubComponent } from 'helpers/stub_component';
import DuoChatAlerts from 'ee/ai/duo_agentic_chat/components/duo_chat_alerts.vue';
import DuoChatHeader from 'ee/ai/duo_agentic_chat/components/duo_chat_header.vue';
import SessionPillsBar from 'ee/ai/duo_agentic_chat/components/session_pills/session_pills_bar.vue';
import PromptComposer from 'ee/ai/duo_agentic_chat/components/prompt_composer/prompt_composer.vue';
import QueuedPromptMessage from 'ee/ai/duo_agentic_chat/components/queued_prompt_message.vue';
import DuoChatScrollRegion from 'ee/ai/duo_agentic_chat/components/duo_chat_scroll_region.vue';
import { createUserPrompt } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import AgenticDuoChatView from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_view.vue';
import { CHAT_RESET_MESSAGE } from 'ee/ai/tanuki_bot/constants';
import { MOCK_RESPONSE_MESSAGE } from '../../tanuki_bot/mock_data';

describe('AgenticDuoChatView', () => {
  let scrollIntoViewMock;
  let wrapper;
  let mockFocusChatInput;
  let mockSendPredefinedPrompt;
  let mockRePinIfAtBottom;

  const createComponent = ({
    propsData = {},
    provide = {},
    slots = {},
    scopedSlots = {},
    mountFn = shallowMountExtended,
  } = {}) => {
    mockFocusChatInput = jest.fn();
    mockSendPredefinedPrompt = jest.fn();
    mockRePinIfAtBottom = jest.fn();

    wrapper = mountFn(AgenticDuoChatView, {
      propsData,
      provide,
      slots,
      scopedSlots,
      stubs: {
        // Stubbed with its scroll API, so the view's forwarding is observable
        // without pulling the whole scroll mechanism into these tests.
        DuoChatScrollRegion: stubComponent(DuoChatScrollRegion, {
          template: '<div><slot name="header"></slot><slot></slot></div>',
          methods: {
            rePinIfAtBottom: mockRePinIfAtBottom,
          },
        }),
        GlEmptyState,
        GlPopover,
        DuoChatConversation: stubComponent(DuoChatConversation, {
          props: {
            ...DuoChatConversation.props,
            isRetryEnabled: {
              type: Boolean,
              required: false,
              default: false,
            },
          },
        }),
        PromptComposer: stubComponent(PromptComposer, {
          methods: {
            focusChatInput: mockFocusChatInput,
            sendPredefinedPrompt: mockSendPredefinedPrompt,
          },
        }),
      },
    });

    return wrapper;
  };

  const findChatComponent = () => wrapper.find('[data-testid="chat-component"]');
  const findScrollRegion = () => wrapper.findComponent(DuoChatScrollRegion);
  const findChatConversations = () => wrapper.findAllComponents(DuoChatConversation);
  const findError = () => wrapper.find('[data-testid="chat-error"]');
  const findFooter = () => wrapper.find('[data-testid="chat-footer"]');
  const findDisclaimer = () => wrapper.find('[data-testid="chat-disclaimer"]');
  const findPromptComposer = () => wrapper.findComponent(PromptComposer);
  const findQueuedPromptMessages = () => wrapper.findAllComponents(QueuedPromptMessage);
  const findEmptyState = () => wrapper.find('[data-testid="gl-duo-chat-empty-state"]');
  const findEmptyStateTitle = () => wrapper.find('[data-testid="gl-duo-chat-empty-state-title"]');
  const findPredefined = () => wrapper.findComponent(DuoChatPredefinedPrompts);
  const findChatHeader = () => wrapper.findComponent(DuoChatHeader);
  const findChatAlerts = () => wrapper.findComponent(DuoChatAlerts);
  const findSessionPillsBar = () => wrapper.findComponent(SessionPillsBar);
  const findBeforeFooterSlot = () => wrapper.find('[data-testid="chat-before-footer"]');

  beforeEach(() => {
    scrollIntoViewMock = jest.fn();
    window.HTMLElement.prototype.scrollIntoView = scrollIntoViewMock;
  });

  const promptStr = 'foo';
  const messages = [
    {
      role: MESSAGE_MODEL_ROLES.user,
      content: promptStr,
    },
  ];

  describe('rendering', () => {
    it('passes chatState reason to duo-chat-header when messages exist', () => {
      const chatState = { isEnabled: false, reason: 'No credits remain' };
      createComponent({
        propsData: { chatState, messages },
      });

      expect(findChatHeader().props('info')).toBe(chatState.reason);
    });

    it('does not pass chatState reason to duo-chat-header when no messages exist', () => {
      const chatState = { isEnabled: false, reason: 'No credits remain' };
      createComponent({
        propsData: { chatState, messages: [] },
      });

      expect(findChatHeader().props('info')).toBe('');
    });

    describe('when the header is hidden', () => {
      const chatState = { isEnabled: false, reason: 'No credits remain' };

      beforeEach(() => {
        createComponent({
          propsData: { chatState, messages, error: 'Something went wrong', showHeader: false },
        });
      });

      it('renders the alerts on their own', () => {
        expect(findChatHeader().exists()).toBe(false);
        expect(findChatAlerts().props()).toMatchObject({
          info: chatState.reason,
          error: 'Something went wrong',
        });
      });
    });

    describe('before-footer slot', () => {
      it('renders content passed into the before-footer slot', () => {
        createComponent({
          slots: {
            'before-footer': '<div data-testid="chat-before-footer">Banner content</div>',
          },
        });

        expect(findBeforeFooterSlot().exists()).toBe(true);
      });

      it('renders nothing in the before-footer slot by default', () => {
        createComponent();

        expect(findBeforeFooterSlot().exists()).toBe(false);
      });
    });

    it('does not fail if no messages are passed', () => {
      createComponent({
        propsData: { messages: null },
      });

      expect(findChatConversations()).toHaveLength(0);
      expect(findEmptyState().exists()).toBe(true);
    });

    it.each`
      desc                            | component            | shouldRender
      ${'renders root component'}     | ${findChatComponent} | ${true}
      ${'renders empty state'}        | ${findEmptyState}    | ${true}
      ${'renders predefined prompts'} | ${findPredefined}    | ${true}
      ${'does not render chat error'} | ${findError}         | ${false}
    `('$desc', ({ component, shouldRender }) => {
      createComponent();

      expect(component().exists()).toBe(shouldRender);
    });

    it('renders PromptComposer component', () => {
      createComponent();

      expect(findPromptComposer().exists()).toBe(true);
    });

    describe('queued prompts', () => {
      const queuedPrompts = [
        { id: 'q1', prompt: createUserPrompt({ text: 'first queued' }) },
        { id: 'q2', prompt: createUserPrompt({ text: 'second queued' }) },
      ];

      it('renders a QueuedPromptMessage per queued prompt', () => {
        createComponent({ propsData: { queuedPrompts } });

        expect(findQueuedPromptMessages()).toHaveLength(2);
        expect(findQueuedPromptMessages().at(0).props('content')).toBe('first queued');
      });

      it('renders none when the queue is empty', () => {
        createComponent();

        expect(findQueuedPromptMessages()).toHaveLength(0);
      });

      it('forwards remove-queued-prompt with the item id when a queued message is removed', () => {
        createComponent({ propsData: { queuedPrompts } });

        findQueuedPromptMessages().at(1).vm.$emit('remove');

        expect(wrapper.emitted('remove-queued-prompt')).toEqual([['q2']]);
      });

      it('forwards queue-chat-prompt from the prompt composer', () => {
        createComponent();

        findPromptComposer().vm.$emit('queue-chat-prompt', 'queued text');

        expect(wrapper.emitted('queue-chat-prompt')).toEqual([['queued text']]);
      });
    });

    it('passes canSendPrompt down to the prompt composer, which decides send vs queue', () => {
      createComponent({ propsData: { canSendPrompt: false } });

      expect(findPromptComposer().props('canSendPrompt')).toBe(false);
    });

    describe('when the flow is locked in another tab', () => {
      it('shows the flow-locked notice in the header instead of disabling input', () => {
        createComponent({ propsData: { isFlowLocked: true } });

        expect(findChatHeader().props('info')).toBe(
          'GitLab Duo is responding to this chat in another tab or location. Messages you send will be queued and delivered once it finishes.',
        );
      });
    });

    describe('conversations', () => {
      it('renders conversation with correct props', () => {
        const newMessages = [
          {
            role: MESSAGE_MODEL_ROLES.user,
            content: 'How are you?',
          },
          {
            role: MESSAGE_MODEL_ROLES.assistant,
            content: 'Great!',
          },
        ];
        createComponent({ propsData: { messages: newMessages } });
        expect(findChatConversations().at(0).props('messages')).toEqual(newMessages);
        expect(findChatConversations().at(0).props('showDelimiter')).toEqual(false);
      });

      it('renders one conversation when no reset message is present', () => {
        const newMessages = [
          {
            role: MESSAGE_MODEL_ROLES.user,
            content: 'How are you?',
          },
          {
            role: MESSAGE_MODEL_ROLES.assistant,
            content: 'Great!',
          },
        ];
        createComponent({ propsData: { messages: newMessages } });

        expect(findChatConversations()).toHaveLength(1);
        expect(findChatConversations().at(0).props('showDelimiter')).toEqual(false);
      });

      it('does not render conversations when no message is present', () => {
        createComponent({ propsData: { messages: [] } });

        expect(findChatConversations()).toHaveLength(0);
      });

      it('splits it up into multiple conversations when reset message is present', () => {
        const newMessages = [
          {
            role: MESSAGE_MODEL_ROLES.user,
            content: 'Message 1',
          },
          {
            role: MESSAGE_MODEL_ROLES.assistant,
            content: 'Great!',
          },
          {
            role: MESSAGE_MODEL_ROLES.user,
            content: CHAT_RESET_MESSAGE,
          },
        ];
        createComponent({ propsData: { messages: newMessages } });

        expect(findChatConversations()).toHaveLength(2);
        expect(findChatConversations().at(0).props('showDelimiter')).toEqual(false);
        expect(findChatConversations().at(1).props('showDelimiter')).toEqual(true);
      });

      const tierAccessDeniedMessages = [
        {
          role: MESSAGE_MODEL_ROLES.user,
          content: 'Do the thing',
        },
        {
          role: MESSAGE_MODEL_ROLES.assistant,
          message_type: 'agent',
          message_sub_type: 'tier_access_denied',
          content: 'Not available on your tier',
        },
      ];

      it('on SaaS, rewrites tier_access_denied messages to tool role so they fall through to MessageMap', () => {
        createComponent({ propsData: { messages: tierAccessDeniedMessages, isSaas: true } });

        const rendered = findChatConversations().at(0).props('messages');
        expect(rendered[0]).toEqual(tierAccessDeniedMessages[0]);
        expect(rendered[1]).toEqual({
          ...tierAccessDeniedMessages[1],
          role: 'tool',
          message_type: 'tool',
        });
      });

      it('on self-managed, leaves tier_access_denied messages untouched so they render as the original message', () => {
        createComponent({ propsData: { messages: tierAccessDeniedMessages, isSaas: false } });

        const rendered = findChatConversations().at(0).props('messages');
        expect(rendered[1]).toEqual(tierAccessDeniedMessages[1]);
      });

      it('correctly passes payload when "insert-code-snippet" event is emitted from a conversation', () => {
        createComponent({ propsData: { messages } });

        findChatConversations().at(0).vm.$emit('insert-code-snippet', 'foo');
        expect(wrapper.emitted('insert-code-snippet')[0]).toEqual(['foo']);
      });

      it('correctly passes payload when "copy-code-snippet" event is emitted from a conversation', () => {
        createComponent({ propsData: { messages } });

        findChatConversations().at(0).vm.$emit('copy-code-snippet', 'foo');
        expect(wrapper.emitted('copy-code-snippet')[0]).toEqual(['foo']);
      });

      it('correctly passes payload when "copy-message" event is emitted from a conversation', () => {
        createComponent({ propsData: { messages } });

        findChatConversations().at(0).vm.$emit('copy-message', 'foo');
        expect(wrapper.emitted('copy-message')[0]).toEqual(['foo']);
      });

      it('correctly passes payload when "question-answered" event is emitted from a conversation', () => {
        createComponent({ propsData: { messages } });

        findChatConversations()
          .at(0)
          .vm.$emit('question-answered', { optionId: 'option-a', messageId: 'msg-1' });
        expect(wrapper.emitted('question-answered')[0]).toEqual([
          { optionId: 'option-a', messageId: 'msg-1' },
        ]);
      });

      describe('isRetryEnabled prop', () => {
        it('defaults to false on the conversation', () => {
          createComponent({ propsData: { messages } });
          expect(findChatConversations().at(0).props('isRetryEnabled')).toBe(false);
        });

        it('forwards isRetryEnabled=true to the conversation', () => {
          createComponent({ propsData: { messages, isRetryEnabled: true } });
          expect(findChatConversations().at(0).props('isRetryEnabled')).toBe(true);
        });

        it('re-emits "retry-message" with the payload when emitted from a conversation', () => {
          createComponent({ propsData: { messages, isRetryEnabled: true } });
          const payload = { id: 'assistant-1', requestId: 'req-1' };

          findChatConversations().at(0).vm.$emit('retry-message', payload);

          expect(wrapper.emitted('retry-message')).toHaveLength(1);
          expect(wrapper.emitted('retry-message')[0]).toEqual([payload]);
        });
      });

      it('passes trustedUrls prop to conversation', () => {
        const trustedUrls = ['gitlab.com', 'example.com'];
        createComponent({
          propsData: {
            messages,
            trustedUrls,
          },
        });

        expect(findChatConversations().at(0).props('trustedUrls')).toEqual(trustedUrls);
      });
    });

    describe('emptyStateTitle', () => {
      it.each`
        agentName          | emptyStateTitle   | expectedTitle
        ${null}            | ${undefined}      | ${'I am GitLab Duo Agentic Chat, your personal AI-powered assistant.'}
        ${null}            | ${'custom title'} | ${'custom title'}
        ${'awesome agent'} | ${undefined}      | ${'I am GitLab Duo Agentic Chat, your personal AI-powered assistant.'}
      `(
        'displays "$expectedTitle" when emptyStateTitle is "$emptyStateTitle" and agentName is "$agentName"',
        ({ agentName, emptyStateTitle, expectedTitle }) => {
          createComponent({ propsData: { emptyStateTitle, agentName } });
          expect(findEmptyStateTitle().text()).toBe(expectedTitle);
        },
      );
    });

    describe('custom empty state slot', () => {
      describe('when slot is not provided', () => {
        it('renders default empty state', () => {
          createComponent({ propsData: { messages: [] } });
          expect(findEmptyState().exists()).toBe(true);
          expect(findEmptyStateTitle().exists()).toBe(true);
        });
      });

      describe('when slot is provided', () => {
        it('renders custom content', () => {
          createComponent({
            propsData: { messages: [] },
            slots: {
              'custom-empty-state': '<div data-testid="custom-empty">No credits</div>',
            },
          });
          expect(wrapper.find('[data-testid="custom-empty"]').exists()).toBe(true);
          expect(wrapper.find('[data-testid="custom-empty"]').text()).toBe('No credits');
        });
      });
    });

    describe('footer', () => {
      it('renders the footer', () => {
        createComponent();

        expect(findFooter().exists()).toBe(true);
      });
    });

    describe('disclaimer', () => {
      it.each`
        testMessages                                                                                                       | shouldBeVisible
        ${[]}                                                                                                              | ${false}
        ${[{ role: MESSAGE_MODEL_ROLES.user, content: 'Hello' }]}                                                          | ${false}
        ${[{ role: MESSAGE_MODEL_ROLES.assistant, content: 'Hi!' }]}                                                       | ${true}
        ${[{ role: MESSAGE_MODEL_ROLES.user, content: 'Hello' }, { role: MESSAGE_MODEL_ROLES.assistant, content: 'Hi!' }]} | ${true}
      `(
        'visibility matches expected state when shouldBeVisible is $shouldBeVisible',
        ({ testMessages, shouldBeVisible }) => {
          createComponent({ propsData: { messages: testMessages } });

          expect(findDisclaimer().exists()).toBe(true);
          if (shouldBeVisible) {
            expect(findDisclaimer().classes()).not.toContain('gl-hidden');
            expect(findDisclaimer().text()).toBe('Responses may be inaccurate. Verify before use.');
          } else {
            expect(findDisclaimer().classes()).toContain('gl-hidden');
          }
        },
      );
    });

    describe('isBinaryFeedbackEnabled prop', () => {
      it('passes isBinaryFeedbackEnabled prop to conversation component', () => {
        createComponent({
          propsData: {
            messages: [{ role: MESSAGE_MODEL_ROLES.assistant, content: 'Hi!' }],
            isBinaryFeedbackEnabled: true,
          },
        });
        expect(findChatConversations().at(0).props('isBinaryFeedbackEnabled')).toBe(true);
      });
    });

    describe('session pills bar', () => {
      const assistantMessages = [{ role: MESSAGE_MODEL_ROLES.assistant, content: 'Hi!' }];

      it('renders the session pills bar', () => {
        createComponent({ propsData: { messages: assistantMessages } });

        expect(findSessionPillsBar().exists()).toBe(true);
        expect(findSessionPillsBar().props('messages')).toBe(assistantMessages);
      });

      const siblingIndex = (el) => Array.from(el.parentNode.children).indexOf(el);

      it('renders the disclaimer below the form', () => {
        createComponent({ propsData: { messages: assistantMessages } });

        expect(siblingIndex(findDisclaimer().element)).toBeGreaterThan(
          siblingIndex(findPromptComposer().element),
        );
      });
    });
  });

  describe('scroll region integration', () => {
    it('hands the scroll region the last message, so it can drive the turn', () => {
      createComponent({ propsData: { messages } });

      expect(findScrollRegion().props('lastMessage')).toEqual(messages[0]);
    });

    describe('message list layout', () => {
      const withEmptyStateSlot = (propsData) =>
        createComponent({
          propsData,
          slots: { 'custom-empty-state': '<div>No credits</div>' },
        });

      it('centers the message list while a custom empty state is all there is', () => {
        withEmptyStateSlot({ messages: [] });

        expect(findScrollRegion().props('contentClass')).toBe('gl-m-auto');
      });

      it('bottom-aligns the message list once messages arrive', () => {
        withEmptyStateSlot({ messages: [{ role: 'user', content: 'test' }] });

        expect(findScrollRegion().props('contentClass')).toContain('gl-mt-auto');
      });

      it('bottom-aligns the message list when there is no custom empty state', () => {
        createComponent({ propsData: { messages: [] } });

        expect(findScrollRegion().props('contentClass')).toContain('gl-mt-auto');
      });

      it('top-anchors the message list under the redesign, so requests pin to the top', () => {
        createComponent({
          propsData: { messages: [] },
          provide: { glFeatures: { duoChatRedesign: true } },
        });

        expect(findScrollRegion().props('contentClass')).not.toContain('gl-mt-auto');
      });
    });

    describe('message transition', () => {
      it('slides new messages in by default', () => {
        createComponent({ propsData: { messages: [] } });

        expect(findScrollRegion().props('transitionName')).toBe('message');
      });

      // The slide-in translateY would offset the position a pinned request is
      // measured against.
      it('drops the transition when a custom empty state fills the panel', () => {
        createComponent({
          propsData: { messages: [] },
          slots: { 'custom-empty-state': '<div>No credits</div>' },
        });

        expect(findScrollRegion().props('transitionName')).toBe('');
      });

      it('drops the transition when requests pin to the top', () => {
        createComponent({
          propsData: { messages: [] },
          provide: { glFeatures: { duoChatRedesign: true } },
        });

        expect(findScrollRegion().props('transitionName')).toBe('');
      });
    });

    it('asks the scroll region to re-pin when the footer resizes under it', () => {
      createComponent({ propsData: { messages } });

      findSessionPillsBar().vm.$emit('height-change');

      expect(mockRePinIfAtBottom).toHaveBeenCalledTimes(1);
    });
  });

  describe('PromptComposer integration', () => {
    it('passes correct props to PromptComposer', () => {
      const chatState = { isEnabled: true, reason: null };
      createComponent({
        propsData: {
          chatState,
          isChatAvailable: false,
          isLoading: true,
          messages: [MOCK_RESPONSE_MESSAGE],
          chatPromptPlaceholder: 'Type here...',
        },
      });

      const promptTextarea = findPromptComposer();
      expect(promptTextarea.props('chatState')).toEqual(chatState);
      expect(promptTextarea.props('isChatAvailable')).toBe(false);
      expect(promptTextarea.props('isLoading')).toBe(true);
      expect(promptTextarea.props('lastMessage')).toEqual(MOCK_RESPONSE_MESSAGE);
      expect(promptTextarea.props('chatPromptPlaceholder')).toBe('Type here...');
    });

    it('re-emits send-chat-prompt when PromptComposer emits it', () => {
      createComponent();

      findPromptComposer().vm.$emit('send-chat-prompt', 'hello world');

      expect(wrapper.emitted('send-chat-prompt')).toHaveLength(1);
      expect(wrapper.emitted('send-chat-prompt')[0]).toEqual(['hello world']);
    });

    it('re-emits the prompt whole, so its attachments travel with it', () => {
      createComponent();
      const prompt = { text: 'hello world', attachments: [{ id: 'a-1', filename: 'a.png' }] };

      findPromptComposer().vm.$emit('send-chat-prompt', prompt);

      expect(wrapper.emitted('send-chat-prompt')[0]).toEqual([prompt]);
    });

    it('re-emits chat-cancel when PromptComposer emits it', () => {
      createComponent();

      findPromptComposer().vm.$emit('chat-cancel');

      expect(wrapper.emitted('chat-cancel')).toHaveLength(1);
    });
  });

  describe('chat', () => {
    describe('withFeedback prop', () => {
      it('provides withFeedback as true by default', () => {
        createComponent({
          messages,
          isChatAvailable: true,
        });
        expect(wrapper.vm.withFeedback).toBe(true);
      });

      it('provides the value of withFeedback prop when specified', () => {
        createComponent({
          propsData: {
            messages,
            isChatAvailable: true,
            withFeedback: false,
          },
        });
        expect(findChatConversations().at(0).props('withFeedback')).toBe(false);
      });
    });
  });

  describe('interaction', () => {
    // The view no longer knows what progress looks like: it offers the slot, and the
    // caller decides which indicator belongs there.
    describe('turn-progress slot', () => {
      const findSlotWrapper = () => wrapper.find('[data-testid="turn-progress"]');

      it("renders the caller's progress report inside the conversation", () => {
        createComponent({
          slots: { 'turn-progress': '<div data-testid="caller-progress">Working</div>' },
        });

        expect(findScrollRegion().find('[data-testid="caller-progress"]').exists()).toBe(true);
      });

      // The wrapper is what carries the key transition-group needs, so it has to be a
      // real element even when whatever fills the slot decides to render nothing.
      it('wraps the slot in an element of its own', () => {
        // Mirrors TurnProgress when there is nothing to report: the slot is filled, but
        // what fills it renders no element.
        createComponent({
          slots: { 'turn-progress': { name: 'NothingToReport', render: () => null } },
        });

        expect(findSlotWrapper().exists()).toBe(true);
      });

      it('adds nothing to the conversation when the caller ignores the slot', () => {
        createComponent();

        expect(findSlotWrapper().exists()).toBe(false);
        expect(wrapper.find('[data-testid="caller-progress"]').exists()).toBe(false);
      });
    });

    it('does not render the empty state when there are messages available', () => {
      createComponent({ propsData: { messages } });
      expect(findEmptyState().exists()).toBe(false);
    });

    describe('predefined prompts', () => {
      const prompts = ['what is a fork'];

      beforeEach(() => {
        createComponent({ propsData: { predefinedPrompts: prompts } });
      });

      it('passes on predefined prompts', () => {
        expect(findPredefined().props().prompts).toEqual(prompts);
      });

      it('listens to the click event and calls sendPredefinedPrompt on promptComposer ref', async () => {
        findPredefined().vm.$emit('click', prompts[0]);

        await nextTick();

        expect(mockSendPredefinedPrompt).toHaveBeenCalledWith(prompts[0]);
      });

      describe('tracking', () => {
        const { bindInternalEventDocument } = useMockInternalEventsTracking();

        it('tracks the clicked prompt with the agent name', () => {
          createComponent({
            propsData: { predefinedPrompts: prompts, trackingAgentName: 'Data Analyst' },
          });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          findPredefined().vm.$emit('click', prompts[0]);

          expect(trackEventSpy).toHaveBeenCalledWith(
            'select_duo_agentic_chat_predefined_prompt',
            { label: 'what is a fork', property: 'Data Analyst' },
            undefined,
          );
        });

        it('reports the tracking label for the prompt instead of the displayed text', () => {
          createComponent({
            propsData: {
              predefinedPrompts: ['Summarize activity in capsule-corp'],
              predefinedPromptTrackingLabels: ['Summarize activity in %{namespace}'],
              trackingAgentName: 'Data Analyst',
            },
          });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          findPredefined().vm.$emit('click', 'Summarize activity in capsule-corp');

          expect(trackEventSpy).toHaveBeenCalledWith(
            'select_duo_agentic_chat_predefined_prompt',
            {
              label: 'Summarize activity in %{namespace}',
              property: 'Data Analyst',
            },
            undefined,
          );
        });

        it('reports an empty property instead of the localized title without an agent', () => {
          createComponent({ propsData: { predefinedPrompts: prompts, title: 'GitLab Duo' } });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          findPredefined().vm.$emit('click', prompts[0]);

          expect(trackEventSpy).toHaveBeenCalledWith(
            'select_duo_agentic_chat_predefined_prompt',
            { label: 'what is a fork', property: '' },
            undefined,
          );
        });
      });
    });
  });
});
