import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_ai_messages_with_thread.query.graphql.json';
import empty from 'test_fixtures/graphql/ai_duo_panel/integration/get_ai_messages_with_thread_empty.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getAiMessagesWithThread',
  variants: {
    BASE: base,
    // A separate capture of a thread that exists but holds no exchange yet, rather
    // than a transform: the fixture spec records it from its own empty thread.
    EMPTY: empty,
  },
});
