import { onError } from '@apollo/client/link/error';
import {
  NO_DEFAULT_NAMESPACE_CODE,
  WORKFLOW_NOT_FOUND_CODE,
  NO_RESOURCE_PERMISSIONS,
} from '../constants';
import { captureExceptionForDuoChat } from './sentry_utils';

// Business errors that are already routed to a dedicated UI state elsewhere
// (see routeWorkflowError / threadLoadErrorHandlers in the state managers).
// They are expected outcomes, not bugs, so reporting them here would just be
// noise on top of what the owning component already decided about them.
const EXPECTED_GRAPHQL_ERROR_CODES = new Set([
  NO_DEFAULT_NAMESPACE_CODE,
  WORKFLOW_NOT_FOUND_CODE,
  NO_RESOURCE_PERMISSIONS,
]);

/**
 * Reports every GraphQL/network error flowing through the Duo Chat Apollo
 * client to Sentry, tagged with the operation name -- so a query or mutation
 * doesn't need its own `error()` handler just to get observability. Handlers
 * that already exist keep working unchanged: this link never alters the
 * response, it only observes it.
 */
export const duoChatApolloErrorLink = onError(({ graphQLErrors, networkError, operation }) => {
  const { operationName } = operation;

  if (networkError) {
    captureExceptionForDuoChat(networkError, { tags: { operation_name: operationName } });
  }

  graphQLErrors?.forEach((graphQLError) => {
    const code = graphQLError?.extensions?.code;
    if (code && EXPECTED_GRAPHQL_ERROR_CODES.has(code)) return;

    // `new Error()` here gives every event the same stack and type, which
    // Sentry's default grouping would collapse into a single issue. Fingerprint
    // by operation + code so distinct failures stay triageable.
    captureExceptionForDuoChat(new Error(graphQLError.message), {
      tags: { operation_name: operationName, graphql_error_code: code },
      fingerprint: [
        'duo_chat_graphql_error',
        operationName ?? 'unknown',
        code ?? graphQLError.message,
      ],
    });
  });

  return undefined;
});
