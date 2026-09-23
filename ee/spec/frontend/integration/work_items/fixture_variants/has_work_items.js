import hasWorkItemsBase from 'test_fixtures/graphql/work_items/integration/has_work_items.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'hasWorkItems',
  variants: {
    BASE: hasWorkItemsBase,
    EMPTY: setFixtureItemsCount({
      fixture: hasWorkItemsBase,
      lookupKey: 'workItems',
      itemCount: 0,
    }),
  },
});
