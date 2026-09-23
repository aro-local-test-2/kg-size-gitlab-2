import {
  getMessagesToProcess,
  collectSupersededAttemptIds,
  excludeSupersededMessages,
  isCompactPromptMessage,
  isToolApprovalRequest,
  isUserMessage,
} from 'ee/ai/duo_agentic_chat/utils/messages_utils';
import { MOCK_CHAT_MESSAGES } from './mock_data';

const initialMessageId = null;

describe('Messages_utils', () => {
  describe('getMessagesToProcess', () => {
    describe('default state', () => {
      it.each`
        desc                  | value
        ${'"undefined"'}      | ${undefined}
        ${'"an empty array"'} | ${[]}
      `('returns empty Array when `messages` is %desc', ({ value }) => {
        expect(getMessagesToProcess(value)).toEqual({
          toProcess: [],
          lastProcessedMessageId: initialMessageId,
        });
      });

      it('returns all messages on initial state', () => {
        expect(getMessagesToProcess([MOCK_CHAT_MESSAGES.prompt], initialMessageId)).toEqual({
          toProcess: [MOCK_CHAT_MESSAGES.prompt],
          lastProcessedMessageId: MOCK_CHAT_MESSAGES.prompt.message_id,
        });
      });
    });

    describe('updating the existing messages', () => {
      const currentMessages = [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentStreaming];

      it('returns single message matching the lastProcessedMessageId', () => {
        const lastProcessedMessageId = currentMessages[currentMessages.length - 1].message_id; // `agentStreaming` is the last processed

        const incomingMessages = [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentComplete];

        expect(getMessagesToProcess(incomingMessages, lastProcessedMessageId)).toEqual({
          toProcess: [incomingMessages.at(-1)], // only the last agentComplete should be processed
          lastProcessedMessageId: MOCK_CHAT_MESSAGES.agentComplete.message_id, // agentComplete replaces the agentStreaming inline
        });
      });

      it('when existing message is replaced with completely different message at the same index', () => {
        const lastProcessedMessageId = currentMessages[currentMessages.length - 1].message_id; // `agentStreaming` is the last processed

        const incomingMessages = [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.tool];

        // When the lastProcessedMessageId (1) is not found in the incoming messages,
        // the function falls back to processing all messages from the beginning
        expect(getMessagesToProcess(incomingMessages, lastProcessedMessageId)).toEqual({
          toProcess: incomingMessages, // all messages are processed since message_id 1 is not found
          lastProcessedMessageId: MOCK_CHAT_MESSAGES.tool.message_id,
        });
      });

      it('returns all messages from lastProcessedMessageId onwards including the last processed message', () => {
        const lastProcessedMessageId = currentMessages[currentMessages.length - 1].message_id; // `agentStreaming` is the last processed

        const incomingMessages = [
          MOCK_CHAT_MESSAGES.user,
          MOCK_CHAT_MESSAGES.agentComplete,
          MOCK_CHAT_MESSAGES.tool,
          MOCK_CHAT_MESSAGES.request,
        ];

        expect(getMessagesToProcess(incomingMessages, lastProcessedMessageId)).toEqual({
          toProcess: [
            MOCK_CHAT_MESSAGES.agentComplete,
            MOCK_CHAT_MESSAGES.tool,
            MOCK_CHAT_MESSAGES.request,
          ], // only the last agentComplete should be processed
          lastProcessedMessageId: MOCK_CHAT_MESSAGES.request.message_id,
        });
      });
    });

    describe('full cycle workflow', () => {
      it('returns correct messages on every step of a complex workflow', () => {
        // Initial user prompt
        let lastProcessedMessageId;
        let toProcess;
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.prompt],
          initialMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.prompt]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.prompt.message_id);

        // User prompt returned in the checkpoint event
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.user],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.user]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.user.message_id);

        // Agent starts to stream
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentStreaming],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentStreaming]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.agentStreaming.message_id);

        // Streaming continues with a new chunk
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentStreaming1],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([
          MOCK_CHAT_MESSAGES.agentStreaming1, // at this point user doesn't need to be processed again
        ]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.agentStreaming1.message_id);

        // Streaming is done and the complete agent message arrived in the checkpoint event
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentComplete],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.agentComplete]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.agentComplete.message_id);

        // A tool runs automatically to get information that doesn't require approval like
        // fetching a project information
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [MOCK_CHAT_MESSAGES.user, MOCK_CHAT_MESSAGES.agentComplete, MOCK_CHAT_MESSAGES.tool],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.agentComplete, MOCK_CHAT_MESSAGES.tool]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.tool.message_id);

        // Agent starts responding with additional context from the tool
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [
            MOCK_CHAT_MESSAGES.user,
            MOCK_CHAT_MESSAGES.agentComplete,
            MOCK_CHAT_MESSAGES.tool,
            MOCK_CHAT_MESSAGES.agent2Streaming1,
          ],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.tool, MOCK_CHAT_MESSAGES.agent2Streaming1]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.agent2Streaming1.message_id);

        // Agent streaming continues
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [
            MOCK_CHAT_MESSAGES.user,
            MOCK_CHAT_MESSAGES.agentComplete,
            MOCK_CHAT_MESSAGES.tool,
            MOCK_CHAT_MESSAGES.agent2Streaming2,
          ],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.agent2Streaming2]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.agent2Streaming2.message_id);

        // Sometimes, agent streamed response gets replaced with a request, instead of sending the
        // complete agent message.
        // Keep in mind that the agent message will still stay on the screen - message with the same
        // requestID but another message_type is still considered a new message.
        // So, no messages disappearing in the UI!
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [
            MOCK_CHAT_MESSAGES.user,
            MOCK_CHAT_MESSAGES.agentComplete,
            MOCK_CHAT_MESSAGES.tool,
            MOCK_CHAT_MESSAGES.request,
          ],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([MOCK_CHAT_MESSAGES.request]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.request.message_id);

        // User approves request, but tool fails. In this case, the checkpoint event returns 2 messages:
        // - a tool message with `status: "failure"`
        // - a new agent message with some explanation or next step
        ({ toProcess, lastProcessedMessageId } = getMessagesToProcess(
          [
            MOCK_CHAT_MESSAGES.user,
            MOCK_CHAT_MESSAGES.agentComplete,
            MOCK_CHAT_MESSAGES.tool,
            MOCK_CHAT_MESSAGES.request,
            MOCK_CHAT_MESSAGES.tool3Fail[0],
            MOCK_CHAT_MESSAGES.tool3Fail[1],
          ],
          lastProcessedMessageId,
        ));
        expect(toProcess).toEqual([
          MOCK_CHAT_MESSAGES.request,
          MOCK_CHAT_MESSAGES.tool3Fail[0],
          MOCK_CHAT_MESSAGES.tool3Fail[1],
        ]);
        expect(lastProcessedMessageId).toBe(MOCK_CHAT_MESSAGES.tool3Fail[1].message_id);
      });
    });
  });

  describe('collectSupersededAttemptIds', () => {
    const messages = [
      { id: 'user-1' },
      { id: 'assistant-1' },
      { id: 'user-2' },
      { id: 'assistant-2' },
    ];

    it('collects the resubmitted message and everything after it', () => {
      expect(collectSupersededAttemptIds(messages, { id: 'user-2' })).toEqual([
        'user-2',
        'assistant-2',
      ]);
    });

    it('matches a streamed message on its message_id', () => {
      const streamed = [{ message_id: 'user-1' }, { message_id: 'assistant-1' }];

      expect(collectSupersededAttemptIds(streamed, { message_id: 'user-1' })).toEqual([
        'user-1',
        'assistant-1',
      ]);
    });

    it.each`
      desc                               | promptMessage
      ${'the message is not in the log'} | ${{ id: 'unknown' }}
      ${'the message has no id'}         | ${{ content: 'no id' }}
      ${'no message is given'}           | ${undefined}
    `('returns nothing when $desc', ({ promptMessage }) => {
      expect(collectSupersededAttemptIds(messages, promptMessage)).toEqual([]);
    });
  });

  describe('excludeSupersededMessages', () => {
    const messages = [{ id: 'user-1' }, { id: 'assistant-1' }, { id: 'user-2' }];

    it('drops the superseded messages', () => {
      expect(excludeSupersededMessages(messages, new Set(['assistant-1']))).toEqual([
        { id: 'user-1' },
        { id: 'user-2' },
      ]);
    });

    it.each`
      desc              | supersededIds
      ${'is empty'}     | ${new Set()}
      ${'is undefined'} | ${undefined}
    `('returns the log untouched when the set $desc', ({ supersededIds }) => {
      expect(excludeSupersededMessages(messages, supersededIds)).toBe(messages);
    });
  });
  describe('isCompactPromptMessage', () => {
    it('claims the optimistic local message, which carries only a role', () => {
      expect(isCompactPromptMessage({ role: 'user', content: '/compact' })).toBe(true);
    });

    it('claims the streamed copy, which carries a message_type too', () => {
      expect(
        isCompactPromptMessage({ role: 'user', message_type: 'user', content: '/compact' }),
      ).toBe(true);
    });

    it.each([
      ['an argument after the command', '/compact keep the last 10 turns'],
      ['surrounding whitespace', '  /compact\n'],
      // `commandsIn` recognises the token case-insensitively, so the composer accepts
      // this as the command and the log has to read it the same way.
      ['the command in capitals', '/COMPACT'],
    ])('claims a prompt with %s', (_, content) => {
      expect(isCompactPromptMessage({ role: 'user', content })).toBe(true);
    });

    // duo-ui lowercases before deciding a message is the user's, so a caller that did
    // not would fail to override the bubble duo-ui renders for it.
    it('claims a capitalised role, as duo-ui reads it', () => {
      expect(isCompactPromptMessage({ role: 'User', content: '/compact' })).toBe(true);
    });

    it.each([
      ['a prompt that merely starts with the same letters', '/compaction of the log'],
      ['a prompt that only mentions the command', 'what does /compact do?'],
      ['another slash command', '/new'],
      ['empty content', ''],
      ['absent content', undefined],
      // `?.trim()` would throw on these, leaving the caller to fail inside a try/catch
      // rather than simply not matching.
      ['numeric content', 42],
      ['structured content', { text: '/compact' }],
    ])('does not claim %s', (_, content) => {
      expect(isCompactPromptMessage({ role: 'user', content })).toBe(false);
    });

    it('does not claim the compaction the command produces', () => {
      expect(
        isCompactPromptMessage({ role: 'tool', message_type: 'tool', content: 'Summarized 1' }),
      ).toBe(false);
    });

    it.each([undefined, null])('does not claim %p', (message) => {
      expect(isCompactPromptMessage(message)).toBe(false);
    });
  });

  describe('isUserMessage', () => {
    it.each([
      ['a locally added prompt, which carries only a role', { role: 'user' }],
      ['a loaded message, which carries only a message_type', { message_type: 'user' }],
      ['a capitalised role, as duo-ui reads it', { role: 'User' }],
    ])('claims %s', (_, message) => {
      expect(isUserMessage(message)).toBe(true);
    });

    it.each([
      ['a response', { role: 'assistant', message_type: 'agent' }],
      [
        'a tool approval, whose role duo-ui maps to assistant',
        { role: 'assistant', message_type: 'request' },
      ],
      ['a message with neither field', {}],
      ['no message at all', undefined],
    ])('does not claim %s', (_, message) => {
      expect(isUserMessage(message)).toBe(false);
    });
  });

  describe('isToolApprovalRequest', () => {
    it('claims a request carrying tool_info', () => {
      expect(
        isToolApprovalRequest({ message_type: 'request', tool_info: { name: 'run_command' } }),
      ).toBe(true);
    });

    it.each([
      ['a request with no tool to approve', { message_type: 'request' }],
      [
        'the tool message an approval produces',
        { message_type: 'tool', tool_info: { name: 'run_command' } },
      ],
      ['a plain response', { message_type: 'agent' }],
      ['no message at all', undefined],
    ])('does not claim %s', (_, message) => {
      expect(isToolApprovalRequest(message)).toBe(false);
    });
  });
});
