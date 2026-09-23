/**
 * A transparent wrapper around `WebSocket` for local development and tests.
 *
 * It behaves exactly like the socket it wraps, so Duo Chat still talks to a real
 * Duo Workflow Service. On top of that it can synthesise `open`, `message`, `close`
 * and `error` events on demand, which lets connection-error handling be exercised
 * against close codes a real backend will not produce (1006, 1008, 1013, ...).
 *
 * Responses can also be queued ahead of time, so reconnections the client has not
 * made yet answer as scripted instead of reaching the real service.
 *
 * Only used when DWS_MOCK_WEBSOCKET_ENABLED; see stream_worker.js. Drive it from the browser console
 * through `gl.dwsMockSocket`; see exposeMockSocket below.
 */
export const DWS_MOCK_WEBSOCKET_ENABLED =
  process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test';

/**
 * Responses scripted for connections that do not exist yet, one entry per
 * connection, consumed in order.
 *
 * Module scope rather than instance state on purpose: every reconnect builds a
 * new DwsMockWebSocket, so a queue owned by the socket that was closed would die
 * with it. Holding it here is what makes a retry cascade reproducible -- each
 * reconnect gets its scripted response instead of the real server's reply, which
 * would otherwise arrive, count as progress, and reset the retry counter.
 */
const scriptedResponses = [];

const toScriptedEvent = (entry) => {
  if (typeof entry?.close === 'number') {
    return { event: 'close', payload: { code: entry.close, reason: entry.reason ?? '' } };
  }
  if (typeof entry?.message === 'string') {
    return { event: 'message', payload: { data: entry.message } };
  }
  if (entry?.error) {
    return { event: 'error', payload: {} };
  }

  throw new Error(
    'Scripted responses look like { close: 1006 }, { message: \'{"newCheckpoint":{}}\' } or { error: true }',
  );
};

/**
 * Scripts the next connections. `times` repeats an entry, so three failures in a
 * row is one call. Returns how many responses are now queued.
 */
export function queueScriptedResponses(entries) {
  const list = Array.isArray(entries) ? entries : [entries];

  list.forEach((entry) => {
    const scripted = toScriptedEvent(entry);

    for (let i = 0; i < (entry.times ?? 1); i += 1) {
      scriptedResponses.push(scripted);
    }
  });

  return scriptedResponses.length;
}

export function clearScriptedResponses() {
  scriptedResponses.length = 0;
}

export class DwsMockWebSocket {
  #socket;
  #scripted;

  constructor(url) {
    // Claimed at construction, not on open, so two connections opening at once
    // cannot both take the same entry.
    this.#scripted = scriptedResponses.shift() ?? null;

    this.#socket = new WebSocket(url);

    this.#socket.onopen = (event) => {
      this.onopen?.(event);
      this.#applyScriptedResponse();
    };
    this.#socket.onmessage = (event) => this.onmessage?.(event);
    this.#socket.onclose = (event) => this.onclose?.(event);
    this.#socket.onerror = (event) => this.onerror?.(event);
  }

  get readyState() {
    return this.#socket.readyState;
  }

  // Forwarded with rest args rather than named ones so the wrapped socket is called
  // with exactly the arguments it was given, not padded with `undefined`.
  send(...args) {
    this.#socket.send(...args);
  }

  close(...args) {
    this.#socket.close(...args);
  }

  /**
   * Invokes one of the `on*` handlers as though the server had produced the event.
   *
   * A synthesised `close` also tears down the wrapped socket, otherwise the client
   * would reconnect while the old connection is still open and the real `close`
   * would arrive later as a second, unexpected event.
   */
  dispatchMockEvent(event, payload = {}) {
    switch (event) {
      case 'open':
        this.onopen?.({});
        break;
      case 'message':
        if (!payload?.data) {
          throw new Error(
            // eslint-disable-next-line @gitlab/require-i18n-strings
            'You should provide a message payload. The websocket message event listener will not be emitted.',
          );
        }
        this.onmessage?.({ data: payload.data });
        break;
      case 'error':
        this.onerror?.({});
        break;
      case 'close':
        this.#detachAndClose();
        this.onclose?.({ code: payload.code ?? 1006, reason: payload.reason ?? '' });
        break;
      default:
        break;
    }
  }

  /**
   * Runs after the client has seen the connection open and sent whatever it sends
   * on open, so a scripted close stands in for the server's reply rather than
   * racing it: the socket is detached and closed before the network can answer.
   */
  #applyScriptedResponse() {
    if (!this.#scripted) return;

    const { event, payload } = this.#scripted;
    this.#scripted = null;

    this.dispatchMockEvent(event, payload);
  }

  #detachAndClose() {
    this.#socket.onopen = null;
    this.#socket.onmessage = null;
    this.#socket.onclose = null;
    this.#socket.onerror = null;
    this.#socket.close();
  }
}

/**
 * Exposes `gl.dwsMockSocket` in development and test builds, so connection failures
 * can be reproduced from the browser console against a live backend:
 *
 *   gl.dwsMockSocket.close(1001)   // retryable, expect a silent reconnect
 *   gl.dwsMockSocket.close(1013)   // non-retryable, expect the stream to stop
 *   gl.dwsMockSocket.error()
 *   gl.dwsMockSocket.message('{"newCheckpoint":{}}')
 *
 * `queue` scripts connections that do not exist yet, which is the only way to
 * exhaust the retry budget against a live backend -- a reconnect that reaches the
 * real service gets a real reply, and that resets the counter:
 *
 *   gl.dwsMockSocket.queue({ close: 1006, times: 3 })  // the next 3 connections
 *   gl.dwsMockSocket.close(1006)                       // start the cascade
 *   gl.dwsMockSocket.clearQueue()                      // back to the real server
 *
 * The worker forwards these to DwsMockWebSocket, which invokes the corresponding handler
 * as though the server had produced the event.
 */
export function exposeMockSocket(getWorker) {
  const post = (message) => getWorker()?.postMessage(message);
  const emit = (event, payload) => post({ type: 'mockEvent', event, payload });

  window.gl = window.gl || {};
  window.gl.dwsMockSocket = {
    close: (code = 1006, reason = '') => emit('close', { code, reason }),
    error: () => emit('error'),
    message: (data) => emit('message', { data }),
    open: () => emit('open'),
    queue: (entries) => post({ type: 'mockQueue', entries }),
    clearQueue: () => post({ type: 'mockQueueClear' }),
  };
}
