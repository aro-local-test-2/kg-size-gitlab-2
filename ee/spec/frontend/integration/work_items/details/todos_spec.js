import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  describeNoRefetchOnMutation,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

describe('Work item to-do toggle integration test', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // The toggle is one button that relabels itself. `whenEnabled` matters because the cache
  // write flips `aria-pressed` before the mutation settles, and GlButton drops clicks while
  // it is still aria-disabled.
  const findPendingToggle = () =>
    workItemsHelpers.whenEnabled(workItemsHelpers.findTodosToggleWithPending(true))();
  const findEmptyToggle = () =>
    workItemsHelpers.whenEnabled(workItemsHelpers.findTodosToggleWithPending(false))();

  const markTodoDoneFromDrawer = async () => {
    await workItemsHelpers.selectIssue();

    // The detail query seeds one pending to-do, so the toggle renders in
    // "mark as done" state once the drawer is open.
    await testHelpers.waitForElement(findPendingToggle);

    // Snapshot once the drawer detail query has resolved, just before the
    // mark-as-done mutation fires.
    const baseline = snapshotRequests();

    await testHelpers.waitAndClick(findPendingToggle);

    return baseline;
  };

  const addTodoFromDrawer = async () => {
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findPendingToggle);

    // Clear the seeded to-do so the next click takes the add path.
    await testHelpers.waitAndClick(findPendingToggle);
    await testHelpers.waitForElement(findEmptyToggle);

    const baseline = snapshotRequests();

    await testHelpers.waitAndClick(findEmptyToggle);

    return baseline;
  };

  // Marking the to-do done must update the Apollo cache in place via the
  // workItemUpdateCurrentUserTodos mutation and must NOT trigger a refetch of the
  // namespaceWorkItem detail query. On the features path, a mismatch between the
  // mutation's currentUserTodos selection and the query fragment (e.g. a missing
  // `state: pending` argument) writes to a different cache slot and causes a refetch.
  describeNoRefetchOnMutation({
    router,
    description: 'marks the to-do done without refetching the work item',
    perform: markTodoDoneFromDrawer,
    expectOps: ['workItemUpdateCurrentUserTodos'],
    forbidOps: ['namespaceWorkItem'],
  });

  // Adding a to-do goes through the same mutation with `action: ADD`, so it normalizes the
  // same way. It used to go through `todoCreate`, which returns a bare Todo and therefore
  // needed a hand-written cache update.
  describeNoRefetchOnMutation({
    router,
    description: 'adds a to-do without refetching the work item',
    perform: addTodoFromDrawer,
    expectOps: ['workItemUpdateCurrentUserTodos'],
    forbidOps: ['namespaceWorkItem'],
  });
});
