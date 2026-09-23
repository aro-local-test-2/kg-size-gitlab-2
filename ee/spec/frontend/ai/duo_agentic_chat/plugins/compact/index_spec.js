import { compactPlugin } from 'ee/ai/duo_agentic_chat/plugins/compact';
import MessageCompaction from 'ee/ai/duo_agentic_chat/plugins/compact/components/message_compaction.vue';
import { dropCompactPrompt } from 'ee/ai/duo_agentic_chat/plugins/compact/transformers/drop_compact_prompt';
import { dropNoopCompaction } from 'ee/ai/duo_agentic_chat/plugins/compact/transformers/drop_noop_compaction';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { runMessageTransformers } from 'ee/ai/duo_agentic_chat/transformers';
import {
  MOCK_COMPACT_PROMPT_MESSAGE,
  MOCK_COMPACTION_TOOL_MESSAGE,
} from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

describe('compactPlugin', () => {
  const [{ matchMessage }] = compactPlugin.messageWidgets;

  // The registry drops anything malformed, so a broken descriptor would otherwise only
  // show up as a menu with one command missing from it.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(compactPlugin);

    expect(registry.plugins).toEqual([compactPlugin]);
  });

  it('is named after its plugin directory', () => {
    expect(compactPlugin.name).toBe('compact');
  });

  it('offers the compact command', async () => {
    const commands = await compactPlugin.slashCommands[0].getCommands({});

    expect(commands).toEqual([
      {
        value: '/compact',
        description: 'Summarize and compact this conversation',
        startOnly: true,
        action: 'insert',
      },
    ]);
  });

  // `groupable: false` is what keeps the divider out of the collapsible tool-group it
  // would otherwise be folded into; `defaultProps: {}` keeps duo-ui from binding
  // `message`/`workingDirectory` onto a component that renders a static divider.
  it('renders compaction messages with MessageCompaction, ungrouped and without props', () => {
    expect(compactPlugin.messageWidgets).toEqual([
      {
        matchMessage: expect.any(Function),
        component: MessageCompaction,
        groupable: false,
        defaultProps: {},
      },
    ]);
  });

  // Behaviour lives in each transformer's own spec; this is the wiring.
  it('drops compact prompts and no-op compactions from the log', () => {
    expect(compactPlugin.messageTransformers).toEqual([
      { transformMessages: dropCompactPrompt },
      { transformMessages: dropNoopCompaction },
    ]);
  });

  describe('matchMessage', () => {
    it('returns true for a compaction message', () => {
      expect(matchMessage(MOCK_COMPACTION_TOOL_MESSAGE)).toBe(true);
    });

    it('returns false for a tool message of another sub type', () => {
      expect(matchMessage({ message_type: 'tool', message_sub_type: 'start_flow' })).toBe(false);
    });

    it('returns false when message_sub_type is absent', () => {
      expect(matchMessage({ message_type: 'tool' })).toBe(false);
    });

    // The prompt is no longer a widget of this plugin: the view reports progress, and
    // the transformer drops the message, so nothing should claim it for rendering.
    it('returns false for the prompt that asks for the compaction', () => {
      expect(matchMessage(MOCK_COMPACT_PROMPT_MESSAGE)).toBe(false);
    });

    it('returns false for a nullish message', () => {
      expect(matchMessage(undefined)).toBe(false);
      expect(matchMessage(null)).toBe(false);
    });
  });

  // Neither transformer reads the other's output, so the pipeline is asserted for what
  // the pair leaves behind rather than for an order it no longer depends on.
  describe('the transformer pipeline', () => {
    const pipeline = (messages) =>
      runMessageTransformers(
        messages,
        compactPlugin.messageTransformers.map(({ transformMessages }) => transformMessages),
      );

    const noopCompaction = {
      message_type: 'tool',
      message_sub_type: 'compaction',
      tool_info: { name: 'compaction', args: { messages_summarized: 0 } },
    };

    it('leaves nothing behind when the compaction summarized nothing', () => {
      expect(pipeline([MOCK_COMPACT_PROMPT_MESSAGE, noopCompaction])).toEqual([]);
    });

    it('keeps only the compaction when something was summarized', () => {
      expect(pipeline([MOCK_COMPACT_PROMPT_MESSAGE, MOCK_COMPACTION_TOOL_MESSAGE])).toEqual([
        MOCK_COMPACTION_TOOL_MESSAGE,
      ]);
    });

    it('drops a prompt whose turn has not produced anything yet', () => {
      expect(pipeline([MOCK_COMPACT_PROMPT_MESSAGE])).toEqual([]);
    });
  });
});
