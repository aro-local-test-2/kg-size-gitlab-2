import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { snapshotRequests, expectGraphQLCalls } from 'ee_jest/integration/core/operation_helpers';
import {
  getBranchMergeRequest,
  getCommitListBranchNames,
} from 'ee_jest/integration/commits/fixture_variants';
import { branchMergeRequestResponse } from 'ee_jest/integration/commits/handlers';
import {
  apolloProvider,
  mountCommitListApp,
  findViewMergeRequestButton,
  findCreateMergeRequestButton,
  findRefSelector,
  waitForCommitList,
  PROJECT_FULL_PATH,
  DEFAULT_BRANCH,
} from './test_setup';

const openMergeRequestPath = branchMergeRequestResponse.data.project.mergeRequests.nodes[0].webPath;

const expectNoMergeRequestButton = () => {
  expect(findViewMergeRequestButton()).toBe(null);
  expect(findCreateMergeRequestButton()).toBe(null);
};

describe('Commit list merge request button', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('on a branch with an open merge request', () => {
    it('shows "View open merge request" linking to the existing merge request', async () => {
      mountCommitListApp();

      const button = await waitForElement(findViewMergeRequestButton);

      expect(getText(button)).toBe('View open merge request');
      expect(button.getAttribute('href')).toBe(openMergeRequestPath);
      expect(findCreateMergeRequestButton()).toBe(null);
    });

    it('offers the same action in the actions dropdown for small viewports', async () => {
      mountCommitListApp();
      await waitForElement(findViewMergeRequestButton);

      await waitAndClick(() => findButtonByText('Actions'));

      const dropdownItem = await waitForElement(() =>
        document.querySelector('[data-testid="view-merge-request-link"]'),
      );
      expect(getText(dropdownItem)).toBe('View open merge request');
    });
  });

  describe('on a branch without an open merge request', () => {
    it('shows "Create merge request" linking to the new merge request form', async () => {
      setQueryVariant(getBranchMergeRequest).noOpenMergeRequest();
      mountCommitListApp();

      const button = await waitForElement(findCreateMergeRequestButton);

      expect(getText(button)).toBe('Create merge request');
      expect(decodeURIComponent(button.getAttribute('href'))).toBe(
        `/${PROJECT_FULL_PATH}/-/merge_requests/new?merge_request[source_branch]=feature`,
      );
      expect(findViewMergeRequestButton()).toBe(null);
    });
  });

  describe('when the user cannot create merge requests', () => {
    it('renders no merge request button', async () => {
      setQueryVariant(getBranchMergeRequest).noPermissions();
      const baseline = snapshotRequests();
      mountCommitListApp();

      await waitForCommitList();
      await waitForAssertion(() => {
        expectGraphQLCalls(baseline, { expect: ['getBranchMergeRequest'], forbid: [] });
      });

      expectNoMergeRequestButton();
    });
  });

  describe('on the default branch', () => {
    it('renders no button and never queries for a merge request', async () => {
      const baseline = snapshotRequests();
      mountCommitListApp({ ref: DEFAULT_BRANCH });

      await waitForCommitList();

      expectGraphQLCalls(baseline, {
        expect: ['getCommitList'],
        forbid: ['getBranchMergeRequest', 'getCommitListBranchNames'],
      });
      expectNoMergeRequestButton();
    });
  });

  describe('on a tag', () => {
    it('renders no button and never queries for a merge request', async () => {
      const baseline = snapshotRequests();
      mountCommitListApp({ ref: 'v1.0.0', refType: 'tags' });

      await waitForCommitList();

      expectGraphQLCalls(baseline, {
        expect: ['getCommitList'],
        forbid: ['getBranchMergeRequest', 'getCommitListBranchNames'],
      });
      expectNoMergeRequestButton();
    });
  });

  describe('when the ref type is unknown (direct URL visit)', () => {
    it('verifies the ref is a branch before offering to create a merge request', async () => {
      setQueryVariant(getBranchMergeRequest).noOpenMergeRequest();
      const baseline = snapshotRequests();
      mountCommitListApp({ refType: '' });

      await waitForElement(findCreateMergeRequestButton);

      expectGraphQLCalls(baseline, { expect: ['getCommitListBranchNames'], forbid: [] });
    });

    it('renders no create button when the ref is not a branch', async () => {
      setQueryVariant(getBranchMergeRequest).noOpenMergeRequest();
      setQueryVariant(getCommitListBranchNames).notABranch();
      const baseline = snapshotRequests();
      mountCommitListApp({ refType: '' });

      await waitForCommitList();
      await waitForAssertion(() => {
        expectGraphQLCalls(baseline, { expect: ['getCommitListBranchNames'], forbid: [] });
      });

      expectNoMergeRequestButton();
    });
  });

  describe('when switching refs without a page reload', () => {
    it('hides the button after switching to the default branch', async () => {
      mountCommitListApp();
      await waitForElement(findViewMergeRequestButton);

      await waitAndClick(() => findRefSelector().querySelector('button'));
      const masterOption = await waitForElement(
        () =>
          [...findRefSelector().querySelectorAll('[role="option"]')].find((option) =>
            getText(option).includes(DEFAULT_BRANCH),
          ) ?? null,
      );
      masterOption.click();

      await waitForElementToBeNull(findViewMergeRequestButton);
      expect(findCreateMergeRequestButton()).toBe(null);
    });
  });
});
