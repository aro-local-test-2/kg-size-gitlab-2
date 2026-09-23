import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_ai_chat_available_models.query.graphql.json';
import unpinned from 'test_fixtures/graphql/ai_duo_panel/integration/get_ai_chat_available_models_unpinned.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getAiChatAvailableModels',
  variants: {
    // BASE is the *pinned* dropdown: that is what Rails records by default, and
    // `isModelSelectionDisabled` is `Boolean(pinnedModel)`, so BASE is the shape
    // that disables selection. The permissive case is the named variant.
    BASE: base,
    UNPINNED: unpinned,
  },
});
