import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  expectTokensToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

describe('Work items list - search within filter', () => {
  useFilterSpec();

  it('searches titles only', async () => {
    useListFixture('MATCHING_TITLE');
    mountListWithQuery('?search=Dependent&in=TITLE');

    await expectListToShow([WORK_ITEMS.DEPENDENT]);
    await expectTokensToShow(['Search within is Titles']);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      search: 'Dependent',
      in: 'TITLE',
    });
  });

  it('searches descriptions only', async () => {
    useListFixture('MATCHING_DESCRIPTION');
    mountListWithQuery('?search=searchable&in=DESCRIPTION');

    await expectListToShow([WORK_ITEMS.BLOCKING]);

    expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({
      search: 'searchable',
      in: 'DESCRIPTION',
    });
  });
});
