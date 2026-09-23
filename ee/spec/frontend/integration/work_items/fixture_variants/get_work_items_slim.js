import getWorkItemsSlimBase from 'test_fixtures/graphql/work_items/integration/get_work_items_slim.query.graphql.json';
import getWorkItemsSlimClosed from 'test_fixtures/graphql/work_items/integration/get_work_items_slim_closed.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';
import { listFilterVariants } from './list_filter_variants';

export default defineFixtureVariants({
  query: 'getWorkItemsSlimEE',
  variants: {
    BASE: getWorkItemsSlimBase,
    EMPTY: setFixtureItemsCount({
      fixture: getWorkItemsSlimBase,
      lookupKey: 'workItems',
      itemCount: 0,
    }),
    CLOSED: getWorkItemsSlimClosed,
    ...listFilterVariants('slim'),
  },
});
