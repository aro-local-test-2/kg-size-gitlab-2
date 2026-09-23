import { dropNoopCompaction } from 'ee/ai/duo_agentic_chat/plugins/compact/transformers/drop_noop_compaction';
import { MOCK_COMPACTION_TOOL_MESSAGE } from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

describe('dropNoopCompaction', () => {
  const agentMessage = { message_type: 'agent', content: 'Done.' };

  const compaction = (args) => ({
    message_type: 'tool',
    message_sub_type: 'compaction',
    tool_info: { name: 'compaction', args },
  });

  // Dropped rather than hidden by the widget: duo-ui's per-message wrapper would
  // otherwise stay behind as an empty flex item and double the surrounding gap.
  it('drops a compaction that summarized nothing', () => {
    expect(dropNoopCompaction([agentMessage, compaction({ messages_summarized: 0 })])).toEqual([
      agentMessage,
    ]);
  });

  it('drops a compaction with no summarized count', () => {
    expect(dropNoopCompaction([agentMessage, compaction({ trigger: 'manual' })])).toEqual([
      agentMessage,
    ]);
  });

  it('drops a compaction with no tool_info at all', () => {
    expect(dropNoopCompaction([agentMessage, { message_sub_type: 'compaction' }])).toEqual([
      agentMessage,
    ]);
  });

  it('keeps a compaction that summarized messages', () => {
    const compacted = compaction({ messages_summarized: 3 });

    expect(dropNoopCompaction([agentMessage, compacted])).toEqual([agentMessage, compacted]);
  });

  it('keeps the compaction message the widget renders', () => {
    expect(dropNoopCompaction([MOCK_COMPACTION_TOOL_MESSAGE])).toEqual([
      MOCK_COMPACTION_TOOL_MESSAGE,
    ]);
  });

  it('leaves messages of other types alone', () => {
    const messages = [agentMessage, { message_type: 'tool', message_sub_type: 'start_flow' }];

    expect(dropNoopCompaction(messages)).toEqual(messages);
  });

  it('returns an empty log unchanged', () => {
    expect(dropNoopCompaction([])).toEqual([]);
  });
});
