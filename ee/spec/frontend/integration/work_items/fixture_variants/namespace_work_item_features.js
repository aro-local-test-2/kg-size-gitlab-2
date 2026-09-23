import namespaceWorkItemFeaturesBase from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features.query.graphql.json';
import namespaceWorkItemFeaturesStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features_status_unlicensed.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// The `features` shape of the namespaceWorkItem query, which the handler serves whenever
// the request asks for it. Registered under its own key so a spec can vary the two shapes
// independently and, when it runs under both flag states, activate them together.
export default defineFixtureVariants({
  query: 'namespaceWorkItemFeatures',
  variants: {
    BASE: namespaceWorkItemFeaturesBase,
    // Captured from a namespace without the status licence, so `features.status` is null
    // the same way a real unlicensed instance's would be.
    STATUS_UNLICENSED: namespaceWorkItemFeaturesStatusUnlicensed,
  },
});
