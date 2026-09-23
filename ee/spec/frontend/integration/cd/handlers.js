import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { cloneDeep } from 'lodash-es';
import { loadFixturesMap, matchFixture } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import cdEnvironmentsVariants from './fixture_variants/cd_environments';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/cd/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const environmentsResponse = fixtures.cdEnvironments;
export const productionTierEnvironmentsResponse = fixtures.cdEnvironmentsProductionTier;
export const nextPageEnvironmentsResponse = fixtures.cdEnvironmentsNextPage;
export const searchedEnvironmentsResponse = fixtures.cdEnvironmentsSearch;
export const environmentTiersResponse = fixtures.cdEnvironmentTiers;
export const availableAgentsResponse = fixtures.cdAvailableAgents;
export const environmentCreateResponse = fixtures.cdEnvironmentCreate;

export const PRODUCTION_TIER = 'PRODUCTION';

const FIRST_PAGE_CURSOR = environmentsResponse.data.organization.cdEnvironments.pageInfo.endCursor;

export const SEARCH_TERM = 'prod';
export const UNMATCHED_SEARCH_TERM = 'no-such-environment';

const environmentsFixtureTable = [
  {
    matches: ({ search, tier, after }) => !search && !tier && !after,
    fixture: () => environmentsResponse,
  },
  {
    matches: ({ search, tier, after }) => !search && !tier && after === FIRST_PAGE_CURSOR,
    fixture: () => nextPageEnvironmentsResponse,
  },
  {
    matches: ({ search, tier, after }) => !search && tier === PRODUCTION_TIER && !after,
    fixture: () => productionTierEnvironmentsResponse,
  },
  {
    matches: ({ search, tier, after }) => search === SEARCH_TERM && !tier && !after,
    fixture: () => searchedEnvironmentsResponse,
  },
  {
    matches: ({ search, tier, after }) => search === UNMATCHED_SEARCH_TERM && !tier && !after,
    fixture: () => cdEnvironmentsVariants.EMPTY,
  },
];

function buildEnvironmentCreateResponse({ input }) {
  const response = cloneDeep(environmentCreateResponse);
  const { environment } = response.data.cdEnvironmentCreate;

  environment.name = input.name;
  environment.tier = input.tier;
  environment.environmentDriverBindings.nodes[0].driverConfig =
    input.environmentDriverBinding.driverConfig;

  return response;
}

const OPERATION_HANDLERS = {
  cdEnvironments: ({ variables }) =>
    getActiveVariant('cdEnvironments') ??
    matchFixture(variables, environmentsFixtureTable, {
      guard: () => true,
      label: 'cdEnvironments',
    }).fixture(),
  cdEnvironmentTiers: () => environmentTiersResponse,
  cdAvailableAgents: () => availableAgentsResponse,
  cdEnvironmentCreate: ({ variables }) => buildEnvironmentCreateResponse(variables),
};

export function handleCdEnvironmentOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const cdEnvironmentRestEndpoints = [];
