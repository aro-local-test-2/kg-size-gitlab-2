import base from 'test_fixtures/graphql/commits/integration/get_commit_list.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import {
  setFixtureData,
  setFixtureErrors,
  setFixtureItemsCount,
} from 'ee_jest/integration/core/fixture_utils';

export const COMMIT_LIST_ERROR = 'Commit list is unavailable';

export default defineFixtureVariants({
  query: 'getCommitList',
  variants: {
    BASE: base,
    // A search that matches no commits (served by the handler's fixture table).
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'commits', itemCount: 0 }),
    // Commits whose author email has no GitLab account (sets every node's author).
    NO_AUTHOR: setFixtureData(base, 'author', null),
    ERROR: setFixtureErrors(base, [COMMIT_LIST_ERROR]),
  },
});
