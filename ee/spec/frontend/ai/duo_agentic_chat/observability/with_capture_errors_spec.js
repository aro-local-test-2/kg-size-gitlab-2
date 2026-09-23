import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { withCaptureErrors } from 'ee/ai/duo_agentic_chat/observability/with_capture_errors';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('duo_agentic_chat/observability/with_capture_errors', () => {
  const error = new Error('something went wrong');

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('with a synchronous function', () => {
    it('returns the result when there is no error', () => {
      const wrapped = withCaptureErrors(() => 'result');

      expect(wrapped()).toBe('result');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('reports and rethrows by default', () => {
      const wrapped = withCaptureErrors(() => {
        throw error;
      });

      expect(() => wrapped()).toThrow(error);
      expect(Sentry.captureException).toHaveBeenCalledWith(error, expect.objectContaining({}));
    });

    it('reports and returns the fallback when rethrow is false', () => {
      const wrapped = withCaptureErrors(
        () => {
          throw error;
        },
        { rethrow: false, fallback: 'fallback-value' },
      );

      expect(wrapped()).toBe('fallback-value');
      expect(Sentry.captureException).toHaveBeenCalledWith(error, expect.objectContaining({}));
    });

    it('forwards tags and extra to captureExceptionForDuoChat', () => {
      const wrapped = withCaptureErrors(
        () => {
          throw error;
        },
        { rethrow: false, tags: { tool_name: 'create_commit' }, extra: { messageId: 'msg-1' } },
      );

      wrapped();

      expect(Sentry.captureException).toHaveBeenCalledWith(error, {
        tags: { feature_category: 'duo_chat', tool_name: 'create_commit' },
        extra: { messageId: 'msg-1' },
      });
    });
  });

  describe('with an async function', () => {
    it('resolves with the result when there is no error', async () => {
      const wrapped = withCaptureErrors(() => Promise.resolve('result'));

      await expect(wrapped()).resolves.toBe('result');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('reports and rethrows the rejection by default', async () => {
      const wrapped = withCaptureErrors(() => Promise.reject(error));

      await expect(wrapped()).rejects.toBe(error);
      expect(Sentry.captureException).toHaveBeenCalledWith(error, expect.objectContaining({}));
    });

    it('reports and resolves with the fallback when rethrow is false', async () => {
      const wrapped = withCaptureErrors(() => Promise.reject(error), {
        rethrow: false,
        fallback: null,
      });

      await expect(wrapped()).resolves.toBe(null);
      expect(Sentry.captureException).toHaveBeenCalledWith(error, expect.objectContaining({}));
    });
  });

  describe('this binding', () => {
    it('preserves `this` when used as a method decorator', () => {
      const obj = {
        value: 'instance-value',
        getValue: withCaptureErrors(function getValue() {
          return this.value;
        }),
      };

      expect(obj.getValue()).toBe('instance-value');
    });

    it('forwards call arguments to the wrapped function', () => {
      const wrapped = withCaptureErrors((a, b) => a + b);

      expect(wrapped(1, 2)).toBe(3);
    });
  });
});
