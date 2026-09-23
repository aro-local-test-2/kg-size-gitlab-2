import { waitFor } from '@testing-library/vue';
import {
  buildChatConfiguration,
  findChatSubheader,
  findSubmitButton,
  mountAISidebar,
  panelHeadingText,
  panelSubheadingText,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';
import { installDuoAIPanelHandlers } from './test_support/api_handlers';
import { waitForSocket } from './test_support/websocket_mock';

const GOAL = 'Summarize this project';

describe('Duo Agentic Chat | the redesigned single panel header', () => {
  // Without `autoExpand` the router starts on the closed route and no chat
  // body renders, so there is no header to assert against.
  const mountPanel = (duoChatRedesign) =>
    mountAISidebar({
      chatConfiguration: buildChatConfiguration({ autoExpand: true }),
      provide: { glFeatures: { duoChatRedesign } },
    });

  // The composer stays disabled until the initial queries resolve.
  const waitForChat = () =>
    waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  describe('with the redesign enabled', () => {
    beforeEach(async () => {
      mountPanel(true);
      await waitForChat();
    });

    it('names the chat in the panel header rather than in the chat body', () => {
      expect(panelHeadingText()).toBe('New chat');
      expect(panelSubheadingText()).toBe('GitLab Duo');
      expect(findChatSubheader()).toBe(null);
    });

    it('renames the panel header once the first prompt creates the thread', async () => {
      sendPrompt(GOAL);
      await waitForSocket();

      await waitFor(() => {
        expect(panelHeadingText()).toBe(GOAL);
      });
    });
  });

  describe('with the redesign disabled', () => {
    beforeEach(async () => {
      mountPanel(false);
      await waitForChat();
    });

    it('keeps the chat header and leaves the panel header to the route', () => {
      expect(findChatSubheader()).not.toBe(null);
      expect(panelHeadingText()).toBe('GitLab Duo Agentic Chat');
      expect(panelSubheadingText()).toBe(null);
    });
  });
});
