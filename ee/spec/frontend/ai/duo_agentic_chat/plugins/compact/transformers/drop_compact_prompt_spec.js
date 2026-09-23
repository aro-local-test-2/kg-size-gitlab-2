import { dropCompactPrompt } from 'ee/ai/duo_agentic_chat/plugins/compact/transformers/drop_compact_prompt';
import {
  MOCK_COMPACT_PROMPT_MESSAGE,
  MOCK_COMPACTION_TOOL_MESSAGE,
} from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

describe('dropCompactPrompt', () => {
  const agentMessage = { message_type: 'agent', content: 'Done.' };

  // The command asks for work rather than saying anything, and progress is reported
  // outside the log, so the prompt never earns a place in the transcript.
  it('drops the prompt whether or not the compaction has landed', () => {
    expect(dropCompactPrompt([MOCK_COMPACT_PROMPT_MESSAGE])).toEqual([]);
    expect(dropCompactPrompt([MOCK_COMPACT_PROMPT_MESSAGE, MOCK_COMPACTION_TOOL_MESSAGE])).toEqual([
      MOCK_COMPACTION_TOOL_MESSAGE,
    ]);
  });

  it('drops every prompt in a log that was compacted more than once', () => {
    const messages = [
      MOCK_COMPACT_PROMPT_MESSAGE,
      MOCK_COMPACTION_TOOL_MESSAGE,
      MOCK_COMPACT_PROMPT_MESSAGE,
      MOCK_COMPACTION_TOOL_MESSAGE,
    ];

    expect(dropCompactPrompt(messages)).toEqual([
      MOCK_COMPACTION_TOOL_MESSAGE,
      MOCK_COMPACTION_TOOL_MESSAGE,
    ]);
  });

  it('leaves other user messages alone', () => {
    const messages = [
      { role: 'user', content: 'Compact the log for me' },
      { role: 'user', content: '/compaction of the log' },
      agentMessage,
    ];

    expect(dropCompactPrompt(messages)).toEqual(messages);
  });

  it('returns an empty log unchanged', () => {
    expect(dropCompactPrompt([])).toEqual([]);
  });
});
