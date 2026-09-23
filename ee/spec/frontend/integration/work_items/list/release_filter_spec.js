import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { RELEASE } = FILTER_VALUES;

describe('Work items list - release filter', () => {
  useFilterSpec();

  it('filters to work items in the release', async () => {
    useListFixture('WITH_RELEASE');
    mountListWithQuery(`?release_tag=${RELEASE}`);

    await expectListToShow([WORK_ITEMS.DEPENDENT]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ releaseTag: 'v1.0.0' });
  });

  it('filters out work items in the release', async () => {
    useListFixture('WITHOUT_SPECIFIC_RELEASE');
    mountListWithQuery(`?not[release_tag]=${RELEASE}`);

    await expectListToShow([WORK_ITEMS.CHILD_TASK]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      not: { releaseTag: 'v1.0.0' },
    });
  });

  it('filters to work items with no release', async () => {
    useListFixture('WITH_NO_RELEASE');
    mountListWithQuery('?release_tag=None');

    await expectListToShow([
      WORK_ITEMS.SECOND,
      WORK_ITEMS.BLOCKING,
      WORK_ITEMS.LINKABLE,
      WORK_ITEMS.AGENT_PLAN,
    ]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      releaseTagWildcardId: 'NONE',
    });
  });

  it('filters to work items with any release', async () => {
    useListFixture('WITH_ANY_RELEASE');
    mountListWithQuery('?release_tag=Any');

    await expectListToShow([WORK_ITEMS.DEPENDENT, WORK_ITEMS.CHILD_TASK]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      releaseTagWildcardId: 'ANY',
    });
  });
});
