import Vue from 'vue';
import VueApollo from 'vue-apollo';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getWorkItemsFull,
  getWorkItemsSlim,
  getWorkItemsCountOnly,
  hasWorkItems,
} from 'ee_jest/integration/work_items/fixture_variants';

Vue.use(VueApollo);

describe('Work items list - empty state', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  beforeEach(() => {
    setQueryVariant(getWorkItemsFull).empty();
    setQueryVariant(getWorkItemsSlim).empty();
    setQueryVariant(getWorkItemsCountOnly).empty();
    setQueryVariant(hasWorkItems).empty();
  });

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  it('shows empty state message when there are no work items', async () => {
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
      expect(getText(document.body)).toContain('Track bugs, plan features');
    });
  });
});
