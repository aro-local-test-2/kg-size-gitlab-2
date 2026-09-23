import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  expectTokensToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { LABEL, OTHER_LABEL } = FILTER_VALUES;
const ITEM_WITH_LABEL = WORK_ITEMS.SECOND;
const ITEM_WITH_OTHER_LABEL = WORK_ITEMS.CHILD_TASK;
const ITEMS_WITHOUT_LABELS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - label filter', () => {
  useFilterSpec();

  it('filters to work items carrying the label', async () => {
    useListFixture('WITH_LABEL');
    mountListWithQuery(`?label_name[]=${encodeURIComponent(LABEL)}`);

    await expectListToShow([ITEM_WITH_LABEL]);
    await expectTokensToShow(['Label is To Do']);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ labelName: 'To Do' });
  });

  it('filters out work items carrying the label', async () => {
    useListFixture('WITHOUT_SPECIFIC_LABEL');
    mountListWithQuery(`?not[label_name][]=${encodeURIComponent(LABEL)}`);

    await expectListToShow([ITEM_WITH_OTHER_LABEL, ...ITEMS_WITHOUT_LABELS]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      not: { labelName: ['To Do'] },
    });
  });

  it('filters to work items with no labels', async () => {
    useListFixture('WITH_NO_LABEL');
    mountListWithQuery('?label_name[]=None');

    await expectListToShow(ITEMS_WITHOUT_LABELS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ labelName: 'None' });
  });

  it('filters to work items carrying any label', async () => {
    useListFixture('WITH_ANY_LABEL');
    mountListWithQuery('?label_name[]=Any');

    await expectListToShow([ITEM_WITH_LABEL, ITEM_WITH_OTHER_LABEL]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ labelName: 'Any' });
  });

  it('filters to work items carrying one of several labels', async () => {
    useListFixture('WITH_ANY_OF_LABELS');
    mountListWithQuery(
      `?or[label_name][]=${encodeURIComponent(LABEL)}` +
        `&or[label_name][]=${encodeURIComponent(OTHER_LABEL)}`,
    );

    await expectListToShow([ITEM_WITH_LABEL, ITEM_WITH_OTHER_LABEL]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      or: { labelNames: [LABEL, OTHER_LABEL] },
    });
  });
});
