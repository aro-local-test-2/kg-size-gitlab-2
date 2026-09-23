// Shared helper module (not a test file) for the work item list filter specs.
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  assignRouter,
  fullMount,
  getText,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { activateVariant } from 'ee_jest/integration/helpers/setup_utils';
import { PROJECT_PATH, GROUP_PATH } from './filter_test_constants';

Vue.use(VueApollo);

/**
 * The setup every filter spec needs, registering its own hooks. Named `use*` to match
 * `useFakeDate` and the other helpers called bare inside a `describe`. Do not wrap this
 * in a `beforeAll`: the inner `beforeAll` would then be registered too late to run, and
 * the portal element would silently never be created. `jest.mock` stays per file
 * because it is hoisted.
 */
export function useFilterSpec() {
  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });
}

/**
 * Selects the generated fixture this test should be served. The list fires both the slim
 * and the full query, so both are set together.
 *
 * @param {string} variant key from the fixture variants, e.g. 'WITH_LABEL'
 */
export function useListFixture(variant) {
  activateVariant('getWorkItemsSlimEE', variant);
  activateVariant('getWorkItemsFullEE', variant);
}

const findList = () => document.querySelector('.issuable-list');

/**
 * Mounts the list on a filtered URL, the way a user arrives from a bookmarked
 * or shared link. The list reads its filter state from window.location.search.
 *
 * `routerPath` becomes Vue Router's history base, so the location that resolves
 * to the list route is base + path — hence the repeated segment.
 *
 * @param {string} search query string, including the leading `?`
 * @param {Object} [options]
 * @param {boolean} [options.isGroup] mount the group list instead of the project one
 */
export function mountListWithQuery(search, { isGroup = false } = {}) {
  const fullPath = isGroup ? GROUP_PATH : PROJECT_PATH;

  const router = assignRouter(createRouter, {
    fullPath,
    routerPath: 'work_items',
    routerLocation: `/work_items/work_items${search}`,
  });

  fullMount(WorkItemsRoot, {
    router,
    propsData: {
      rootPageFullPath: fullPath,
    },
    apolloProvider,
    provide: {
      isGroup,
      isGroupIssuesList: isGroup,
      fullPath,
      groupPath: GROUP_PATH,
      workItemType: 'Issue',
      isSignedIn: true,
      initialSort: 'created_desc',
      isServiceDeskSupported: false,
    },
  });
}

/**
 * Asserts the exact set of rows on screen.
 *
 * Matches on row title links rather than the list's text content: a row also
 * renders its parent's title as metadata, so a filtered-out title can still
 * appear in the list text.
 *
 * @param {string[]} expectedTitles
 */
export function expectListToShow(expectedTitles) {
  return waitForAssertion(() => {
    const titles = [...findList().querySelectorAll('[data-testid="issuable-title-link"]')].map(
      (el) => getText(el),
    );

    expect(titles.sort()).toEqual([...expectedTitles].sort());
  });
}

/**
 * Clears every applied filter the way the "Clear" button in the search bar does.
 */
export function clearFilters() {
  document.querySelector('[data-testid="filtered-search-clear-button"]').click();
}

/**
 * Asserts the filter tokens rendered in the search bar.
 *
 * Covers the URL to token direction: these specs arrive on an already-filtered
 * URL, so the token has to reconstruct its own label, operator and value from
 * the query string. The deleted feature specs got this for free by picking the
 * token in the UI.
 *
 * @param {string[]} expectedTokens e.g. ['My reaction is thumbsup']
 */
export function expectTokensToShow(expectedTokens) {
  return waitForAssertion(() => {
    const tokens = [...document.querySelectorAll('[data-testid="filtered-search-token"]')].map(
      (el) => getText(el).replace(/\s+/g, ' ').trim(),
    );

    expect(tokens.sort()).toEqual([...expectedTokens].sort());
  });
}
