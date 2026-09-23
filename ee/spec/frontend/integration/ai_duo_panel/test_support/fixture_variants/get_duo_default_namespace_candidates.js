import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_duo_default_namespace_candidates.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getDuoDefaultNamespaceCandidates',
  variants: {
    BASE: base,
    // A Duo user who belongs to no top-level group: the selector has nothing to
    // offer and the panel shows its no-groups message instead.
    EMPTY: setFixtureItemsCount({
      fixture: base,
      lookupKey: 'duoDefaultNamespaceCandidates',
      itemCount: 0,
    }),
  },
});
