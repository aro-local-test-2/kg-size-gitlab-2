import { waitFor } from '@testing-library/vue';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import { installDuoAIPanelHandlers } from '../test_support/api_handlers';
import {
  PROJECT_ID,
  findChatMessages,
  findCompactingIndicator,
  cancelPrompt,
  findCancelButton,
  findCompactionDelimiter,
  findResponseLoader,
  findSubmitButton,
  mountDuoAgenticChatStateManager,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  pushCheckpoint,
  toolLogEntry,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// The compact plugin's two halves only work because of a precedence rule that lives
// inside `@gitlab/duo-ui`: host `messageRenderers` are merged ahead of the built-ins,
// so the widget outranks duo-ui's own user prompt bubble. A unit test cannot see that,
// so the override is proven here, through the real registry the harness builds.

const COMPACT_PROMPT = '/compact';

const compactionLogEntry = () =>
  toolLogEntry({
    id: 'compaction-1',
    name: 'compaction',
    subType: 'compaction',
    args: { trigger: 'manual', messages_summarized: 2 },
    content: 'Summarized 2 messages',
  });

describe('Duo Agentic Chat | compacting the conversation', () => {
  // The worker opens the socket only once startWorkflow calls connect(), so the prompt
  // has to come before any checkpoint.
  const send = async (text) => {
    sendPrompt(text);
    await waitForSocket();
  };

  beforeEach(async () => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();

    mountDuoAgenticChatStateManager({ propsData: { projectId: PROJECT_ID } });

    await waitFor(() => {
      expect(findSubmitButton()).not.toBe(null);
    });
  });

  afterEach(() => teardownDuoChatTest());

  describe('while the command is in flight', () => {
    beforeEach(() => send(COMPACT_PROMPT));

    it('stands the indicator in for the prompt instead of echoing it back', async () => {
      await waitFor(() => {
        expect(findCompactingIndicator()).not.toBe(null);
      });

      expect(getText(findCompactingIndicator())).toBe('Compacting…');
      expect(getText(findChatMessages())).not.toContain(COMPACT_PROMPT);
      expect(findCompactionDelimiter()).toBe(null);
    });

    // The indicator is the progress signal for this turn, so duo-ui's own loader would
    // be a second spinner for the same wait.
    it("shows the indicator alone, without duo-ui's response loader under it", async () => {
      await waitFor(() => {
        expect(findCompactingIndicator()).not.toBe(null);
      });

      expect(findResponseLoader()).toBe(null);
      // The turn has not finished, so the composer still offers to cancel it.
      expect(findCancelButton()).not.toBe(null);
    });
  });

  describe('once the compaction lands', () => {
    beforeEach(async () => {
      await send(COMPACT_PROMPT);
      await pushCheckpoint([
        userLogEntry({ id: 'user-1', content: COMPACT_PROMPT }),
        compactionLogEntry(),
      ]);
    });

    it('replaces the indicator with the divider that marks the boundary', async () => {
      await waitFor(() => {
        expect(findCompactionDelimiter()).not.toBe(null);
      });

      expect(getText(findCompactionDelimiter())).toBe('Conversation compacted');
      expect(findCompactingIndicator()).toBe(null);
      expect(getText(findChatMessages())).not.toContain(COMPACT_PROMPT);
    });
  });

  // Cancelling stops the workflow without adding anything to the log, so nothing
  // downstream of the message log can retire the indicator.
  describe('when the user stops the workflow mid-compaction', () => {
    beforeEach(async () => {
      await send(COMPACT_PROMPT);

      await waitFor(() => {
        expect(findCompactingIndicator()).not.toBe(null);
      });

      cancelPrompt();
    });

    it('retires the indicator', async () => {
      await waitFor(() => {
        expect(findCancelButton()).toBe(null);
      });

      expect(findCompactingIndicator()).toBe(null);
    });
  });

  // The control for the assertion above: an ordinary prompt in the same harness does
  // show the loader, so "no loader" is a real consequence of the compact prompt rather
  // than a loader that never renders here at all.
  describe('an ordinary prompt in flight', () => {
    beforeEach(() => send('Summarise this file for me'));

    it("still shows duo-ui's response loader", async () => {
      await waitFor(() => {
        expect(findResponseLoader()).not.toBe(null);
      });

      expect(findCompactingIndicator()).toBe(null);
    });
  });

  // Whatever settles the prompt ends the indicator, so a turn that produced no
  // compaction at all must not leave it spinning.
  describe('when the command produced no compaction', () => {
    beforeEach(async () => {
      await send(COMPACT_PROMPT);
      await pushCheckpoint([
        userLogEntry({ id: 'user-1', content: COMPACT_PROMPT }),
        agentLogEntry({ id: 'agent-1', content: 'There was nothing to compact.' }),
      ]);
    });

    it('drops the indicator along with the prompt', async () => {
      await waitFor(() => {
        expect(getText(findChatMessages())).toContain('There was nothing to compact.');
      });

      expect(findCompactingIndicator()).toBe(null);
      expect(getText(findChatMessages())).not.toContain(COMPACT_PROMPT);
    });
  });
});
