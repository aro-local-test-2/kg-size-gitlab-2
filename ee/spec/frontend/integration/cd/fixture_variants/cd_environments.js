import base from 'test_fixtures/graphql/cd/integration/cd_environments.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData, setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

// `pageInfo` has to be reset alongside the nodes, otherwise the list offers a next
// page it cannot serve.
const emptyEnvironmentsResponse = setFixtureData(
  setFixtureItemsCount({ fixture: base, lookupKey: 'cdEnvironments', itemCount: 0 }),
  'pageInfo',
  {
    ...base.data.organization.cdEnvironments.pageInfo,
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: null,
    endCursor: null,
  },
);

export default defineFixtureVariants({
  query: 'cdEnvironments',
  variants: {
    BASE: base,
    EMPTY: emptyEnvironmentsResponse,
  },
});
