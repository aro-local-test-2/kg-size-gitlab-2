import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  expectTokensToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { REACTION } = FILTER_VALUES;
const REACTED_ITEM = WORK_ITEMS.SECOND;
const UNREACTED_ITEMS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - my reaction filter', () => {
  useFilterSpec();

  it('filters to work items the current user reacted to', async () => {
    useListFixture('WITH_MY_REACTION');
    mountListWithQuery(`?my_reaction_emoji=${REACTION}`);

    await expectListToShow([REACTED_ITEM]);
    await expectTokensToShow(['My reaction is thumbsup']);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      myReactionEmoji: 'thumbsup',
    });
  });

  it('filters out work items the current user reacted to', async () => {
    useListFixture('WITHOUT_MY_REACTION');
    mountListWithQuery(`?not[my_reaction_emoji]=${REACTION}`);

    await expectListToShow(UNREACTED_ITEMS);
    await expectTokensToShow(['My reaction is not thumbsup']);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      not: { myReactionEmoji: 'thumbsup' },
    });
  });

  it('filters to work items with no reaction from the current user', async () => {
    useListFixture('WITH_NO_REACTION');
    mountListWithQuery('?my_reaction_emoji=None');

    await expectListToShow(UNREACTED_ITEMS);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ myReactionEmoji: 'None' });
  });

  it('filters to work items with any reaction from the current user', async () => {
    useListFixture('WITH_ANY_REACTION');
    mountListWithQuery('?my_reaction_emoji=Any');

    await expectListToShow([REACTED_ITEM]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ myReactionEmoji: 'Any' });
  });
});
