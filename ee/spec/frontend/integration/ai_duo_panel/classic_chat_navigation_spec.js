import { waitFor } from '@testing-library/vue';
import { CHAT_MODES } from 'ee/ai/state';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  buildClassicChatConfiguration,
  findChatComponent,
  findEmptyState,
  findMessages,
  findHistoryToggle,
  findThreadBoxWithText,
  isShowingClassicChatView,
  isShowingClassicListView,
  mountAISidebar,
  panelHeadingText,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';
import {
  getAiConversationThreads,
  getAiMessagesWithThread,
  aiMessagesWithThreadVariants,
  installDuoAIPanelHandlers,
} from './test_support/api_handlers';

const chatConfiguration = buildClassicChatConfiguration();

// Only a titled thread is clickable by name in the history list. Its messages come
// from the `getAiMessagesWithThread` BASE fixture; the EMPTY variant below is the
// same thread coming back with no exchange yet.
const threadWithMessages = getAiConversationThreads
  .threads()
  .find((thread) => thread.title !== null);
const assistantMessage = getAiMessagesWithThread
  .messages()
  .find((message) => message.role === 'ASSISTANT');

describe('Duo classic chat panel navigation and reload-from-history', () => {
  let wrapper;

  // Joined rather than checked per-element so a failure prints the conversation
  // that did render.
  const renderedMessagesText = () => [...findMessages()].map(getText).join('\n');

  // The classic DuoChat state manager declares a String userId; without one Vue
  // logs a prop-type warning on every re-render.
  const mountPanel = () => {
    wrapper = mountAISidebar({
      chatConfiguration,
      propsData: { userId: 'gid://gitlab/User/1' },
    });
  };

  beforeEach(() => {
    setupDuoChatTest({ chatMode: CHAT_MODES.CLASSIC });
    installDuoAIPanelHandlers();
  });

  afterEach(() => {
    // Destroys the mounted wrappers too, so `simulateReload` is the only place
    // this spec has to destroy one itself.
    teardownDuoChatTest();
  });

  // Reload = tear down the DOM and re-create the router. The persisted
  // sessionStorage (history stack + last route) survives, so a fresh
  // `createRouter` replays it via `restoreLastRoute` exactly as a page
  // reload would.
  const simulateReload = () => {
    wrapper.destroy();
    document.body.innerHTML = '';
    mountPanel();
  };

  // Drives history-list -> open-thread and waits until the chat view is shown.
  const openThreadFromHistory = async () => {
    mountPanel();

    await waitAndClick(findHistoryToggle);
    await waitAndClick(() => findThreadBoxWithText(threadWithMessages.title));

    await waitFor(() => {
      expect(isShowingClassicChatView()).toBe(true);
    });
  };

  describe('reloading while a conversation is open', () => {
    beforeEach(async () => {
      await openThreadFromHistory();
      simulateReload();
      await waitForElement(findChatComponent);
    });

    it('restores the conversation, not the history list', async () => {
      // Route and view must agree after replay, and the conversation itself
      // comes back: the restored assistant message renders in the body. The
      // thread id now travels in the route, so it survives the heap wipe.
      await waitFor(() => {
        expect(isShowingClassicChatView()).toBe(true);
        expect(isShowingClassicListView()).toBe(false);
        expect(renderedMessagesText()).toContain(assistantMessage.content);
      });
    });

    it('shows the classic chat heading, not the history heading', async () => {
      // The classic surface derives its heading from the route: the show route
      // reads the classic chat title, never "History". (Unlike agent sessions,
      // classic chat does not surface a per-conversation title.)
      await waitFor(() => {
        expect(isShowingClassicChatView()).toBe(true);
        expect(panelHeadingText()).toBe(chatConfiguration.classicTitle);
      });
    });

    it('reads "History" on the heading after returning to the list', async () => {
      await waitFor(() => {
        expect(isShowingClassicChatView()).toBe(true);
      });

      await waitAndClick(findHistoryToggle);

      // On the history route the heading must be the route-derived "History",
      // proving the reload did not leave the conversation view pinned.
      await waitFor(() => {
        expect(isShowingClassicListView()).toBe(true);
        expect(panelHeadingText()).toBe('History');
      });
    });
  });

  describe('opening a thread that holds no exchange yet', () => {
    beforeEach(() => {
      setQueryVariant(aiMessagesWithThreadVariants).empty();
    });

    it('shows the chat empty state instead of the recorded exchange', async () => {
      await openThreadFromHistory();

      // The empty state carries the same `.duo-chat-message` class as a real
      // message, so assert on it directly rather than on a message count.
      await waitForElement(findEmptyState);

      await waitFor(() => {
        expect(isShowingClassicChatView()).toBe(true);
        expect(renderedMessagesText()).not.toContain(assistantMessage.content);
      });
    });
  });

  describe('back-to-list from a conversation', () => {
    it('keeps the route and view in sync on the history route', async () => {
      await openThreadFromHistory();

      await waitAndClick(findHistoryToggle);

      // Route (history) and view (LIST) agree: the thread list is shown, the
      // conversation footer is gone, and the heading reads "History".
      await waitFor(() => {
        expect(isShowingClassicListView()).toBe(true);
        expect(isShowingClassicChatView()).toBe(false);
        expect(panelHeadingText()).toBe('History');
      });
    });
  });
});
