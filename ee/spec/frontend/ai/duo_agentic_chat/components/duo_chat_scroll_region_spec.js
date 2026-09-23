import { nextTick } from 'vue';
import { DuoChatContextConversation as DuoChatConversation } from '@gitlab/duo-ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeRequestAnimationFrame } from 'helpers/fake_request_animation_frame';
import waitForPromises from 'helpers/wait_for_promises';
import DuoChatScrollRegion from 'ee/ai/duo_agentic_chat/components/duo_chat_scroll_region.vue';
import { MOCK_RESPONSE_MESSAGE, MOCK_USER_PROMPT_MESSAGE } from '../../tanuki_bot/mock_data';

describe('DuoChatScrollRegion', () => {
  let wrapper;
  let container;
  let scrollIntoViewMock;

  const createComponent = ({ propsData = {}, duoChatRedesign = true, slots = {} } = {}) =>
    mountExtended(DuoChatScrollRegion, {
      propsData,
      provide: { glFeatures: { duoChatRedesign } },
      slots: {
        header: '<div data-testid="header-slot">header</div>',
        default: '<div key="slotted-message">a message</div>',
        ...slots,
      },
    });

  const findScrollContainer = () => wrapper.find('[data-testid="chat-history"]');
  const findMessages = () => wrapper.find('[data-testid="chat-messages"]');
  const findContentEnd = () => wrapper.find('[data-testid="content-end"]');
  const findScrollToBottomButton = () => wrapper.findByTestId('scroll-to-bottom-button');

  // The turn floor is a min-height the browser resolves against the live window.
  // jsdom does no layout, so the style string is the whole observable.
  const turnFloor = () => findMessages().element.style.minHeight;

  // Drains the whole await chain behind a turn: the watcher, the scroll helpers'
  // ticks, and Vue's patch of the floor style.
  const settleScroll = () => waitForPromises();

  // Places the end-of-conversation marker at a fixed position in the scroll
  // container's coordinates, which is what the component measures against.
  const setContentEnd = (offset) => {
    jest
      .spyOn(findContentEnd().element, 'getBoundingClientRect')
      .mockImplementation(() => ({ top: offset - container.scrollTop }));
  };

  // Geometry: a 400px-tall window over `contentHeight` of content, as the browser
  // reports it. The floor only ever adds blank room below the conversation, so it
  // does not change where the content ends.
  const mockGeometry = (contentHeight = 500) => {
    container = findScrollContainer().element;
    jest.spyOn(container, 'clientHeight', 'get').mockReturnValue(400);
    jest.spyOn(container, 'scrollHeight', 'get').mockReturnValue(contentHeight);
    jest.spyOn(container, 'getBoundingClientRect').mockReturnValue({ top: 0 });
    setContentEnd(contentHeight);
  };

  // Stands in for the `.duo-chat-message-container` that @gitlab/duo-ui renders per
  // message, which is how the pin locates a turn boundary.
  const appendMessageNode = (top) => {
    const node = document.createElement('div');
    node.classList.add('duo-chat-message-container');
    jest.spyOn(node, 'getBoundingClientRect').mockReturnValue({ top });
    findMessages().element.appendChild(node);
  };

  const receiveMessage = async (message) => {
    wrapper.setProps({ lastMessage: message });
    await settleScroll();
  };

  beforeEach(() => {
    scrollIntoViewMock = jest.fn();
    window.HTMLElement.prototype.scrollIntoView = scrollIntoViewMock;
  });

  describe('rendering', () => {
    it('renders the header slot outside the message list', () => {
      wrapper = createComponent();

      expect(wrapper.findByTestId('header-slot').exists()).toBe(true);
      expect(findMessages().element.querySelector('[data-testid="header-slot"]')).toBe(null);
    });

    it('renders the default slot inside the message list', () => {
      wrapper = createComponent();

      expect(findMessages().text()).toContain('a message');
    });

    it('applies the layout classes it is given to the message list', () => {
      wrapper = createComponent({ propsData: { contentClass: 'gl-mt-auto' } });

      expect(findMessages().classes()).toContain('gl-mt-auto');
    });

    it('names the message transition as it is told', () => {
      wrapper = createComponent({ propsData: { transitionName: 'message' } });

      expect(findMessages().attributes('name')).toBe('message');
    });

    it('scrolls to the bottom on load', async () => {
      wrapper = createComponent({ propsData: { lastMessage: MOCK_USER_PROMPT_MESSAGE } });

      await nextTick();

      expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
    });
  });

  describe('when turn-based scrolling is disabled', () => {
    // The turn already on screen when these tests start. A message the tests
    // then receive has to be a different object, or the watcher sees no change.
    const earlierMessage = { role: 'user', content: 'an earlier question' };

    const setupScrolledToBottom = () => {
      jest.spyOn(container, 'scrollTop', 'get').mockReturnValue(100);
      jest.spyOn(container, 'offsetHeight', 'get').mockReturnValue(100);
      jest.spyOn(container, 'scrollHeight', 'get').mockReturnValue(200);
    };

    const setupScrolledUp = () => {
      jest.spyOn(container, 'scrollTop', 'get').mockReturnValue(50);
      jest.spyOn(container, 'offsetHeight', 'get').mockReturnValue(100);
      jest.spyOn(container, 'scrollHeight', 'get').mockReturnValue(200);
    };

    beforeEach(() => {
      wrapper = createComponent({
        duoChatRedesign: false,
        propsData: { lastMessage: earlierMessage },
      });
      container = findScrollContainer().element;
    });

    it('keeps the default border-on-scroll treatment', () => {
      expect(findScrollContainer().classes()).not.toContain('duo-chat-scroll-scrims');
    });

    it('applies no turn floor', () => {
      expect(turnFloor()).toBe('');
    });

    describe('when the user is pinned to the bottom', () => {
      beforeEach(() => {
        setupScrolledToBottom();
        scrollIntoViewMock.mockClear();

        findScrollContainer().trigger('scroll');
        return nextTick();
      });

      it('does not scroll chat to bottom on the scroll event alone', () => {
        expect(scrollIntoViewMock).toHaveBeenCalledTimes(0);
      });

      it('never offers the scroll-to-bottom button', () => {
        expect(findScrollToBottomButton().exists()).toBe(false);
      });

      describe('when a new message is received', () => {
        beforeEach(() => receiveMessage(MOCK_USER_PROMPT_MESSAGE));

        it('scrolls chat to bottom', () => {
          expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the footer resizes', () => {
        beforeEach(async () => {
          wrapper.vm.rePinIfAtBottom();
          await settleScroll();
        });

        it('re-pins chat to bottom', () => {
          expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe('when the user has explicitly scrolled up', () => {
      beforeEach(() => {
        setupScrolledUp();
        scrollIntoViewMock.mockClear();

        findScrollContainer().trigger('scroll');
        return nextTick();
      });

      it('does not scroll chat to bottom on the scroll event alone', () => {
        expect(scrollIntoViewMock).toHaveBeenCalledTimes(0);
      });

      describe('when a new assistant message is received', () => {
        beforeEach(() => receiveMessage(MOCK_RESPONSE_MESSAGE));

        it('does not scroll chat to bottom', () => {
          expect(scrollIntoViewMock).toHaveBeenCalledTimes(0);
        });
      });

      describe('when a new user message is received', () => {
        beforeEach(() => receiveMessage(MOCK_USER_PROMPT_MESSAGE));

        it('scrolls chat to bottom', () => {
          expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the footer resizes', () => {
        beforeEach(async () => {
          wrapper.vm.rePinIfAtBottom();
          await settleScroll();
        });

        it('does not re-pin chat to bottom', () => {
          expect(scrollIntoViewMock).toHaveBeenCalledTimes(0);
        });
      });
    });
  });

  describe('when turn-based scrolling is enabled', () => {
    const toolApprovalMessage = {
      role: 'assistant',
      message_type: 'request',
      tool_info: { name: 'run_command' },
      content: '',
    };

    // The pin settles across animation frames, so they have to run for the
    // await chain behind a turn to resolve at all.
    useFakeRequestAnimationFrame();

    beforeEach(async () => {
      wrapper = createComponent();
      await nextTick();
      mockGeometry();
      scrollIntoViewMock.mockClear();
    });

    it('swaps the border-on-scroll strip for scroll-edge scrims', () => {
      expect(findScrollContainer().classes()).toContain('duo-chat-scroll-scrims');
    });

    it('suppresses native scroll anchoring on the scroll container', () => {
      expect(findScrollContainer().classes()).toContain('[overflow-anchor:none]');
    });

    it('disables the message slide-in transition', () => {
      expect(findMessages().attributes('css')).toBeUndefined();
    });

    // The turn floor is a min-height, which overrides the automatic minimum size
    // that otherwise stops a flex item shrinking under its own content. Without
    // this the list shrinks to the floor and its padding strands mid-conversation.
    it('stops the message list shrinking under its content', () => {
      expect(findMessages().classes()).toContain('gl-shrink-0');
    });

    describe('when the user sends a request', () => {
      beforeEach(async () => {
        // The just-sent request, rendered 300px down.
        appendMessageNode(300);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      });

      it('pins the request to the top of the window', () => {
        // 300px offset minus the 32px scrim-height gap.
        expect(container.scrollTop).toBe(268);
      });

      it('floors the list one window below the pin so a short turn can reach it', () => {
        // The list starts at the container's own top here, so the floor carries
        // the whole 268px pin offset.
        expect(turnFloor()).toBe('calc(100% + 268px)');
      });

      it('leaves the geometry alone as the response streams in', async () => {
        jest.spyOn(container, 'scrollHeight', 'get').mockReturnValue(600);
        setContentEnd(600);

        await receiveMessage(MOCK_RESPONSE_MESSAGE);

        // The floor is what holds the scroll height, so a streamed chunk moves
        // nothing: no re-measure, no re-size, no scroll.
        expect(turnFloor()).toBe('calc(100% + 268px)');
        expect(container.scrollTop).toBe(268);
        expect(scrollIntoViewMock).not.toHaveBeenCalled();
        // 600px of content against a 268px pin and a 400px window: the
        // conversation still ends above the fold.
        expect(findScrollToBottomButton().exists()).toBe(false);
      });

      it('scrolls to the bottom when a tool approval appears', async () => {
        await receiveMessage(toolApprovalMessage);

        expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        expect(scrollIntoViewMock.mock.contexts[0].classList).toContain('scroll-anchor');
      });

      it('does not re-scroll while the tool approval stays pending', async () => {
        await receiveMessage(toolApprovalMessage);
        scrollIntoViewMock.mockClear();

        await receiveMessage({ ...toolApprovalMessage });

        expect(scrollIntoViewMock).not.toHaveBeenCalled();
      });

      it('resets the turn scroll state when the chat clears', async () => {
        await receiveMessage(null);

        expect(turnFloor()).toBe('');
      });
    });

    describe('when the first request pins flush to the top', () => {
      beforeEach(async () => {
        // A short turn: 300px of content in a 400px window.
        mockGeometry(300);
        // Rendered above the top gap, so the pinned position clamps to zero.
        appendMessageNode(20);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      });

      it('pins the request to the very top', () => {
        expect(container.scrollTop).toBe(0);
      });

      it('floors the list at exactly one window, so the panel cannot scroll', () => {
        // Nothing is pinned above the request, so the floor adds no offset and the
        // list is exactly as tall as the window: no scrollbar over blank room.
        expect(turnFloor()).toBe('100%');
      });
    });

    describe('when the composer collapses as the request is sent', () => {
      beforeEach(async () => {
        // GlFormTextarea's auto-height clears the sent prompt a frame after the
        // request lands, which grows the window the pin was measured against.
        jest.spyOn(container, 'clientHeight', 'get').mockReturnValueOnce(400).mockReturnValue(700);
        appendMessageNode(300);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      });

      it('needs no re-measure, because the floor is a percentage', () => {
        // A pixel floor sized against the pre-collapse 400px window would leave
        // the pinned position past the scroll limit once the window grew to
        // 700px. `100%` re-resolves against the settled window on its own.
        expect(turnFloor()).toBe('calc(100% + 268px)');
      });

      it('keeps the request pinned to the top', () => {
        expect(container.scrollTop).toBe(268);
      });
    });

    describe('when the request follows an earlier response', () => {
      const sendFollowUpRequest = async () => {
        await receiveMessage(MOCK_RESPONSE_MESSAGE);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      };

      it('pins the request short of the top so the response tail stays visible', async () => {
        appendMessageNode(100); // the previous response
        appendMessageNode(300); // the just-sent request
        await sendFollowUpRequest();

        // 300px offset minus the 32px scrim-height gap and the 64px peek.
        expect(container.scrollTop).toBe(204);
      });

      it('never reveals more than the whole previous response', async () => {
        appendMessageNode(280); // a short previous response
        appendMessageNode(300); // the just-sent request
        await sendFollowUpRequest();

        // Clamped to the response's 280px offset minus the 32px gap.
        expect(container.scrollTop).toBe(248);
      });
    });

    it('scrolls a bulk-loaded thread to the bottom without flooring the list', async () => {
      await receiveMessage(MOCK_RESPONSE_MESSAGE);

      expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
      expect(scrollIntoViewMock.mock.contexts[0].classList).toContain('scroll-anchor');
      expect(turnFloor()).toBe('');
    });

    describe('when the conversation renders no turn boundary', () => {
      // @gitlab/duo-ui does not export the markup the pin looks for, so a DOM
      // change upstream must degrade to a plain scroll-to-bottom, not throw.
      it('scrolls to the bottom instead of pinning', async () => {
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);

        expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        expect(scrollIntoViewMock.mock.contexts[0].classList).toContain('scroll-anchor');
      });

      it('floors nothing', async () => {
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);

        expect(turnFloor()).toBe('');
      });
    });

    describe('when the browser refuses to honour the pinned position', () => {
      beforeEach(async () => {
        // A container that clamps every scroll, as one still settling does.
        Object.defineProperty(container, 'scrollTop', {
          configurable: true,
          get: () => 0,
          set: () => {},
        });
        appendMessageNode(300);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      });

      it('gives up rather than re-measuring forever', () => {
        expect(container.scrollTop).toBe(0);
      });

      it('still floors the list for the turn', () => {
        expect(turnFloor()).not.toBe('');
      });
    });

    // The empty state renders in the same slot as the conversation and can be
    // taller than the window on its own, with nothing to scroll down to.
    describe('when there is no conversation yet', () => {
      beforeEach(async () => {
        jest
          .spyOn(container, 'scrollHeight', 'get')
          .mockImplementation(() => container.scrollTop + 800);

        findScrollContainer().trigger('scroll');
        await settleScroll();
      });

      it('never offers the scroll-to-bottom button', () => {
        expect(findScrollToBottomButton().exists()).toBe(false);
      });
    });

    describe('scroll-to-bottom button', () => {
      beforeEach(async () => {
        appendMessageNode(300);
        await receiveMessage(MOCK_USER_PROMPT_MESSAGE);
      });

      it('stays hidden while everything below the viewport is the turn floor', () => {
        expect(findScrollToBottomButton().exists()).toBe(false);
      });

      // The button appears on conversation below the fold, so the reveal threshold
      // is what keeps a hairline of overflow from flickering it into view.
      const setOverflowBelowViewport = async (pixels) => {
        setContentEnd(container.scrollTop + 400 + pixels);
        findScrollContainer().trigger('scroll');
        await settleScroll();
      };

      it('stays hidden while the overflow is within the reveal threshold', async () => {
        await setOverflowBelowViewport(24);

        expect(findScrollToBottomButton().exists()).toBe(false);
      });

      it('appears once the overflow passes the reveal threshold', async () => {
        await setOverflowBelowViewport(25);

        expect(findScrollToBottomButton().exists()).toBe(true);
      });

      describe('when the response grows past the viewport', () => {
        beforeEach(async () => {
          jest.spyOn(container, 'scrollHeight', 'get').mockReturnValue(900);
          setContentEnd(900);

          await receiveMessage(MOCK_RESPONSE_MESSAGE);
        });

        it('offers the button', () => {
          expect(findScrollToBottomButton().exists()).toBe(true);
        });

        it('scrolls to the end of the conversation, not the turn floor, when pressed', () => {
          container.scrollTo = jest.fn();

          findScrollToBottomButton().trigger('click');

          expect(container.scrollTo).toHaveBeenCalledWith({ top: 500, behavior: 'smooth' });
        });

        it('does nothing where the browser has no smooth scrolling', () => {
          delete container.scrollTo;

          expect(() => findScrollToBottomButton().trigger('click')).not.toThrow();
        });

        it('withdraws the button once scrolled to the bottom of the content', async () => {
          container.scrollTop = 500;
          findScrollContainer().trigger('scroll');
          await nextTick();

          expect(findScrollToBottomButton().exists()).toBe(false);
        });
      });
    });

    // The pin locates turn boundaries via a class and test id that @gitlab/duo-ui
    // renders but does not export, so a DOM change there would silently degrade it
    // to a plain scroll-to-bottom.
    describe('turn boundary markup contract', () => {
      const toolMessage = {
        role: 'assistant',
        message_type: 'tool',
        content: 'ran a tool',
      };
      const conversation = [MOCK_USER_PROMPT_MESSAGE, toolMessage, MOCK_RESPONSE_MESSAGE];

      const mountWithRealConversation = async () => {
        wrapper = mountExtended(DuoChatScrollRegion, {
          provide: { glFeatures: { duoChatRedesign: true } },
          slots: {
            default: {
              name: 'RealConversation',
              components: { DuoChatConversation },
              template: `<duo-chat-conversation
                key="conversation"
                :messages="messages"
                :enable-code-insertion="false"
              />`,
              data() {
                return { messages: conversation };
              },
            },
          },
        });
        await waitForPromises();
      };

      it('renders a message container per message', async () => {
        await mountWithRealConversation();

        // One per message, the grouped tool message included: its container is
        // nested inside the tool group rather than replaced by it.
        expect(findMessages().element.querySelectorAll('.duo-chat-message-container')).toHaveLength(
          conversation.length,
        );
      });

      it('renders a tool group wrapper per run of tool messages', async () => {
        await mountWithRealConversation();

        expect(findMessages().element.querySelectorAll('[data-testid="tool-group"]')).toHaveLength(
          1,
        );
      });

      it('pins a new request instead of falling back to scroll-to-bottom', async () => {
        await mountWithRealConversation();
        scrollIntoViewMock.mockClear();

        await wrapper.setProps({ lastMessage: MOCK_USER_PROMPT_MESSAGE });
        await waitForPromises();

        expect(scrollIntoViewMock).not.toHaveBeenCalled();
      });
    });
  });
});
