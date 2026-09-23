import inboxBase from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_agent_flow_inbox.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

// The inbox has two empty states with different triggers, so it needs two empty
// variants rather than one: the decision tab shows its own copy whenever
// `needsDecision` is empty, while the shared empty state waits until neither alias
// has returned a row.
//
// Hand-built rather than via `setFixtureItemsCount`, which resizes a `nodes` array.
// These connections expose `edges`.
const emptied = (connection) => ({
  ...connection,
  edges: [],
  pageInfo: { ...connection.pageInfo, hasNextPage: false, endCursor: null },
});

const withEmptyDecision = setFixtureData(
  inboxBase,
  'needsDecision',
  emptied(inboxBase.data.needsDecision),
);

export default defineFixtureVariants({
  query: 'getUserAgentFlowInbox',
  variants: {
    BASE: inboxBase,
    DECISION_EMPTY: withEmptyDecision,
    BOTH_EMPTY: setFixtureData(withEmptyDecision, 'all', emptied(inboxBase.data.all)),
  },
});
