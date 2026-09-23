import createEventHub from '~/helpers/event_hub_factory';
import { CHAT_MESSAGE_TYPES } from 'ee/ai/constants';
import { processWorkflowMessage } from 'ee/ai/duo_agentic_chat/websocket/workflow_utils';
import {
  DUO_CHAT_TOOL_REQUESTED_EVENT,
  DUO_CHAT_TOOL_COMPLETED_EVENT,
  DUO_CHAT_TOOL_FAILURE_EVENT,
  initDuoAgenticChatEventHub,
  subscribeToEvent,
} from 'ee/ai/duo_agentic_chat/events/event_hub';

// createEventHub is called at module level, so the factory must return a stable
// mock hub that all tests can reference via createEventHub().
jest.mock('~/helpers/event_hub_factory', () => {
  const mockHub = { $emit: jest.fn(), $on: jest.fn(), $off: jest.fn() };
  return jest.fn(() => mockHub);
});
jest.mock('ee/ai/duo_agentic_chat/websocket/workflow_utils');

function makeStreamMock() {
  const subscribedHandlers = {};
  const subscriptionDisposables = {};

  return {
    subscribe: jest.fn().mockImplementation((event, handler) => {
      subscribedHandlers[event] = handler;
      const dispose = jest.fn();
      subscriptionDisposables[event] = dispose;
      return { dispose };
    }),
    subscribedHandlers,
    subscriptionDisposables,
  };
}

describe('duo agentic chat event hub', () => {
  let mockEventHub;
  let mockStream;
  let disposable;

  beforeEach(() => {
    // Calling the mock returns the same stable hub object every time.
    mockEventHub = createEventHub();
    mockEventHub.$emit.mockClear();
    mockEventHub.$on.mockClear();
    mockEventHub.$off.mockClear();

    mockStream = makeStreamMock();
    disposable = initDuoAgenticChatEventHub(mockStream);
  });

  afterEach(() => {
    disposable.dispose();
  });

  it('creates an event hub at module level', () => {
    expect(createEventHub).toHaveBeenCalled();
  });

  it('subscribes to stream open and message events', () => {
    expect(mockStream.subscribe).toHaveBeenCalledWith('open', expect.any(Function));
    expect(mockStream.subscribe).toHaveBeenCalledWith('message', expect.any(Function));
  });

  describe('subscribeToEvent', () => {
    it('registers a handler on the event hub', () => {
      const handler = jest.fn();
      subscribeToEvent(DUO_CHAT_TOOL_COMPLETED_EVENT, handler);

      expect(mockEventHub.$on).toHaveBeenCalledWith(DUO_CHAT_TOOL_COMPLETED_EVENT, handler);
    });

    it('returns a disposable that unregisters the handler', () => {
      const handler = jest.fn();
      const subscription = subscribeToEvent(DUO_CHAT_TOOL_COMPLETED_EVENT, handler);
      subscription.dispose();

      expect(mockEventHub.$off).toHaveBeenCalledWith(DUO_CHAT_TOOL_COMPLETED_EVENT, handler);
    });
  });

  describe('disposable', () => {
    it('disposes open and message subscriptions on dispose', () => {
      disposable.dispose();

      expect(mockStream.subscriptionDisposables.open).toHaveBeenCalled();
      expect(mockStream.subscriptionDisposables.message).toHaveBeenCalled();
    });
  });

  describe('stream message → hub event emission', () => {
    const triggerMessage = async (messages, lastProcessedMessageId = 'msg-1') => {
      processWorkflowMessage.mockReturnValue({ messages, lastProcessedMessageId });
      await mockStream.subscribedHandlers.message({ data: 'test' });
    };

    it('emits DUO_CHAT_TOOL_REQUESTED_EVENT for request-type messages', async () => {
      await triggerMessage([
        {
          message_id: 'msg-req',
          message_type: CHAT_MESSAGE_TYPES.request,
          tool_info: { name: 'create_commit', args: {} },
        },
      ]);

      expect(mockEventHub.$emit).toHaveBeenCalledWith(DUO_CHAT_TOOL_REQUESTED_EVENT, {
        messageId: 'msg-req',
        name: 'create_commit',
      });
    });

    it('emits DUO_CHAT_TOOL_COMPLETED_EVENT with messageId for successful tool messages', async () => {
      await triggerMessage([
        {
          message_id: 'msg-ok',
          message_type: CHAT_MESSAGE_TYPES.tool,
          status: 'success',
          tool_info: {
            name: 'update_form',
            args: { select: ['read'] },
            tool_response: { status: 'success' },
          },
        },
      ]);

      expect(mockEventHub.$emit).toHaveBeenCalledWith(DUO_CHAT_TOOL_COMPLETED_EVENT, {
        messageId: 'msg-ok',
        name: 'update_form',
        args: { select: ['read'] },
      });
    });

    // A failed tool call arrives with no tool_response, so the status and the
    // failure text are only available on the message itself.
    it('emits DUO_CHAT_TOOL_FAILURE_EVENT with messageId and content for failed tool messages', async () => {
      await triggerMessage([
        {
          message_id: 'msg-fail',
          message_type: CHAT_MESSAGE_TYPES.tool,
          status: 'failure',
          content: 'Failed: run_command - Tool call failed: ToolException',
          tool_info: {
            name: 'run_command',
            args: {},
          },
        },
      ]);

      expect(mockEventHub.$emit).toHaveBeenCalledWith(DUO_CHAT_TOOL_FAILURE_EVENT, {
        messageId: 'msg-fail',
        name: 'run_command',
        content: 'Failed: run_command - Tool call failed: ToolException',
      });
    });

    it('does not emit when the message carries no status', async () => {
      await triggerMessage([
        {
          message_id: 'msg-pending',
          message_type: CHAT_MESSAGE_TYPES.tool,
          tool_info: { name: 'run_command', args: {} },
        },
      ]);

      expect(mockEventHub.$emit).not.toHaveBeenCalled();
    });

    it('does not emit for agent messages', async () => {
      await triggerMessage([
        { message_type: CHAT_MESSAGE_TYPES.agent, tool_info: { name: 'some_tool', args: {} } },
      ]);

      expect(mockEventHub.$emit).not.toHaveBeenCalled();
    });

    it('does not emit when tool_info has no name', async () => {
      await triggerMessage([{ message_type: CHAT_MESSAGE_TYPES.tool, tool_info: { args: {} } }]);

      expect(mockEventHub.$emit).not.toHaveBeenCalled();
    });

    it('does not emit when processWorkflowMessage returns null', async () => {
      processWorkflowMessage.mockReturnValue(null);
      await mockStream.subscribedHandlers.message({ data: 'test' });

      expect(mockEventHub.$emit).not.toHaveBeenCalled();
    });
  });
});
