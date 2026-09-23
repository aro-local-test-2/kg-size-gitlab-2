import getWorkItemsCountOnlyBase from 'test_fixtures/graphql/work_items/integration/get_work_items_count_only.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getWorkItemsCountOnlyEE',
  variants: {
    BASE: getWorkItemsCountOnlyBase,
    EMPTY: setFixtureItemsCount({
      fixture: getWorkItemsCountOnlyBase,
      lookupKey: 'workItems',
      itemCount: 0,
    }),
  },
});
