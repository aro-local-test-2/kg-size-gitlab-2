import { waitFor } from '@testing-library/vue';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import { installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  findAlternativePagerNext,
  findAlternativePagerPosition,
  findAlternativePagerPrevious,
  findChatMessages,
  findRetryButton,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// Exercises the pieces the alternatives_transformer unit spec cannot: the real
// retry button collapsing a turn into a pager, and the pager driving what
// duo-ui actually renders, end to end through the chat/transformer/duo-ui stack.

const PROMPT = 'What is GitLab?';
const FIRST_ANSWER = 'A DevOps platform.';
const RETRY_ANSWER = 'GitLab is the AI-powered DevSecOps platform.';
const SECOND_RETRY_ANSWER = 'GitLab is a complete DevSecOps platform.';

describe('Duo Agentic Chat | navigating retry alternatives', () => {
  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('collapses a retry into a pager and lets the user page between the two responses', async () => {
    mountDuoAgenticChatStateManager({
      propsData: { projectId: PROJECT_ID },
      provide: { glFeatures: { agenticManualRetryForDuoChatResponses: true } },
    });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

    sendPrompt(PROMPT);
    await waitForSocket();

    await pushCheckpoint([
      userLogEntry({ id: 'user-1', content: PROMPT }),
      agentLogEntry({ id: 'agent-1', content: FIRST_ANSWER }),
    ]);

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FIRST_ANSWER);
    });

    // Retrying re-sends the same prompt content and opens a fresh socket; the
    // retried turn is what the workflow service appends to the checkpoint log.
    await waitFor(() => {
      expect(findRetryButton()).not.toBe(null);
    });
    findRetryButton().click();
    await waitForSocket({ minCount: 2 });

    await pushCheckpoint([
      userLogEntry({ id: 'user-1', content: PROMPT }),
      agentLogEntry({ id: 'agent-1', content: FIRST_ANSWER }),
      userLogEntry({ id: 'user-2', content: PROMPT }),
      agentLogEntry({ id: 'agent-2', content: RETRY_ANSWER }),
    ]);

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(RETRY_ANSWER);
    });

    // The retry collapses into a single turn: the first attempt no longer
    // renders as its own message, only as an entry behind the pager.
    expect(getText(findChatMessages())).not.toContain(FIRST_ANSWER);
    expect(getText(findAlternativePagerPosition())).toBe('1/2');

    findAlternativePagerNext().click();

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FIRST_ANSWER);
    });
    expect(getText(findChatMessages())).not.toContain(RETRY_ANSWER);
    expect(getText(findAlternativePagerPosition())).toBe('2/2');

    findAlternativePagerPrevious().click();

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(RETRY_ANSWER);
    });
    expect(getText(findAlternativePagerPosition())).toBe('1/2');
  });

  it('counts each retry once when the service replays a forked branch log', async () => {
    mountDuoAgenticChatStateManager({
      propsData: { projectId: PROJECT_ID },
      provide: { glFeatures: { agenticManualRetryForDuoChatResponses: true } },
    });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

    sendPrompt(PROMPT);
    await waitForSocket();

    await pushCheckpoint([
      userLogEntry({ id: 'user-1', content: PROMPT }),
      agentLogEntry({ id: 'agent-1', content: FIRST_ANSWER }),
    ]);

    await waitFor(() => {
      expect(findRetryButton()).not.toBe(null);
    });
    findRetryButton().click();
    await waitForSocket({ minCount: 2 });

    await pushCheckpoint([
      userLogEntry({ id: 'user-1', content: PROMPT }),
      agentLogEntry({ id: 'agent-1', content: FIRST_ANSWER }),
      userLogEntry({ id: 'user-2', content: PROMPT }),
      agentLogEntry({ id: 'agent-2', content: RETRY_ANSWER }),
    ]);

    await waitFor(() => {
      expect(getText(findAlternativePagerPosition())).toBe('1/2');
    });

    // Retrying a retried turn forks from before the previous attempt, so the
    // replayed branch log no longer contains that attempt's messages (the
    // dedup anchor among them). The whole log is reprocessed from the top;
    // the re-delivered first attempt must not be double-counted.
    findRetryButton().click();
    await waitForSocket({ minCount: 3 });

    await pushCheckpoint([
      userLogEntry({ id: 'user-1', content: PROMPT }),
      agentLogEntry({ id: 'agent-1', content: FIRST_ANSWER }),
      userLogEntry({ id: 'user-3', content: PROMPT }),
      agentLogEntry({ id: 'agent-3', content: SECOND_RETRY_ANSWER }),
    ]);

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(SECOND_RETRY_ANSWER);
    });
    expect(getText(findAlternativePagerPosition())).toBe('1/3');
  });
});
