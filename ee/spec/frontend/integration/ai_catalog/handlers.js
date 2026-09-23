import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { cloneDeep } from 'lodash-es';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import aiCatalogAgentVariants from './fixture_variants/ai_catalog_agent';
import aiCatalogFlowVariants from './fixture_variants/ai_catalog_flow';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ai_catalog/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const agentResponse = fixtures.aiCatalogAgent;
export const agentPinnedToLatestResponse = fixtures.aiCatalogAgentPinnedToLatest;
export const flowResponse = fixtures.aiCatalogFlow;
export const flowPinnedToLatestResponse = fixtures.aiCatalogFlowPinnedToLatest;
export const updateConsumerResponse = fixtures.updateAiCatalogItemConsumer;

export { aiCatalogAgentVariants, aiCatalogFlowVariants };

let agentCache = cloneDeep(agentResponse);
let flowCache = cloneDeep(flowResponse);

export function resetAiCatalogCache() {
  agentCache = cloneDeep(agentResponse);
  flowCache = cloneDeep(flowResponse);
}

const FIXTURE_RESPONSES = {
  ...fixtures,
};

const STATIC_OPERATION_HANDLERS = Object.fromEntries(
  Object.entries(FIXTURE_RESPONSES).map(([operationName, fixture]) => [
    operationName,
    () => fixture,
  ]),
);

// A variant selects the starting shape; otherwise serve the cache the mutation swaps.
STATIC_OPERATION_HANDLERS.aiCatalogAgent = () => getActiveVariant('aiCatalogAgent') ?? agentCache;
STATIC_OPERATION_HANDLERS.aiCatalogFlow = () => getActiveVariant('aiCatalogFlow') ?? flowCache;

const MUTATION_OPERATION_HANDLERS = {
  updateAiCatalogItemConsumer: () => {
    // Swap query caches to "pinned to latest" so refetch returns updated state
    agentCache = cloneDeep(agentPinnedToLatestResponse);
    flowCache = cloneDeep(flowPinnedToLatestResponse);

    return cloneDeep(updateConsumerResponse);
  },
};

const OPERATION_HANDLERS = {
  ...STATIC_OPERATION_HANDLERS,
  ...MUTATION_OPERATION_HANDLERS,
};

export function handleAiCatalogOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  const payload = handler({ operationName, variables });

  return HttpResponse.json(payload);
}

export const aiCatalogRestEndpoints = [];
