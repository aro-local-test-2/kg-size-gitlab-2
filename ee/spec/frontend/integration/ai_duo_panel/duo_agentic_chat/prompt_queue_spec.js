import { waitFor } from '@testing-library/vue';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import { installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  approveTool,
  cancelPrompt,
  findApproveButton,
  findCancelButton,
  findQueuedPromptMessages,
  findQueuedPromptRemoveButton,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  closeSocketFromServer,
  getSockets,
  lastStartRequest,
  pushCheckpoint,
  toolRequestLogEntry,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// The composer, the state manager and the queue each hold a piece of this
// feature, and the interesting cases are the handoffs between them. Every
// assertion about "was it sent" counts sockets: a prompt leaves the client as a
// fresh connect, so an unchanged socket count is the proof nothing went out.

const FIRST_PROMPT = 'summarise the open issues';
const QUEUED_PROMPT = 'now draft a plan from them';
const DENYING_PROMPT = 'skip that, just tell me what you have';

const inFlightTurn = () => [
  userLogEntry({ id: 'user-1', content: FIRST_PROMPT }),
  agentLogEntry({ id: 'agent-1', content: 'Looking now', status: 'running' }),
];

const finishedTurn = () => [
  userLogEntry({ id: 'user-1', content: FIRST_PROMPT }),
  agentLogEntry({ id: 'agent-1', content: 'Here is the summary' }),
];

const pendingToolRequest = () => [
  userLogEntry({ id: 'user-1', content: FIRST_PROMPT }),
  agentLogEntry({ id: 'agent-1', content: 'I need to read a file first' }),
  toolRequestLogEntry({
    id: 'request-1',
    name: 'read_file',
    args: { path: 'README.md' },
    content: 'Requesting approval to read a file',
    status: 'pending',
  }),
];

describe('Duo Agentic Chat | queueing prompts during a turn', () => {
  const mountAndStartTurn = async () => {
    mountDuoAgenticChatStateManager({ propsData: { projectId: PROJECT_ID } });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });

    // The worker opens the socket only once startWorkflow calls connect().
    sendPrompt(FIRST_PROMPT);
    await waitForSocket();

    // The cancel button replaces the submit button once a response is awaited.
    await waitFor(() => {
      expect(findCancelButton()).not.toBe(null);
    });
  };

  const queueSecondPrompt = async () => {
    sendPrompt(QUEUED_PROMPT);

    await waitFor(() => {
      expect(findQueuedPromptMessages()).toHaveLength(1);
    });
  };

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('holds a prompt submitted mid-turn instead of sending it', async () => {
    await mountAndStartTurn();
    await pushCheckpoint(inFlightTurn(), { status: 'RUNNING', goal: FIRST_PROMPT });

    const socketsBeforeQueueing = getSockets().length;
    await queueSecondPrompt();

    expect(getText(findQueuedPromptMessages()[0])).toContain(QUEUED_PROMPT);
    expect(getSockets()).toHaveLength(socketsBeforeQueueing);
  });

  it('drops a queued prompt the user removes', async () => {
    await mountAndStartTurn();
    await queueSecondPrompt();

    findQueuedPromptRemoveButton().click();

    await waitFor(() => {
      expect(findQueuedPromptMessages()).toHaveLength(0);
    });
  });

  it('sends the queued prompt once the turn ends', async () => {
    await mountAndStartTurn();
    await queueSecondPrompt();

    const socketsBeforeDrain = getSockets().length;

    // The turn ending is not on its own the go-ahead: Workhorse holds the workflow
    // lock until it closes the socket, so the close is what releases the queue.
    await pushCheckpoint(finishedTurn(), { goal: FIRST_PROMPT });
    await closeSocketFromServer();

    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBeforeDrain + 1);
    });
    await waitForSocket();

    expect(lastStartRequest().goal).toBe(QUEUED_PROMPT);
    expect(findQueuedPromptMessages()).toHaveLength(0);
  });

  it('holds the queue at a tool approval gate until the user answers', async () => {
    await mountAndStartTurn();
    await queueSecondPrompt();

    const socketsBeforeGate = getSockets().length;

    // An approval gate ends the turn without finishing the workflow: the service
    // reports TOOL_CALL_APPROVAL_REQUIRED and closes the socket, and it is the
    // close that clears the waiting flag. Draining here would cancel the tool.
    await pushCheckpoint(pendingToolRequest(), {
      status: 'TOOL_CALL_APPROVAL_REQUIRED',
      goal: FIRST_PROMPT,
    });
    await closeSocketFromServer();

    await waitFor(() => {
      expect(findApproveButton()).not.toBe(null);
    });

    expect(getSockets()).toHaveLength(socketsBeforeGate);
    expect(findQueuedPromptMessages()).toHaveLength(1);

    approveTool();

    // The approval is its own connect, carrying an empty goal.
    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBeforeGate + 1);
    });
    await waitForSocket();
    expect(lastStartRequest().approval).toEqual({ approval: {} });

    await pushCheckpoint(finishedTurn(), { goal: FIRST_PROMPT });
    await closeSocketFromServer();

    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBeforeGate + 2);
    });
    await waitForSocket();

    expect(lastStartRequest().goal).toBe(QUEUED_PROMPT);
    expect(findQueuedPromptMessages()).toHaveLength(0);
  });

  it('sends a prompt submitted at a tool approval gate straight away', async () => {
    await mountAndStartTurn();
    await queueSecondPrompt();

    await pushCheckpoint(pendingToolRequest(), {
      status: 'TOOL_CALL_APPROVAL_REQUIRED',
      goal: FIRST_PROMPT,
    });
    await closeSocketFromServer();

    await waitFor(() => {
      expect(findApproveButton()).not.toBe(null);
    });

    const socketsBeforeSend = getSockets().length;

    // Sending rather than approving is how the user walks away from a tool call
    // they do not want to answer, so this prompt goes out now. The one queued
    // before the gate appeared was not that choice, so it stays put.
    sendPrompt(DENYING_PROMPT);

    await waitFor(() => {
      expect(getSockets()).toHaveLength(socketsBeforeSend + 1);
    });
    await waitForSocket();

    expect(lastStartRequest().goal).toBe(DENYING_PROMPT);
    expect(findQueuedPromptMessages()).toHaveLength(1);
    expect(getText(findQueuedPromptMessages()[0])).toContain(QUEUED_PROMPT);
  });

  it('discards the queue when the user cancels the turn', async () => {
    await mountAndStartTurn();
    await queueSecondPrompt();

    cancelPrompt();

    await waitFor(() => {
      expect(findQueuedPromptMessages()).toHaveLength(0);
    });
  });
});
