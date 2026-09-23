import base from 'test_fixtures/graphql/commits/integration/get_branch_merge_request.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData, setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

const noOpenMergeRequest = setFixtureItemsCount({
  fixture: base,
  lookupKey: 'mergeRequests',
  itemCount: 0,
});

const noPermissions = setFixtureData(noOpenMergeRequest, 'userPermissions', {
  ...base.data.project.userPermissions,
  createMergeRequestFrom: false,
  createMergeRequestIn: false,
});

export default defineFixtureVariants({
  query: 'getBranchMergeRequest',
  variants: {
    BASE: base,
    NO_OPEN_MERGE_REQUEST: noOpenMergeRequest,
    NO_PERMISSIONS: noPermissions,
  },
});
