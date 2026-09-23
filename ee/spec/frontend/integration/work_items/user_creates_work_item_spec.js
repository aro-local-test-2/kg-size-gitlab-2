import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { screen } from '@testing-library/vue';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  assignRouter,
  fullMount,
  waitForAssertion,
  waitAndSetValue,
} from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

Vue.use(VueApollo);

const FULL_PATH = 'gitlab-org/gitlab';

describe('Work items - create from new page', () => {
  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    window.gon = {
      ...window.gon,
      current_user_avatar_url:
        'https://www.gravatar.com/avatar/d3dd6864c3471bf0791642098d9758bdd63d307d3a31ec1c0f43e49ea97d2b68?s=80&d=identicon',
      current_username: 'user136',
      current_user_fullname: 'Sidney Jones263',
    };

    await apolloProvider.defaultClient.cache.reset();
  });

  const mountNewPage = async () => {
    const router = assignRouter(createRouter, {
      fullPath: FULL_PATH,
      routerPath: 'work_items',
      routerLocation: '/work_items/work_items/new',
    });

    fullMount(WorkItemsRoot, {
      router,
      propsData: { rootPageFullPath: 'gitlab-org/gitlab' },
      apolloProvider,
      provide: {
        isGroup: false,
        isGroupIssuesList: false,
        fullPath: 'gitlab-org/gitlab',
        groupPath: 'gitlab-org',
        workItemType: 'Issue',
        isSignedIn: true,
        initialSort: 'created_desc',
      },
    });

    await waitForAssertion(() => {
      expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
    });
  };

  it('renders expected widgets for an issue', async () => {
    await mountNewPage();

    expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
    expect(screen.queryByTestId('work-item-description-wrapper')).not.toBe(null);
    expect(screen.queryByTestId('work-item-assignees')).not.toBe(null);
    expect(screen.queryByTestId('work-item-labels')).not.toBe(null);
    expect(screen.queryByTestId('work-item-milestone')).not.toBe(null);
  });

  it('supports label keyboard shortcut', async () => {
    await mountNewPage();

    const labelsWidget = screen.queryByTestId('work-item-labels');
    expect(labelsWidget).not.toBe(null);

    const editButton = labelsWidget.querySelector('[data-testid="edit-button"]');
    expect(editButton).not.toBe(null);

    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'l', bubbles: true }));

    await waitForAssertion(() => {
      const dropdown = document.querySelector('.gl-new-dropdown-panel');
      expect(dropdown).not.toBe(null);
    });
  });

  it('creates work item with title', async () => {
    await mountNewPage();

    const findTitleInput = () => screen.queryByTestId('work-item-title-input');
    await waitAndSetValue(findTitleInput, 'New test issue');

    const createButton = screen.queryByRole('button', { name: /create issue/i });
    expect(createButton).not.toBe(null);
    createButton.click();

    await waitForAssertion(() => {
      const variables = lastRequestVariables('createWorkItem');
      expect(variables).toMatchObject({
        input: expect.objectContaining({
          title: 'New test issue',
        }),
      });
    });

    await waitForAssertion(() => {
      expect(screen.queryByRole('heading', { name: 'New test issue' })).not.toBe(null);
    });
  });
});
