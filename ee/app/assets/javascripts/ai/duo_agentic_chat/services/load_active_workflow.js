import { ApolloUtils } from '../utils/apollo_utils';
import { WorkflowUtils } from '../utils/workflow_utils';
import {
  THREAD_LOAD_MAX_ATTEMPTS,
  THREAD_LOAD_RETRY_DELAY_MS,
  THREAD_LOAD_TERMINAL_ERROR_CODES,
} from '../constants';

const ABORT_ERROR_NAME = 'ThreadLoadAbortedError';

const hasGraphQLErrorCode = (error, code) =>
  error?.graphQLErrors?.some((e) => e?.extensions?.code === code);

// Terminal failures (deleted workflow, permission denied) have dedicated
// handlers a retry can never satisfy, so only other failures are retried.
const isRetryableError = (error) =>
  !THREAD_LOAD_TERMINAL_ERROR_CODES.some((code) => hasGraphQLErrorCode(error, code));

const abortError = () => {
  // eslint-disable-next-line @gitlab/require-i18n-strings
  const error = new Error('Loading the chat thread was cancelled');
  error.name = ABORT_ERROR_NAME;
  return error;
};

const wait = (delayMs, signal) =>
  new Promise((resolve, reject) => {
    let onAbort;

    const timeoutId = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, delayMs);

    onAbort = () => {
      clearTimeout(timeoutId);
      reject(abortError());
    };

    signal?.addEventListener('abort', onAbort, { once: true });
  });

/**
 * True when the load was cancelled through its `signal` (thread switch,
 * unmount); callers should drop the result rather than surface an error.
 */
export const isThreadLoadAborted = (error) => error?.name === ABORT_ERROR_NAME;

/**
 * Loads a saved chat thread, retrying transient failures.
 *
 * Resolves with the thread's data once an attempt succeeds; rejects with the
 * last error when the retries are exhausted or the failure is terminal, and
 * with an abort error when `signal` is aborted.
 *
 * @param {Object} apollo - Apollo client (or Vue `$apollo`)
 * @param {String} workflowId - GraphQL id of the workflow to load
 * @param {Object} [options]
 * @param {AbortSignal} [options.signal] - cancels a pending retry
 * @param {Function} [options.onRetry] - called before each retry wait
 */
export const loadActiveWorkflowWithRetry = async (
  apollo,
  workflowId,
  {
    signal,
    onRetry = () => {},
    maxAttempts = THREAD_LOAD_MAX_ATTEMPTS,
    retryDelayMs = THREAD_LOAD_RETRY_DELAY_MS,
  } = {},
) => {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    let data = null;

    try {
      // eslint-disable-next-line no-await-in-loop
      data = await ApolloUtils.fetchWorkflowEvents(apollo, workflowId);
    } catch (error) {
      if (attempt === maxAttempts || !isRetryableError(error)) throw error;

      onRetry(error);
      // eslint-disable-next-line no-await-in-loop
      await wait(retryDelayMs, signal);
    }

    if (data) {
      if (signal?.aborted) throw abortError();

      const [workflow] = data.duoWorkflowWorkflows.nodes ?? [];
      const latestCheckpoint = WorkflowUtils.parseWorkflowData(data);

      return {
        workflow,
        workflowStatus: latestCheckpoint?.workflowStatus,
        workflowGoal: latestCheckpoint?.workflowGoal,
        messages: WorkflowUtils.transformChatMessages(
          WorkflowUtils.normalizeDuoMessages(latestCheckpoint?.duoMessages || []),
        ),
      };
    }
  }

  return null; // unreachable: the loop always returns or throws
};
