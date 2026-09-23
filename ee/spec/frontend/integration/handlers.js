import { graphql, http, HttpResponse } from 'msw';
import { handleWorkItemOperation, workItemRestEndpoints } from './work_items/handlers';
import { captureMissingOperation, captureRequest } from './core/operation_helpers';
import { handleAiCatalogOperation, aiCatalogRestEndpoints } from './ai_catalog/handlers';
import { handleCdEnvironmentOperation, cdEnvironmentRestEndpoints } from './cd/handlers';
import { handleCommitListOperation, commitListRestEndpoints } from './commits/handlers';

export const featureHandlers = [
  handleWorkItemOperation,
  handleAiCatalogOperation,
  handleCdEnvironmentOperation,
  handleCommitListOperation,
];
export const restEndpoints = [
  ...workItemRestEndpoints,
  ...aiCatalogRestEndpoints,
  ...cdEnvironmentRestEndpoints,
  ...commitListRestEndpoints,
];

export function buildHandlers(allFeatureHandlers, allRestEndpoints) {
  const restEndpointsHandlers = allRestEndpoints.map((endpoint) =>
    http[endpoint.method](endpoint.path, ({ request }) => {
      const operationName = endpoint.name || `REST:${endpoint.method}:${endpoint.path}`;
      captureRequest(operationName, request);

      return HttpResponse.json(endpoint.response, { headers: endpoint.headers });
    }),
  );

  return [
    graphql.operation(({ operationName, variables, request }) => {
      for (const handler of allFeatureHandlers) {
        const result = handler({ operationName, variables });
        if (result) {
          captureRequest(operationName, request, variables);
          return result;
        }
      }

      captureMissingOperation(operationName);
      return new HttpResponse(null, { status: 400 });
    }),

    ...restEndpointsHandlers,

    http.get('*', ({ request }) => {
      // eslint-disable-next-line no-console
      console.log(`Unhandled url for REST endpoint: ${request.url}`);
      return new HttpResponse(null, { status: 400 });
    }),
  ];
}
