import flowBase from 'test_fixtures/graphql/ai_catalog/integration/ai_catalog_flow.query.graphql.json';
import flowPinnedToLatest from 'test_fixtures/graphql/ai_catalog/integration/ai_catalog_flow_pinned_to_latest.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'aiCatalogFlow',
  variants: {
    BASE: flowBase,
    PINNED_TO_LATEST: flowPinnedToLatest,
  },
});
