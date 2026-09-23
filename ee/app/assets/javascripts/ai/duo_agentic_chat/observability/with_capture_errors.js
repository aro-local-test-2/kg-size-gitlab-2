import { captureExceptionForDuoChat } from './sentry_utils';

/**
 * Wraps `fn` so any error it throws synchronously, or any rejection of the
 * promise it returns, is reported to Sentry via `captureExceptionForDuoChat`
 * before being rethrown (default) or swallowed in favor of `fallback`.
 *
 * This exists for errors that are caught and recovered from -- by definition
 * they never become "unhandled", so no global error handler can ever see
 * them automatically. Wrapping the call site is the only way to get
 * consistent, tagged reporting for these without hand-writing
 * `try/catch` + `captureExceptionForDuoChat` at every one of them.
 *
 * Two calling conventions, one utility:
 *
 * Decorator-style, wrapping an entire method at definition time:
 *   methods: {
 *     onSubmit: withCaptureErrors(async function onSubmit() { ... }, { tags }),
 *   }
 *
 * Inline, wrapping a single call:
 *   await withCaptureErrors(() => ApolloUtils.fetchWorkflowEvents(...), {
 *     rethrow: false,
 *     fallback: null,
 *   })();
 *
 * `fn` is invoked with `function.apply` (not called directly), and `wrapped`
 * is declared with `function` rather than an arrow, so `this` -- the Vue
 * component instance, when used as a method decorator -- is preserved.
 *
 * @param {Function} fn - function to wrap; may be sync or return a promise.
 * @param {Object} [options]
 * @param {Object} [options.tags] - forwarded to captureExceptionForDuoChat.
 * @param {Object} [options.extra] - forwarded to captureExceptionForDuoChat.
 * @param {boolean} [options.rethrow=true] - rethrow after reporting. Set to
 *   `false` for call sites that want to swallow the error and continue.
 * @param {*} [options.fallback] - value returned when `rethrow` is `false`.
 */
export function withCaptureErrors(fn, { tags, extra, rethrow = true, fallback } = {}) {
  const handle = (err) => {
    captureExceptionForDuoChat(err, { tags, extra });
    if (rethrow) throw err;
    return fallback;
  };

  return function wrapped(...args) {
    try {
      const result = fn.apply(this, args);
      if (result && typeof result.then === 'function') {
        return result.catch(handle);
      }
      return result;
    } catch (err) {
      return handle(err);
    }
  };
}
