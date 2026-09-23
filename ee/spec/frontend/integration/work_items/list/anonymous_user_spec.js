import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { findIssueToEdit } from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant, setUserSession } from 'ee_jest/integration/helpers/setup_utils';
import { workItemMetadata } from 'ee_jest/integration/work_items/fixture_variants';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';

Vue.use(VueApollo);

describe('Work items list - anonymous user', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    setUserSession(false);
    await apolloProvider.defaultClient.cache.reset();

    setQueryVariant(workItemMetadata).anonymous();
    fullMount(WorkItemsRoot, {
      router,
      propsData: {
        rootPageFullPath: 'gitlab-org/gitlab',
      },
      apolloProvider,
      provide: {
        isGroup: false,
        isGroupIssuesList: false,
        fullPath: 'gitlab-org/gitlab',
        groupPath: 'gitlab-org',
        workItemType: 'Issue',
        isSignedIn: false,
        initialSort: 'created_desc',
        isServiceDeskSupported: false,
      },
    });

    await waitForElement(findIssueToEdit);
  });

  it('renders the list, keeps the New item link for sign-in, and hides bulk edit', () => {
    expect(findIssueToEdit()).not.toBe(null);

    // showNewWorkItem stays true for anonymous users so the link routes them to
    // sign-in; only the admin-gated bulk edit action (adminIssue: false) is hidden.
    const links = [...document.querySelectorAll('a')];
    expect(links.some((a) => a.textContent.includes('New item'))).toBe(true);
    expect(within(document.body).queryByTestId('bulk-edit-start-button')).toBe(null);
  });
});
