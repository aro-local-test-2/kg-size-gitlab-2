import base from 'test_fixtures/graphql/commits/integration/get_commit_list_branch_names.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getCommitListBranchNames',
  variants: {
    BASE: base,
    // The ref does not resolve to a branch (for example, a commit SHA).
    NOT_A_BRANCH: setFixtureData(base, 'branchNames', []),
  },
});
