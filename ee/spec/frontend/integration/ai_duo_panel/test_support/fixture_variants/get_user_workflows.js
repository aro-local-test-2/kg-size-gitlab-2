import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_workflows.query.graphql.json';
import twoThreads from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_workflows_two_threads.query.graphql.json';
import withArchived from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_workflows_with_archived.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getUserWorkflows',
  variants: {
    BASE: base,
    // `archived` is derived from the workflow's age rather than stored, so this is a
    // second capture taken after the fixture spec aged one workflow past retention.
    WITH_ARCHIVED: withArchived,
    TWO_THREADS: twoThreads,
  },
});
