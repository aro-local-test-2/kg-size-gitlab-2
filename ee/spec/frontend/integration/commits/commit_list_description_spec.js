import { snapshotRequests, expectGraphQLCalls } from 'ee_jest/integration/core/operation_helpers';
import { commitListResponse } from 'ee_jest/integration/commits/handlers';
import { within } from 'ee_jest/integration/helpers/test_helpers';
import {
  apolloProvider,
  mountCommitListApp,
  findCommitItem,
  waitForCommitList,
} from './test_setup';

const headCommit = commitListResponse.data.project.repository.commits.nodes[0];
// From the recorded getCommitDetails fixture (the commit's trailer line).
const DESCRIPTION_TEXT = 'Signed-off-by';

const findItem = () => findCommitItem(headCommit.shortId);
const findRow = () => within(findItem()).queryByTestId('commit-row');

const toggleRow = async (expanded) => {
  findRow().click();
  await waitForAssertion(() => {
    expect(findRow().getAttribute('aria-expanded')).toBe(String(expanded));
  });
};

describe('Commit list item description', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
    mountCommitListApp();
    await waitForCommitList();
  });

  it('renders the row collapsed without the description', () => {
    expect(getText(findItem())).not.toContain(DESCRIPTION_TEXT);
    expect(findRow().getAttribute('aria-expanded')).toBe('false');
  });

  describe('when expanding the description', () => {
    let baseline;

    beforeEach(async () => {
      baseline = snapshotRequests();
      await toggleRow(true);
    });

    it('fetches and shows the description', async () => {
      await waitForAssertion(() => {
        expect(getText(findItem())).toContain(DESCRIPTION_TEXT);
        expectGraphQLCalls(baseline, { expect: ['getCommitDetails'], forbid: [] });
      });
    });

    describe('when collapsing and re-expanding the description', () => {
      let reExpandBaseline;

      beforeEach(async () => {
        await waitForAssertion(() => {
          expect(getText(findItem())).toContain(DESCRIPTION_TEXT);
        });

        await toggleRow(false);
        reExpandBaseline = snapshotRequests();
        await toggleRow(true);
      });

      it('shows the description from the Apollo cache without refetching', () => {
        expect(getText(findItem())).toContain(DESCRIPTION_TEXT);
        expectGraphQLCalls(reExpandBaseline, { expect: [], forbid: ['getCommitDetails'] });
      });
    });
  });
});
