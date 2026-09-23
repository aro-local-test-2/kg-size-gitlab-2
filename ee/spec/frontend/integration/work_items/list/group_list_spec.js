import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

const ALL_ITEMS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - group namespace', () => {
  useFilterSpec();

  it('lists work items from across the group', async () => {
    useListFixture('GROUP');
    mountListWithQuery('', { isGroup: true });

    await expectListToShow(ALL_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org',
      includeDescendants: true,
    });
  });

  it('lists only the project work items when mounted on a project', async () => {
    mountListWithQuery('');

    await expectListToShow(ALL_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      fullPath: 'gitlab-org/gitlab',
    });
  });
});
