import namespaceWorkItem from 'test_fixtures/graphql/work_items/integration/namespace_work_item.query.graphql.json';
import { healthStatusDropdownOptions } from 'ee/sidebar/constants';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
  describeNoRefetchOnMutation,
  FORBIDDEN_LIST_REFETCHES,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

// The fixture seeds a health status, so the spec moves the widget between that status and
// another one the dropdown offers rather than assuming which one is seeded.
const seededStatus = namespaceWorkItem.data.namespace.workItem.widgets.find(
  ({ type }) => type === 'HEALTH_STATUS',
).healthStatus;

const { text: SEEDED_LABEL } = healthStatusDropdownOptions.find(
  ({ value }) => value === seededStatus,
);
const { text: OTHER_LABEL } = healthStatusDropdownOptions.find(
  ({ value }) => value !== seededStatus,
);

describe('Work item health status widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // The widget renders on the presence of the HEALTH_STATUS widget in the detail query, so
  // opening the drawer exercises the same component tree as the full-page work item route.
  const findHealthStatusWidget = () => workItemsHelpers.findInDrawer('work-item-health-status');
  const findHealthStatusValue = () =>
    workItemsHelpers.findInDrawer('work-item-health-status-value');
  const findEditButton = workItemsHelpers.findEditButton(findHealthStatusWidget);
  const findClearButton = () => testHelpers.findButtonByText('Clear', findHealthStatusWidget());

  const findCloseIssueButton = () => {
    const stateToggle = workItemsHelpers.findInDrawer('state-toggle-action');
    return stateToggle ? testHelpers.findButtonByText('Close issue', stateToggle) : null;
  };

  const findOption = (label) => () => {
    const widget = findHealthStatusWidget();
    return widget ? testHelpers.within(widget).queryByRole('option', { name: label }) : null;
  };

  const startEditing = () => workItemsHelpers.startEditing(findHealthStatusWidget);

  const selectStatus = async (label) => {
    await startEditing();
    await testHelpers.waitAndClick(findOption(label));
  };

  const openDrawer = async () => {
    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findHealthStatusWidget);
  };

  const expectHealthStatus = (label) =>
    testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(findHealthStatusValue())).toBe(label);
    });

  const expectNoHealthStatus = () =>
    testHelpers.waitForAssertion(() => {
      expect(findHealthStatusValue()).toBe(null);
      expect(testHelpers.getText(findHealthStatusWidget())).toContain('None');
    });

  // The mutation returns `features` rather than `widgets` once the flag is on, and the
  // widget reads `features.healthStatus` first, so both shapes have to keep the UI in sync.
  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(() => {
        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });
        return openDrawer();
      });

      it('changes, clears and re-sets the health status', async () => {
        await expectHealthStatus(SEEDED_LABEL);

        await selectStatus(OTHER_LABEL);
        await expectHealthStatus(OTHER_LABEL);

        await startEditing();
        await testHelpers.waitAndClick(findClearButton);
        await expectNoHealthStatus();

        // Setting onto a cleared widget is the path the deleted Capybara example started
        // from, where the readonly view renders the empty state rather than a status.
        await selectStatus(SEEDED_LABEL);
        await expectHealthStatus(SEEDED_LABEL);
      });

      it('drops the edit button once the work item is closed', async () => {
        await testHelpers.waitForElement(findEditButton);
        const baseline = snapshotRequests();

        await testHelpers.waitAndClick(workItemsHelpers.findActionsDropdown);
        await testHelpers.waitAndClick(findCloseIssueButton);

        await testHelpers.waitForElementToBeNull(findEditButton);
        await expectHealthStatus(SEEDED_LABEL);

        // Closing reloads the list. That REST request is issued after the drawer has
        // re-rendered, so without this wait it lands after the test, once the global gon
        // reset has dropped api_version, and MSW logs it as an unhandled URL.
        await testHelpers.waitForAssertion(() => {
          expect(snapshotRequests().getWorkItemsRest).toBe(baseline.getWorkItemsRest + 1);
        });
      });
    },
  );

  const selectStatusFromDrawer = async () => {
    await openDrawer();
    await startEditing();

    // Snapshot once the dropdown has its options, just before the update mutation fires.
    const option = await testHelpers.waitForElement(findOption(OTHER_LABEL));
    const baseline = snapshotRequests();

    option.click();

    // The readonly view only renders the new status once the mutation has resolved and its
    // result is in the cache, so any cache-miss refetch has been issued by this point.
    await expectHealthStatus(OTHER_LABEL);

    return baseline;
  };

  // Changing the health status must update the Apollo cache in place via the workItemUpdate
  // mutation and must NOT refetch the work item list or the detail query.
  describeNoRefetchOnMutation({
    router,
    description: 'changes the health status without refetching the work item list',
    perform: selectStatusFromDrawer,
    expectOps: ['workItemUpdate'],
    forbidOps: [...FORBIDDEN_LIST_REFETCHES, 'namespaceWorkItem'],
  });
});
