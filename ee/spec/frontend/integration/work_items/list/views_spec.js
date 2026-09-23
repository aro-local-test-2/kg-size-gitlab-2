import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { screen } from '@testing-library/vue';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { baseUpdateResponse, workItemsSlimResponse } from 'ee_jest/integration/work_items/handlers';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';

const workItemId = baseUpdateResponse.data.workItemUpdate.workItem.id;
// Titles live on the slim response; the full list query only selects the fields slim
// does not, to keep it under the anonymous GraphQL complexity cap.
const listNodes = workItemsSlimResponse.data.namespace.workItems.nodes;
const secondWorkItemId = listNodes.find((n) => n.title === 'Second test issue')?.id;

Vue.use(VueApollo);

describe('Work items list - views', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  const findIssueCard = () => findByGraphQLId(workItemId, getIdFromGraphQLId);
  const findSecondIssueCard = () => findByGraphQLId(secondWorkItemId, getIdFromGraphQLId);

  const createComponent = () => {
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
  };

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when the work items list page renders', () => {
    beforeEach(async () => {
      createComponent();
      await waitForElement(findIssueCard);
    });

    it('shows action buttons for signed-in user', () => {
      expect(findButtonByText('Bulk edit')).not.toBe(null);

      const links = [...document.querySelectorAll('a')];
      expect(links.some((a) => a.textContent.includes('New item'))).toBe(true);
    });

    it('shows default sort order', async () => {
      await waitAndClick(() => findButtonByText('Display'));

      await waitForAssertion(() => {
        const drawer = within(document.body).queryByTestId('display-settings-drawer');
        expect(getText(drawer)).toContain('Created date');
      });
    });

    it('displays assignee on the work item card', () => {
      expect(within(findIssueCard()).queryByTestId('assignee-link')).not.toBe(null);
    });

    it('displays milestone on the work item card', () => {
      expect(within(findIssueCard()).queryByTestId('issuable-milestone')).not.toBe(null);
      expect(getText(findIssueCard())).toContain('v1.0');
    });

    it('displays due date on the work item card', () => {
      expect(findIssueCard().querySelector('.issuable-due-date')).not.toBe(null);
    });

    it('displays labels on the work item card', () => {
      expect(findSecondIssueCard().querySelector('.gl-label')).not.toBe(null);
      expect(getText(findSecondIssueCard())).toContain('To Do');
    });

    it('displays upvotes on the work item card', () => {
      expect(within(findSecondIssueCard()).queryByTestId('issuable-upvotes')).not.toBe(null);
    });

    it('displays health status on the work item card', () => {
      expect(within(findIssueCard()).queryByTestId('status-text')).not.toBe(null);
    });

    it('displays weight on the work item card', () => {
      expect(within(findIssueCard()).queryByTestId('issuable-weight-content')).not.toBe(null);
    });

    it('shows open items and does not show closed items', () => {
      const list = document.querySelector('.issuable-list');
      const listText = getText(list);
      expect(listText).toContain('Dependent test issue');
      expect(listText).toContain('Second test issue');
      expect(listText).not.toContain('Closed test issue');
    });
  });

  describe('when creating a work item from the list modal', () => {
    beforeEach(async () => {
      window.gon = {
        ...window.gon,
        current_user_avatar_url:
          'https://www.gravatar.com/avatar/d3dd6864c3471bf0791642098d9758bdd63d307d3a31ec1c0f43e49ea97d2b68?s=80&d=identicon',
        current_username: 'user136',
        current_user_fullname: 'Sidney Jones263',
      };

      await apolloProvider.defaultClient.cache.reset();
      createComponent();
      await waitForElement(findIssueCard);

      const newItemLink = [...document.querySelectorAll('a')].find((a) =>
        a.textContent.includes('New item'),
      );
      expect(newItemLink).not.toBe(null);
      newItemLink.click();

      await waitForAssertion(() => {
        expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
      });
    });

    it('renders expected widgets in the create modal', () => {
      expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
      expect(screen.queryByTestId('work-item-description-wrapper')).not.toBe(null);
      expect(screen.queryByTestId('work-item-assignees')).not.toBe(null);
      expect(screen.queryByTestId('work-item-labels')).not.toBe(null);
      expect(screen.queryByTestId('work-item-milestone')).not.toBe(null);
    });

    describe('when the form is submitted with a title', () => {
      beforeEach(async () => {
        const findTitleInput = () => screen.queryByTestId('work-item-title-input');
        await waitAndSetValue(findTitleInput, 'New test issue');

        const createButton = screen.queryByRole('button', { name: /create issue/i });
        expect(createButton).not.toBe(null);
        createButton.click();

        await waitForAssertion(() => {
          expect(lastRequestVariables('createWorkItem')).not.toBe(undefined);
        });
      });

      it('sends the typed title', () => {
        expect(lastRequestVariables('createWorkItem')).toMatchObject({
          input: expect.objectContaining({
            title: 'New test issue',
          }),
        });
      });

      it('confirms the work item was created', async () => {
        await waitForAssertion(() => {
          expect(getText(document.querySelector('.gl-toast'))).toContain('Issue created.');
        });
      });
    });
  });
});
