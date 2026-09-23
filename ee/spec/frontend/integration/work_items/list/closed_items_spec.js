import Vue from 'vue';
import VueApollo from 'vue-apollo';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getWorkItemsFull,
  getWorkItemsSlim,
} from 'ee_jest/integration/work_items/fixture_variants';

Vue.use(VueApollo);

describe('Work items list - closed items view', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    setQueryVariant(getWorkItemsFull).closed();
    setQueryVariant(getWorkItemsSlim).closed();
    await apolloProvider.defaultClient.cache.reset();
  });

  it('shows closed items and does not show open items', async () => {
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
        isSignedIn: true,
        initialSort: 'created_desc',
        isServiceDeskSupported: false,
      },
    });

    await waitForAssertion(() => {
      const listText = getText(document.querySelector('.issuable-list'));
      expect(listText).toContain('Closed test issue');
      expect(listText).not.toContain('Dependent test issue');
      expect(listText).not.toContain('Second test issue');
    });
  });
});
