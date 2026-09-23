import { ApolloLink, Observable } from '@apollo/client/core';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { duoChatApolloErrorLink } from 'ee/ai/duo_agentic_chat/observability/apollo_error_link';
import {
  NO_DEFAULT_NAMESPACE_CODE,
  WORKFLOW_NOT_FOUND_CODE,
  NO_RESOURCE_PERMISSIONS,
} from 'ee/ai/duo_agentic_chat/constants';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('duoChatApolloErrorLink', () => {
  let subscription;

  afterEach(() => {
    subscription?.unsubscribe();
    jest.clearAllMocks();
  });

  const makeMockGraphQLErrorLink = (extensions) =>
    new ApolloLink(() =>
      Observable.of({
        errors: [{ message: 'something failed', extensions }],
      }),
    );

  const makeMockNetworkErrorLink = () =>
    new ApolloLink(
      () =>
        new Observable(() => {
          throw new Error('NetworkError');
        }),
    );

  const makeMockSuccessLink = () => new ApolloLink(() => Observable.of({ data: { foo: 1 } }));

  const createSubscription = (otherLink, observer, operationName = 'getThings') => {
    const mockOperation = { operationName };
    const link = duoChatApolloErrorLink.concat(otherLink);
    subscription = link.request(mockOperation).subscribe(observer);
  };

  // The mock links below emit synchronously from inside the initial `subscribe()`
  // call. zen-observable defers notifications raised during that initial,
  // still-initializing phase to a microtask (see zen-observable's `onNotify`),
  // so callbacks and side effects triggered by them are only observable after
  // flushing pending promises.
  it('does not report successful responses', async () => {
    createSubscription(makeMockSuccessLink(), {
      next({ data }) {
        expect(data).toEqual({ foo: 1 });
      },
    });
    await waitForPromises();

    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('reports a network error, tagged with the operation name', async () => {
    createSubscription(makeMockNetworkErrorLink(), { error: () => {} }, 'getThings');
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'NetworkError' }),
      { tags: { feature_category: 'duo_chat', operation_name: 'getThings' } },
    );
  });

  it('still forwards the network error to the next subscriber', async () => {
    const spy = jest.fn();
    createSubscription(makeMockNetworkErrorLink(), { error: spy });
    await waitForPromises();

    expect(spy).toHaveBeenCalledWith(expect.objectContaining({ message: 'NetworkError' }));
  });

  it('reports a graphQL error, tagged with the operation name and error code', async () => {
    createSubscription(
      makeMockGraphQLErrorLink({ code: 'SOME_ERROR' }),
      { next: () => {} },
      'getThings',
    );
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'something failed' }),
      {
        tags: {
          feature_category: 'duo_chat',
          operation_name: 'getThings',
          graphql_error_code: 'SOME_ERROR',
        },
        // The error is constructed inside the link, so stack-based grouping
        // would collapse every operation into one Sentry issue.
        fingerprint: ['duo_chat_graphql_error', 'getThings', 'SOME_ERROR'],
      },
    );
  });

  it('still forwards the response to the next subscriber', async () => {
    const spy = jest.fn();
    createSubscription(makeMockGraphQLErrorLink({ code: 'SOME_ERROR' }), {
      next: spy,
    });
    await waitForPromises();

    expect(spy).toHaveBeenCalledWith(
      expect.objectContaining({
        errors: [expect.objectContaining({ message: 'something failed' })],
      }),
    );
  });

  it.each([NO_DEFAULT_NAMESPACE_CODE, WORKFLOW_NOT_FOUND_CODE, NO_RESOURCE_PERMISSIONS])(
    'does not report an expected/already-routed graphQL error code (%s)',
    async (code) => {
      createSubscription(makeMockGraphQLErrorLink({ code }), { next: () => {} });
      await waitForPromises();

      expect(Sentry.captureException).not.toHaveBeenCalled();
    },
  );

  it('reports a graphQL error with no extensions code, fingerprinted by message', async () => {
    createSubscription(makeMockGraphQLErrorLink(undefined), { next: () => {} });
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'something failed' }),
      expect.objectContaining({
        tags: expect.objectContaining({ graphql_error_code: undefined }),
        fingerprint: ['duo_chat_graphql_error', 'getThings', 'something failed'],
      }),
    );
  });
});
