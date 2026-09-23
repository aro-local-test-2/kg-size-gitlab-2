import { waitFor } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import {
  getUserWorkflows,
  getUserWorkflowsTwoThreads,
  getWorkflowLatestCheckpointFirstThread,
  getWorkflowLatestCheckpointSecondThread,
  userWorkflowsVariants,
  workflowLatestCheckpointVariants,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  buildChatConfiguration,
  findButton,
  findChatComponent,
  findChatMessages,
  findChatToggle,
  findDuoAgenticChatPanel,
  findEmptyState,
  findHistoryToggle,
  findMessages,
  findSessionsToggle,
  findSubmitButton,
  findThreadBoxWithText,
  findThreadBoxes,
  mountAISidebar,
  openChatTab,
  openHistoryTab,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  closeSocketFromServer,
  getSockets,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// Replaces the "allows basic UI interactions" and "shows session ID dropdown
// during active chat" examples from
// ee/spec/support/shared_examples/ai/agentic_chat_shared_example.rb.
//
// Mounts the whole panel because the navigation rail, the history round-trip and
// the session-id dropdown (gated on `$route.name`) all need the real router.

const QUESTION = 'dummy-question';
const ANSWER = 'mock answer';
const SECOND_QUESTION = 'dummy-question-2';
const SECOND_ANSWER = 'second mock answer';

// Read off the recorded conversations rather than restated, so the two threads stay
// distinguishable even if a regeneration changes their wording.
const conversationText = ({ messages }) => ({
  question: messages().find(({ role }) => role === 'user').content,
  answer: messages().find(({ role }) => role === 'assistant').content,
});

const listedThreads = () => getUserWorkflows.threads();
const twoThreadsList = () => getUserWorkflowsTwoThreads.threads();

const { question: OLDER_QUESTION, answer: OLDER_ANSWER } = conversationText(
  getWorkflowLatestCheckpointFirstThread,
);
const { question: NEWER_QUESTION, answer: NEWER_ANSWER } = conversationText(
  getWorkflowLatestCheckpointSecondThread,
);

const firstExchange = () => [
  userLogEntry({ id: 'user-1', content: QUESTION }),
  agentLogEntry({ id: 'agent-1', content: ANSWER }),
];

const secondExchange = () => [
  ...firstExchange(),
  userLogEntry({ id: 'user-2', content: SECOND_QUESTION }),
  agentLogEntry({ id: 'agent-2', content: SECOND_ANSWER }),
];

describe('Duo Agentic Chat | conversation lifecycle in the AI panel', () => {
  const mountPanel = () => mountAISidebar({ chatConfiguration: buildChatConfiguration() });

  const openChatAndWaitForComposer = async () => {
    await waitFor(() => {
      expect(findChatToggle()).not.toBe(null);
    });

    openChatTab();

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });
  };

  const askAndAnswer = async ({ prompt, uiChatLog }) => {
    const socketsBefore = getSockets().length;

    sendPrompt(prompt);

    // Each startWorkflow opens a fresh socket; wait for this prompt's.
    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBefore + 1);
    });
    await waitForSocket();

    await pushCheckpoint(uiChatLog(), { goal: prompt });

    // Workhorse closes the socket when the turn ends, and that close is what frees
    // the workflow lock. Without it the next prompt cannot go out.
    return closeSocketFromServer();
  };

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('exposes the navigation rail with the panel closed', async () => {
    mountPanel();

    await waitFor(() => {
      expect(findChatToggle()).not.toBe(null);
    });

    expect(findHistoryToggle()).not.toBe(null);
    expect(findSessionsToggle()).not.toBe(null);

    // Nothing is mounted into the panel until a tab is opened.
    expect(findDuoAgenticChatPanel()).toBe(null);
    expect(findChatComponent()).toBe(null);
  });

  it('opens the chat on the empty state and streams a full exchange', async () => {
    mountPanel();
    await openChatAndWaitForComposer();

    // The chat opens on its empty state. (The Capybara original asserted
    // "GitLab Duo Agent Platform" here, which is the SaaS trial/subscription
    // empty state rather than the chat's own -- those specs ran with `:saas`.)
    expect(findEmptyState()).not.toBe(null);
    expect(getText(findEmptyState())).toContain('I am GitLab Duo Agentic Chat');

    await askAndAnswer({ prompt: QUESTION, uiChatLog: firstExchange });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(ANSWER);
    });

    expect(getText(findChatMessages())).toContain(QUESTION);

    // A follow-up appends to the same conversation rather than replacing it.
    await askAndAnswer({ prompt: SECOND_QUESTION, uiChatLog: secondExchange });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(SECOND_ANSWER);
    });

    expect(findMessages()).toHaveLength(4);
  });

  it('offers the session ID once a workflow is active', async () => {
    mountPanel();
    await openChatAndWaitForComposer();

    // The dropdown only renders once a session id has been emitted, which
    // happens after the workflow is created.
    await askAndAnswer({ prompt: QUESTION, uiChatLog: firstExchange });

    const moreOptions = await waitFor(() => {
      const button = findButton('More options');
      expect(button).not.toBe(null);
      return button;
    });

    // The items are in the DOM whether or not the dropdown is open, so assert on
    // the toggle's own state as well as on the menu it controls -- otherwise this
    // passes without the click.
    expect(moreOptions.getAttribute('aria-expanded')).toBe('false');

    moreOptions.click();

    await waitFor(() => {
      expect(moreOptions.getAttribute('aria-expanded')).toBe('true');
    });

    const menu = document.getElementById(moreOptions.getAttribute('aria-controls'));
    expect(getText(menu)).toContain('Copy Chat Session ID');
  });

  it('creates a workflow for the prompt and lists the threads history returns', async () => {
    mountPanel();
    await openChatAndWaitForComposer();
    await askAndAnswer({ prompt: QUESTION, uiChatLog: firstExchange });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(ANSWER);
    });

    // Whether the workflow this prompt created then shows up in history is the
    // backend persisting it, which these tests do not run. What is the panel's own
    // is that it asked for the workflow it meant to create...
    expect(lastRequestVariables('createAiDuoWorkflow')).toMatchObject({ goal: QUESTION });

    openHistoryTab();

    // ...and that it renders the threads the server hands back.
    await waitFor(() => {
      expect(findThreadBoxes()).toHaveLength(listedThreads().length);
    });

    expect(findThreadBoxWithText(listedThreads()[0].title)).not.toBe(null);
  });

  it('hydrates the thread picked from history rather than the other one', async () => {
    // Two conversations already exist; only the older one's content should
    // appear after selecting it.
    setQueryVariant(userWorkflowsVariants).twoThreads();
    setQueryVariant(workflowLatestCheckpointVariants).firstThread();

    mountPanel();

    await waitFor(() => {
      expect(findHistoryToggle()).not.toBe(null);
    });

    openHistoryTab();

    await waitFor(() => {
      expect(findThreadBoxes()).toHaveLength(twoThreadsList().length);
    });

    findThreadBoxWithText(OLDER_QUESTION).click();

    await waitFor(() => {
      expect(findDuoAgenticChatPanel()).not.toBe(null);
    });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(OLDER_ANSWER);
    });

    // The variant answers whatever id it is asked for, so the proof that the app
    // opened the thread the user clicked is the id it asked for.
    expect(lastRequestVariables('getWorkflowLatestCheckpoint')).toEqual({
      workflowId: getWorkflowLatestCheckpointFirstThread.workflow().id,
    });
    expect(getText(findChatMessages())).not.toContain(NEWER_ANSWER);

    openHistoryTab();

    await waitFor(() => {
      expect(findThreadBoxes()).toHaveLength(twoThreadsList().length);
    });

    setQueryVariant(workflowLatestCheckpointVariants).secondThread();
    findThreadBoxWithText(NEWER_QUESTION).click();

    await waitFor(() => {
      expect(findDuoAgenticChatPanel()).not.toBe(null);
    });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(NEWER_ANSWER);
    });

    // Same reason as above: with SECOND_THREAD active the rendered text is the
    // same whichever thread was clicked, so the id is the only proof.
    expect(lastRequestVariables('getWorkflowLatestCheckpoint')).toEqual({
      workflowId: getWorkflowLatestCheckpointSecondThread.workflow().id,
    });
  });
});
