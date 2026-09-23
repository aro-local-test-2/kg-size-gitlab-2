import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  describeNoRefetchOnMutation,
} from '../drawer_shared_test_helpers';
import { setUserSession } from '../../helpers/setup_utils';

setupWorkItemsListApollo();

describe('Work item linked items integration test', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const addLinkedItemFromDrawer = async () => {
    await workItemsHelpers.selectIssue();

    await testHelpers.waitForElement(workItemsHelpers.findRelationshipsWidget);
    await testHelpers.waitAndClick(workItemsHelpers.findLinkItemAddButton);
    await testHelpers.waitForElement(workItemsHelpers.findLinkItemForm);

    const input = await testHelpers.waitForElement(workItemsHelpers.findTokenSelectorInput);
    input.dispatchEvent(new Event('focus', { bubbles: true }));

    await testHelpers.waitAndClick(workItemsHelpers.findTokenSelectorResult);

    // Snapshot once the linked item is selected, just before the add mutation fires.
    const baseline = snapshotRequests();

    await testHelpers.waitAndClick(workItemsHelpers.findLinkWorkItemSubmitButton);

    return baseline;
  };

  const removeLinkedItemFromDrawer = async () => {
    // `vuedraggable` does not render rows in jsdom on Vue 3, so force the
    // non-draggable list (`canReorder` is `isLoggedIn() && canUpdate`) to get a
    // clickable remove button. Cache/network behaviour is the same either way.
    setUserSession(false);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(workItemsHelpers.findRelationshipsWidget);

    // The linked items query seeds one item, so a row renders on mount.
    // Snapshot once it is rendered, just before the remove mutation fires.
    await testHelpers.waitForElement(workItemsHelpers.findRemoveLinkedItemButton);
    const baseline = snapshotRequests();

    await testHelpers.waitAndClick(workItemsHelpers.findRemoveLinkedItemButton);

    return baseline;
  };

  // Adding a linked item must update the Apollo cache in place via the
  // addLinkedItems mutation and must NOT trigger a refetch of the
  // workItemLinkedItems query.
  describeNoRefetchOnMutation({
    router,
    description: 'adds a linked item without refetching the linked items list',
    perform: addLinkedItemFromDrawer,
    expectOps: ['addLinkedItems'],
    forbidOps: ['workItemLinkedItems'],
  });

  // Removing a linked item must update the Apollo cache in place via the
  // removeLinkedItems mutation and must NOT trigger a refetch of the
  // workItemLinkedItems query.
  describeNoRefetchOnMutation({
    router,
    description: 'removes a linked item without refetching the linked items list',
    perform: removeLinkedItemFromDrawer,
    expectOps: ['removeLinkedItems'],
    forbidOps: ['workItemLinkedItems'],
  });
});
