import { snapshotRequests, expectGraphQLCalls } from 'ee_jest/integration/core/operation_helpers';
import { screen, within } from 'ee_jest/integration/helpers/test_helpers';
import {
  commitListResponse,
  nextPageCommitListResponse,
} from 'ee_jest/integration/commits/handlers';
import {
  apolloProvider,
  mountCommitListApp,
  findPagination,
  waitForCommitList,
} from './test_setup';

const pageOneHead = commitListResponse.data.project.repository.commits.nodes[0];
const pageTwoHead = nextPageCommitListResponse.data.project.repository.commits.nodes[0];

const findPrevButton = () => within(findPagination()).queryByTestId('prevButton');
const findNextButton = () => within(findPagination()).queryByTestId('nextButton');
// GlButton renders disabled pagination buttons with aria-disabled, not the disabled attribute.
const isDisabled = (button) => button.getAttribute('aria-disabled') === 'true';
// GlCollapsibleListbox toggles use the ARIA select-only combobox pattern, not the button role.
const findPageSizeToggle = (text) =>
  within(document.body).queryAllByRole('combobox', { name: text })[0] ?? null;

describe('Commit list keyset pagination', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
    mountCommitListApp();
    await waitForCommitList();
  });

  it('shows the first page with the Previous button disabled', () => {
    expect(getText(document.body)).toContain(pageOneHead.shortId);
    expect(isDisabled(findPrevButton())).toBe(true);
  });

  describe('when paginating to the next page', () => {
    beforeEach(async () => {
      await waitAndClick(findNextButton);

      await waitForAssertion(() => {
        expect(getText(document.body)).toContain(pageTwoHead.shortId);
      });
    });

    it('shows the second page and enables the Previous button', () => {
      expect(getText(document.body)).not.toContain(pageOneHead.shortId);
      expect(isDisabled(findPrevButton())).toBe(false);
    });

    describe('when paginating back to the first page', () => {
      let baseline;

      beforeEach(async () => {
        baseline = snapshotRequests();
        await waitAndClick(findPrevButton);

        await waitForAssertion(() => {
          expect(getText(document.body)).toContain(pageOneHead.shortId);
        });
      });

      it('serves the first page from the Apollo cache', () => {
        expect(isDisabled(findPrevButton())).toBe(true);
        expectGraphQLCalls(baseline, { expect: [], forbid: ['getCommitList'] });
      });
    });
  });

  describe('when all commits fit the selected page size', () => {
    beforeEach(async () => {
      await waitAndClick(() => findPageSizeToggle('Show 20 items'));
      await waitAndClick(() => screen.queryByRole('option', { name: 'Show 50 items' }));

      await waitForAssertion(() => {
        expect(getText(document.body)).toContain('Initial commit');
      });
    });

    it('hides the pagination controls', () => {
      expect(findPagination()).toBe(null);
      expect(findPageSizeToggle('Show 50 items')).not.toBe(null);
    });
  });
});
