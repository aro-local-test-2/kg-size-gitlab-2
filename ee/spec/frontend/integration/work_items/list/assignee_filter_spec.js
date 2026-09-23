import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { ASSIGNABLE_USER: ASSIGNEE, SECOND_ASSIGNABLE_USER: SECOND_ASSIGNEE } = FILTER_VALUES;

describe('Work items list - assignee filter', () => {
  useFilterSpec();

  it('filters to work items assigned to the user', async () => {
    useListFixture('WITH_ASSIGNEE');
    mountListWithQuery(`?assignee_username[]=${ASSIGNEE}`);

    await expectListToShow([WORK_ITEMS.SECOND]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      assigneeUsernames: 'assignable_user',
    });
  });

  it('filters out work items assigned to the user', async () => {
    useListFixture('WITHOUT_SPECIFIC_ASSIGNEE');
    mountListWithQuery(`?not[assignee_username][]=${ASSIGNEE}`);

    await expectListToShow([
      WORK_ITEMS.DEPENDENT,
      WORK_ITEMS.CHILD_TASK,
      WORK_ITEMS.BLOCKING,
      WORK_ITEMS.LINKABLE,
      WORK_ITEMS.AGENT_PLAN,
    ]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      not: { assigneeUsernames: ['assignable_user'] },
    });
  });

  it('filters to unassigned work items', async () => {
    useListFixture('WITH_NO_ASSIGNEE');
    mountListWithQuery('?assignee_id=None');

    await expectListToShow([WORK_ITEMS.BLOCKING, WORK_ITEMS.LINKABLE, WORK_ITEMS.AGENT_PLAN]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      assigneeWildcardId: 'NONE',
    });
  });

  it('filters to work items with any assignee', async () => {
    useListFixture('WITH_ANY_ASSIGNEE');
    mountListWithQuery('?assignee_id=Any');

    await expectListToShow([WORK_ITEMS.DEPENDENT, WORK_ITEMS.SECOND, WORK_ITEMS.CHILD_TASK]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      assigneeWildcardId: 'ANY',
    });
  });

  it('filters to work items assigned to one of several users', async () => {
    useListFixture('WITH_ANY_OF_ASSIGNEES');
    mountListWithQuery(
      `?or[assignee_username][]=${ASSIGNEE}&or[assignee_username][]=${SECOND_ASSIGNEE}`,
    );

    await expectListToShow([WORK_ITEMS.SECOND, WORK_ITEMS.CHILD_TASK]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      or: { assigneeUsernames: ['assignable_user', 'second_assignable_user'] },
    });
  });
});
