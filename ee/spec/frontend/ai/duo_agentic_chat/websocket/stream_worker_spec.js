import StreamWorker from 'ee/ai/duo_agentic_chat/websocket/stream_worker';

describe('stream_worker', () => {
  const TEST_URL = 'ws://localhost/api/v4/ai/duo_workflows/ws';
  const TEST_MESSAGE = { startRequest: { workflowID: '123' } };

  let worker;
  let mockSocket;
  let messages;
  let sockets;
  let OriginalWebSocket;

  beforeEach(() => {
    messages = [];

    mockSocket = {
      readyState: WebSocket.CONNECTING,
      send: jest.fn(),
      close: jest.fn(),
      onopen: null,
      onmessage: null,
      onclose: null,
      onerror: null,
    };

    OriginalWebSocket = global.WebSocket;
    global.WebSocket = jest.fn(() => mockSocket);
    sockets = [];
    global.WebSocket.OPEN = 1;
    global.WebSocket.CONNECTING = 0;

    worker = new StreamWorker();
    worker.addEventListener('message', (event) => {
      messages.push(event.data);
    });
  });

  afterEach(() => {
    worker.terminate();
    global.WebSocket = OriginalWebSocket;
  });

  describe('connect command', () => {
    it('creates a WebSocket with the given URL', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      expect(global.WebSocket).toHaveBeenCalledWith(TEST_URL);
    });

    it('sends initial message on open', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL, initialMessage: TEST_MESSAGE });
      mockSocket.readyState = WebSocket.OPEN;
      mockSocket.onopen();

      expect(mockSocket.send).toHaveBeenCalledWith(JSON.stringify(TEST_MESSAGE));
    });

    it('posts open event when socket opens', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.OPEN;
      mockSocket.onopen();

      expect(messages).toContainEqual({ type: 'open' });
    });

    it('opens without initial message when none provided', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.OPEN;
      mockSocket.onopen();

      expect(mockSocket.send).not.toHaveBeenCalled();
      expect(messages).toContainEqual({ type: 'open' });
    });

    it('closes existing socket before opening a new one', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      const firstSocket = mockSocket;
      firstSocket.readyState = WebSocket.OPEN;

      const secondSocket = {
        ...mockSocket,
        send: jest.fn(),
        close: jest.fn(),
      };
      const NewWebSocket = jest.fn(() => secondSocket);
      NewWebSocket.OPEN = 1;
      NewWebSocket.CONNECTING = 0;
      global.WebSocket = NewWebSocket;

      worker.postMessage({ type: 'connect', url: 'ws://other' });

      expect(firstSocket.close).toHaveBeenCalledWith(1000);
    });

    it('ignores close event from a replaced socket', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      const firstSocket = mockSocket;
      firstSocket.readyState = WebSocket.OPEN;

      const secondSocket = {
        readyState: WebSocket.CONNECTING,
        send: jest.fn(),
        close: jest.fn(),
        onopen: null,
        onmessage: null,
        onclose: null,
        onerror: null,
      };
      global.WebSocket = jest.fn(() => secondSocket);
      global.WebSocket.OPEN = 1;
      global.WebSocket.CONNECTING = 0;

      worker.postMessage({ type: 'connect', url: 'ws://other' });

      // Old socket fires close event asynchronously after being replaced
      firstSocket.onclose({ code: 1000, reason: 'replaced' });

      // Should NOT receive a close event from the old socket
      expect(messages).not.toContainEqual(expect.objectContaining({ type: 'close', code: 1000 }));
    });
  });

  describe('message forwarding', () => {
    it('parses string messages as JSON', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      const action = { newCheckpoint: { status: 'RUNNING' } };
      mockSocket.onmessage({ data: JSON.stringify(action) });

      expect(messages).toContainEqual({ type: 'message', data: action });
    });

    it('parses the nested checkpoint string inside newCheckpoint', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      const checkpoint = { channel_values: { ui_chat_log: [] } };
      const action = {
        newCheckpoint: { status: 'RUNNING', checkpoint: JSON.stringify(checkpoint) },
      };
      mockSocket.onmessage({ data: JSON.stringify(action) });

      expect(messages).toContainEqual({
        type: 'message',
        data: { newCheckpoint: { status: 'RUNNING', checkpoint } },
      });
    });

    it('posts an error event for non-parseable messages', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      mockSocket.onmessage({ data: 'not valid json{{{' });

      expect(messages).toContainEqual(expect.objectContaining({ type: 'error', origin: 'decode' }));
      expect(messages).not.toContainEqual(expect.objectContaining({ type: 'message' }));
    });

    it('parses Blob messages as JSON', async () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      const action = { newCheckpoint: { status: 'RUNNING' } };
      const blob = { text: () => Promise.resolve(JSON.stringify(action)) };
      mockSocket.onmessage({ data: blob });

      await new Promise(process.nextTick);

      expect(messages).toContainEqual({ type: 'message', data: action });
    });

    it('posts error with decode origin and details when Blob text() rejects', async () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      const blob = { text: () => Promise.reject(new Error('read failed')) };
      mockSocket.onmessage({ data: blob });

      await new Promise(process.nextTick);

      expect(messages).toContainEqual(
        expect.objectContaining({ type: 'error', origin: 'decode', message: 'read failed' }),
      );
      expect(messages).not.toContainEqual(expect.objectContaining({ type: 'message' }));
    });

    it('parses ArrayBuffer messages as JSON', async () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      const action = { newCheckpoint: { status: 'RUNNING' } };
      const { buffer } = new TextEncoder().encode(JSON.stringify(action));
      mockSocket.onmessage({ data: buffer });

      await new Promise(process.nextTick);
      await new Promise(process.nextTick);

      expect(messages).toContainEqual({ type: 'message', data: action });
    });

    it('falls back to String() for unknown payload types', async () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });

      mockSocket.onmessage({ data: 42 });

      await new Promise(process.nextTick);
      await new Promise(process.nextTick);

      // String(42) → '42', which JSON.parse yields the number 42
      expect(messages).toContainEqual({ type: 'message', data: 42 });
    });
  });

  describe('close event', () => {
    it('forwards close code and reason', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.onclose({ code: 1013, reason: 'flow locked' });

      expect(messages).toContainEqual({ type: 'close', code: 1013, reason: 'flow locked' });
    });
  });

  describe('send command', () => {
    it('sends JSON message through open socket', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.OPEN;

      const payload = { approval: { approved: true } };
      worker.postMessage({ type: 'send', message: payload });

      expect(mockSocket.send).toHaveBeenCalledWith(JSON.stringify(payload));
    });

    it('does not send when socket is not open', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.CONNECTING;

      worker.postMessage({ type: 'send', message: { test: true } });

      expect(mockSocket.send).not.toHaveBeenCalled();
    });
  });

  describe('disconnect command', () => {
    it('closes open socket with code 1000', () => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.OPEN;

      worker.postMessage({ type: 'disconnect' });

      expect(mockSocket.close).toHaveBeenCalledWith(1000);
    });

    it('does nothing when no socket exists', () => {
      expect(() => {
        worker.postMessage({ type: 'disconnect' });
      }).not.toThrow();
    });
  });

  // NODE_ENV is `test` here, so the worker wraps the socket in DwsMockWebSocket and these
  // commands are live. In production the real WebSocket is used and they are inert.
  describe('mockEvent command', () => {
    beforeEach(() => {
      worker.postMessage({ type: 'connect', url: TEST_URL });
      mockSocket.readyState = WebSocket.OPEN;
      mockSocket.onopen();
      messages.length = 0;
    });

    it('posts a close event with the requested code', () => {
      worker.postMessage({
        type: 'mockEvent',
        event: 'close',
        payload: { code: 1013, reason: 'try later' },
      });

      expect(messages).toEqual([{ type: 'close', code: 1013, reason: 'try later' }]);
    });

    it('closes the wrapped socket when synthesising a close', () => {
      worker.postMessage({ type: 'mockEvent', event: 'close', payload: { code: 1001 } });

      expect(mockSocket.close).toHaveBeenCalled();
    });

    // This worker no longer assigns `ws.onerror`, so there is nothing for a synthetic
    // error to invoke. Asserted rather than dropped so the gap stays visible: reaching
    // the client's error path currently means an unclean close (1006), not `error()`.
    it('posts nothing for a synthetic error, because onerror is not handled', () => {
      worker.postMessage({ type: 'mockEvent', event: 'error' });

      expect(messages).toEqual([]);
    });

    it('posts a message event, parsed like any other incoming frame', () => {
      worker.postMessage({
        type: 'mockEvent',
        event: 'message',
        payload: { data: '{"newCheckpoint":{"status":"running"}}' },
      });

      expect(messages).toEqual([
        { type: 'message', data: { newCheckpoint: { status: 'running' } } },
      ]);
    });

    it('does nothing when no socket exists', () => {
      worker.postMessage({ type: 'disconnect' });
      messages.length = 0;

      expect(() => {
        worker.postMessage({ type: 'mockEvent', event: 'close' });
      }).not.toThrow();
      expect(messages).toEqual([]);
    });
  });

  // Queued responses answer connections that do not exist yet, which is the only
  // way to fail a reconnect: one that reaches the real service gets a real reply,
  // and RetryableWorkflowStream treats any frame as progress and resets its count.
  describe('mockQueue command', () => {
    // Each connect() wraps its own socket, so a reconnect must be given a new one.
    const reconnect = () => {
      const next = {
        readyState: WebSocket.OPEN,
        send: jest.fn(),
        close: jest.fn(),
        onopen: null,
        onmessage: null,
        onclose: null,
        onerror: null,
      };
      sockets.push(next);
      global.WebSocket.mockReturnValueOnce(next);

      worker.postMessage({ type: 'connect', url: TEST_URL });
      next.onopen();

      return next;
    };

    beforeEach(() => {
      worker.postMessage({ type: 'mockQueue', entries: { close: 1006, times: 2 } });
      messages.length = 0;
    });

    afterEach(() => {
      worker.postMessage({ type: 'mockQueueClear' });
    });

    it('closes the reconnect that follows, after reporting it open', () => {
      reconnect();

      expect(messages).toEqual([{ type: 'open' }, { type: 'close', code: 1006, reason: '' }]);
    });

    it('spends one entry per connection', () => {
      reconnect();
      reconnect();
      const third = reconnect();

      const closes = messages.filter(({ type }) => type === 'close');
      expect(closes).toHaveLength(2);
      // The queue is empty by now, so this connection is left to the real server.
      expect(third.onmessage).not.toBeNull();
    });

    // Without this the server's reply would still arrive and count as progress.
    it('detaches the socket, so a reply after the scripted close cannot land', () => {
      const socket = reconnect();
      messages.length = 0;

      expect(socket.onmessage).toBeNull();
      expect(socket.close).toHaveBeenCalled();
      expect(messages).toEqual([]);
    });

    it('leaves the reconnect alone once the queue is cleared', () => {
      worker.postMessage({ type: 'mockQueueClear' });

      reconnect();

      expect(messages).toEqual([{ type: 'open' }]);
    });
  });
});
