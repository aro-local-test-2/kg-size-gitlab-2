import Vue from 'vue';
import VueApollo from 'vue-apollo';
import CommitListApp from '~/projects/commits/components/commit_list_app.vue';
import apolloProvider from '~/projects/commits/graphql';
import { createRouter } from '~/projects/commits/router';
import {
  assignRouter,
  fullMount,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';

Vue.use(VueApollo);

export const PROJECT_FULL_PATH = 'gitlab-org/gitlab';
export const DEFAULT_BRANCH = 'master';

const BASE_PATH = `/${PROJECT_FULL_PATH}/-/commits`;

export { apolloProvider };

// Mirrors app/assets/javascripts/projects/commits/init_commit_list_app.js
export function mountCommitListApp({ ref = 'feature', refType = 'heads', path = '' } = {}) {
  // Mirror Rails' escape_path (commits_helper.rb): each segment is escaped but
  // slashes stay literal, so slash refs get the same URL and routes as production.
  const escapedRef = ref.split('/').map(encodeURIComponent).join('/');
  const router = assignRouter(() => createRouter(BASE_PATH, escapedRef), {
    routerLocation: path ? `${BASE_PATH}/${escapedRef}/${path}` : `${BASE_PATH}/${escapedRef}`,
  });

  return fullMount(CommitListApp, {
    router,
    apolloProvider,
    provide: {
      projectFullPath: PROJECT_FULL_PATH,
      projectRootPath: PROJECT_FULL_PATH,
      projectPath: 'gitlab',
      projectId: '1',
      escapedRef,
      refType,
      rootRef: DEFAULT_BRANCH,
      browseFilesPath: `/${PROJECT_FULL_PATH}/-/tree/${escapedRef}`,
      commitsFeedPath: `/${PROJECT_FULL_PATH}/-/commits/${escapedRef}?format=atom`,
    },
  });
}

export const findViewMergeRequestButton = () =>
  document.querySelector('[data-testid="view-merge-request-button"]');

export const findCreateMergeRequestButton = () =>
  document.querySelector('[data-testid="create-merge-request-button"]');

export const findDailyCommits = () => [
  ...document.querySelectorAll('[data-testid="daily-commits"]'),
];

export const findRefSelector = () => screen.queryByTestId('commits-ref-selector');

export const findCommitItem = (shortId) => document.getElementById(`commit-${shortId}`);

export const findPagination = () => screen.queryByTestId('commits-pagination');

// The idle search input; focusing it swaps in the active token segment input.
export const findFilteredSearchInput = () => screen.queryByTestId('filtered-search-term-input');

export const findActiveFilteredSearchInput = () =>
  screen.queryByTestId('filtered-search-token-segment-input');

export const waitForCommitList = () =>
  waitForAssertion(() => {
    expect(findDailyCommits().length).toBeGreaterThan(0);
  });
