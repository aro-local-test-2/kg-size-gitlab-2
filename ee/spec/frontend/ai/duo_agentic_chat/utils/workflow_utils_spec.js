import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import {
  MOCK_ASSISTANT_MESSAGES,
  MOCK_SINGLE_GENERIC_MESSAGE,
  MOCK_MULTIPLE_USER_MESSAGES,
  MOCK_USER_MESSAGE_WITH_PROPERTIES,
  MOCK_PARSE_WORKFLOW_RESPONSE,
  MOCK_PARSE_WORKFLOW_EMPTY_RESPONSE,
  MOCK_PARSE_WORKFLOW_WITH_CHECKPOINT_RESPONSE,
} from './mock_data';

describe('WorkflowUtils', () => {
  describe('parseWorkflowData', () => {
    it('returns null when there are no workflow nodes', () => {
      const result = WorkflowUtils.parseWorkflowData(MOCK_PARSE_WORKFLOW_EMPTY_RESPONSE);

      expect(result).toBeNull();
    });

    it('returns the latestCheckpoint from the first workflow node', () => {
      const result = WorkflowUtils.parseWorkflowData(MOCK_PARSE_WORKFLOW_RESPONSE);

      expect(result.workflowGoal).toBe('Test goal');
      expect(result.workflowStatus).toBe('RUNNING');
      expect(result.duoMessages).toHaveLength(1);
    });

    it('returns null when the workflow has no latestCheckpoint', () => {
      const result = WorkflowUtils.parseWorkflowData(MOCK_PARSE_WORKFLOW_WITH_CHECKPOINT_RESPONSE);

      expect(result).toBeNull();
    });
  });

  describe('parseWorkflowStatus', () => {
    it('returns null when there are no workflow nodes', () => {
      expect(WorkflowUtils.parseWorkflowStatus(MOCK_PARSE_WORKFLOW_EMPTY_RESPONSE)).toBeNull();
    });

    it('returns null for an empty response object', () => {
      expect(WorkflowUtils.parseWorkflowStatus({})).toBeNull();
    });

    it('returns the status of the first workflow node', () => {
      expect(WorkflowUtils.parseWorkflowStatus(MOCK_PARSE_WORKFLOW_RESPONSE)).toBe('RUNNING');
    });

    it('returns the status even when the workflow has no latestCheckpoint', () => {
      expect(WorkflowUtils.parseWorkflowStatus(MOCK_PARSE_WORKFLOW_WITH_CHECKPOINT_RESPONSE)).toBe(
        'CREATED',
      );
    });
  });

  describe('normalizeDuoMessages', () => {
    it('converts camelCase GraphQL fields to snake_case', () => {
      const duoMessages = [
        {
          content: 'Hello',
          messageType: 'agent',
          toolInfo: '{"name":"tool"}',
          messageId: 'executor-msg-1',
          correlationId: 'client-corr-1',
          role: 'assistant',
          status: null,
          timestamp: '2025-07-25T14:30:00Z',
        },
      ];

      const result = WorkflowUtils.normalizeDuoMessages(duoMessages);

      expect(result[0]).toEqual({
        content: 'Hello',
        message_type: 'agent',
        tool_info: { name: 'tool' },
        message_id: 'executor-msg-1',
        correlation_id: 'client-corr-1',
        role: 'assistant',
        status: null,
        timestamp: '2025-07-25T14:30:00Z',
        alternative_count: undefined,
      });
    });

    it('maps alternativeCount to alternative_count', () => {
      const duoMessages = [
        { messageId: 'user-msg-1', threadTs: 'ts-1', parentTs: 'ts-0', alternativeCount: 2 },
      ];

      const result = WorkflowUtils.normalizeDuoMessages(duoMessages);

      expect(result[0].alternative_count).toBe(2);
    });

    it('returns an empty array for empty input', () => {
      expect(WorkflowUtils.normalizeDuoMessages([])).toEqual([]);
    });
  });

  describe('findLatestTodoToolInfo', () => {
    const todoToolInfo = (todos) => ({
      name: 'todo_write',
      args: { todos },
    });

    const otherToolInfo = {
      name: 'read_file',
      args: { path: 'foo.rb' },
    };

    describe('when the messages array is empty', () => {
      let result;

      beforeEach(() => {
        result = WorkflowUtils.findLatestTodoToolInfo([]);
      });

      it('returns null', () => {
        expect(result).toBeNull();
      });
    });

    describe('when no message has a todo_write tool_info', () => {
      let result;

      beforeEach(() => {
        const messages = [{ tool_info: otherToolInfo }, { tool_info: { name: 'grep', args: {} } }];

        result = WorkflowUtils.findLatestTodoToolInfo(messages);
      });

      it('returns null', () => {
        expect(result).toBeNull();
      });
    });

    describe('when a single todo_write message has todos', () => {
      const expected = todoToolInfo([{ status: 'pending', description: 'one' }]);
      let result;

      beforeEach(() => {
        const messages = [{ tool_info: otherToolInfo }, { tool_info: expected }];

        result = WorkflowUtils.findLatestTodoToolInfo(messages);
      });

      it('returns its tool_info', () => {
        expect(result).toBe(expected);
      });
    });

    describe('when multiple todo_write messages are present', () => {
      const oldest = todoToolInfo([{ status: 'pending', description: 'old' }]);
      const latest = todoToolInfo([{ status: 'in_progress', description: 'new' }]);
      let result;

      beforeEach(() => {
        const messages = [
          { tool_info: oldest },
          { tool_info: otherToolInfo },
          { tool_info: latest },
        ];

        result = WorkflowUtils.findLatestTodoToolInfo(messages);
      });

      it('returns the latest tool_info', () => {
        expect(result).toBe(latest);
      });
    });

    describe('when the latest todo_write has an empty todos array', () => {
      let result;

      beforeEach(() => {
        const messages = [{ tool_info: todoToolInfo([]) }];

        result = WorkflowUtils.findLatestTodoToolInfo(messages);
      });

      it('returns null', () => {
        expect(result).toBeNull();
      });
    });

    describe('when some messages are missing tool_info', () => {
      const expected = todoToolInfo([{ status: 'completed', description: 'done' }]);
      let result;

      beforeEach(() => {
        const messages = [{}, { tool_info: null }, { tool_info: expected }];

        result = WorkflowUtils.findLatestTodoToolInfo(messages);
      });

      it('skips them and returns the latest todo_write tool_info', () => {
        expect(result).toBe(expected);
      });
    });
  });

  describe('transformChatMessages', () => {
    it('maps agent and request message types to assistant role', () => {
      const result = WorkflowUtils.transformChatMessages(MOCK_ASSISTANT_MESSAGES);

      expect(result[0].role).toBe(GENIE_CHAT_MODEL_ROLES.assistant);
      expect(result[1].role).toBe(GENIE_CHAT_MODEL_ROLES.assistant);
    });

    it('preserves original message_type for non-agent/request messages', () => {
      const result = WorkflowUtils.transformChatMessages(MOCK_SINGLE_GENERIC_MESSAGE);
      expect(result[0].role).toBe('generic');
    });

    it('preserves all original message properties', () => {
      const result = WorkflowUtils.transformChatMessages(MOCK_USER_MESSAGE_WITH_PROPERTIES);

      expect(result[0]).toEqual({
        ...MOCK_USER_MESSAGE_WITH_PROPERTIES[0],
        id: 'msg-7',
        requestId: 'msg-7',
        role: 'user',
      });
    });

    it('sets requestId to message_id for each message', () => {
      const result = WorkflowUtils.transformChatMessages(MOCK_MULTIPLE_USER_MESSAGES);

      expect(result[0].requestId).toBe('msg-4');
      expect(result[1].requestId).toBe('msg-5');
      expect(result[2].requestId).toBe('msg-6');
    });

    it('excludes orbit_context items from contextItems but keeps other additional_context', () => {
      const messages = [
        {
          message_type: 'user',
          message_id: 'msg-8',
          content: 'Test',
          additional_context: [
            { category: 'orbit_context', content: '{"orbit_enabled":false}', metadata: '{}' },
            { category: 'repository', content: 'page', metadata: { title: 'Current page' } },
          ],
        },
      ];

      const result = WorkflowUtils.transformChatMessages(messages);
      const { contextItems } = result[0].extras;

      expect(contextItems).toHaveLength(1);
      expect(contextItems[0].category).toBe('repository');
    });

    it('sets id to message_id for each message', () => {
      const result = WorkflowUtils.transformChatMessages(MOCK_MULTIPLE_USER_MESSAGES);

      expect(result[0].id).toBe('msg-4');
      expect(result[1].id).toBe('msg-5');
      expect(result[2].id).toBe('msg-6');
    });

    it('excludes permissions_form_context items from the visible contextItems', () => {
      const messages = [
        {
          message_type: 'user',
          message_id: 'msg-9',
          content: 'Test',
          additional_context: [
            {
              category: 'permissions_form_context',
              content: '{"namespace":[],"user":[],"instance":[],"access":""}',
              metadata: '{}',
            },
            { category: 'repository', content: 'page', metadata: { title: 'Current page' } },
          ],
        },
      ];

      const result = WorkflowUtils.transformChatMessages(messages);
      const { contextItems } = result[0].extras;

      expect(contextItems).toHaveLength(1);
      expect(contextItems[0].category).toBe('repository');
    });

    // The literal category, not the constant: this is the wire value Rails filters on
    // in INTERNAL_CONTEXT_CATEGORIES, so renaming the constant must not move it.
    it('excludes duo_chat_command items from the visible contextItems', () => {
      const messages = [
        {
          message_type: 'user',
          message_id: 'msg-10',
          content: 'Test',
          additional_context: [
            {
              category: 'duo_chat_command',
              content: '{"command":"flow","ai_catalog_item_consumer_id":42,"goal":null}',
              metadata: '{}',
            },
            { category: 'repository', content: 'page', metadata: { title: 'Current page' } },
          ],
        },
      ];

      const result = WorkflowUtils.transformChatMessages(messages);
      const { contextItems } = result[0].extras;

      expect(contextItems).toHaveLength(1);
      expect(contextItems[0].category).toBe('repository');
    });
  });

  describe('findParentTs', () => {
    const messages = [
      { message_id: 'msg-1', parent_ts: 'ts-0' },
      { message_id: 'msg-2', parent_ts: null },
    ];

    it('returns the parent_ts of the matching message', () => {
      expect(WorkflowUtils.findParentTs(messages, 'msg-1')).toBe('ts-0');
    });

    it('returns null when the matching message has no parent_ts', () => {
      expect(WorkflowUtils.findParentTs(messages, 'msg-2')).toBeNull();
    });

    it('returns null when no message matches', () => {
      expect(WorkflowUtils.findParentTs(messages, 'msg-3')).toBeNull();
    });

    it('returns null when no message ID is given', () => {
      expect(WorkflowUtils.findParentTs(messages, undefined)).toBeNull();
    });
  });

  describe('reconcileLoadedMessages', () => {
    const msg = (id) => ({ message_id: id, content: id });

    it('keeps the freshly streamed tail when the snapshot continues the checkpoint', () => {
      const loaded = [msg('m1'), msg('m2')];
      const pending = [msg('m1'), msg('m2'), msg('m3')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, pending)).toEqual([
        msg('m1'),
        msg('m2'),
        msg('m3'),
      ]);
    });

    it('keeps the tail when the snapshot is a truncated window of a longer thread', () => {
      const loaded = [msg('m1'), msg('m2'), msg('m3'), msg('m4'), msg('m5')];
      const pending = [msg('m4'), msg('m5'), msg('m6')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, pending)).toEqual([
        msg('m1'),
        msg('m2'),
        msg('m3'),
        msg('m4'),
        msg('m5'),
        msg('m6'),
      ]);
    });

    it('returns the loaded messages when the checkpoint already has the tail', () => {
      const loaded = [msg('m1'), msg('m2'), msg('m3')];
      const pending = [msg('m1'), msg('m2'), msg('m3')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, pending)).toEqual(loaded);
    });

    it('trusts the checkpoint when the last message diverges, e.g. a regenerated turn', () => {
      const loaded = [msg('m1'), msg('m2b')];
      const pending = [msg('m1'), msg('m2a'), msg('m3')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, pending)).toEqual(loaded);
    });

    it('returns the loaded messages when there is no snapshot', () => {
      const loaded = [msg('m1')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, [])).toEqual(loaded);
      expect(WorkflowUtils.reconcileLoadedMessages(loaded)).toEqual(loaded);
    });

    it('trusts the checkpoint when its last message lacks a message_id', () => {
      const loaded = [msg('m1'), { content: 'no id' }];
      const pending = [msg('m1'), { content: 'no id' }, msg('m3')];

      expect(WorkflowUtils.reconcileLoadedMessages(loaded, pending)).toEqual(loaded);
    });

    it('keeps the whole snapshot when the checkpoint has no messages yet', () => {
      const pending = [msg('m1'), msg('m2')];

      expect(WorkflowUtils.reconcileLoadedMessages([], pending)).toEqual(pending);
    });
  });
});
