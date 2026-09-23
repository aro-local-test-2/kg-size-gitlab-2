import agentBase from 'test_fixtures/graphql/ai_catalog/integration/ai_catalog_agent.query.graphql.json';
import agentPinnedToLatest from 'test_fixtures/graphql/ai_catalog/integration/ai_catalog_agent_pinned_to_latest.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'aiCatalogAgent',
  variants: {
    BASE: agentBase,
    PINNED_TO_LATEST: agentPinnedToLatest,
  },
});
