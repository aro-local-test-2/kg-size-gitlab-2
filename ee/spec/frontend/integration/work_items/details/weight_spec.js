import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

// The widget renders on the presence of the WEIGHT widget in the detail query,
// so opening the drawer exercises the same component tree
// as the full-page work item route.
describe('Work item weight widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const findWeightWidget = () => workItemsHelpers.findInDrawer('work-item-weight');
  const findWeightInput = () => findWeightWidget()?.querySelector('#weight-widget-input') ?? null;

  const findInWeightWidget = (testId) => {
    const widget = findWeightWidget();
    return widget ? testHelpers.within(widget).queryByTestId(testId) : null;
  };

  const findApplyButton = () => findInWeightWidget('apply-button');
  const findRemoveWeightButton = () => findInWeightWidget('remove-weight');

  // The widget edits through a number input rather than a listbox, so it reuses the
  // shared enabled-edit-button finder instead of the shared `startEditing`.
  const startEditingWeight = async () => {
    await testHelpers.waitAndClick(workItemsHelpers.findEnabledEditButton(findWeightWidget));
    await testHelpers.waitForElement(findWeightInput);
  };

  const setWeight = async (weight) => {
    await startEditingWeight();
    await testHelpers.waitAndSetValue(findWeightInput, weight);
    await testHelpers.waitAndClick(findApplyButton);
  };

  const clearWeight = async () => {
    await startEditingWeight();
    await testHelpers.waitAndClick(findRemoveWeightButton);
  };

  const expectWeightText = (text) =>
    testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(findWeightWidget())).toContain(text);
    });

  // The mutation returns `features` rather than `widgets` once the flag is on, and the
  // widget reads `features.weight` first, so both shapes have to keep the UI in sync.
  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(async () => {
        // cache_utils reads window.gon.features while the query variables come from
        // glFeatures, so both have to resolve to the same cache variant.
        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });
        await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
        await workItemsHelpers.selectIssue();
        await testHelpers.waitForElement(findWeightWidget);
      });

      it('sets, zeroes, clears and re-sets the weight', async () => {
        await expectWeightText('3');

        // A weight of 0 is falsy but still a set value, so it must render as "0"
        // rather than falling through to the "None" empty state.
        await setWeight('0');
        await expectWeightText('0');
        expect(testHelpers.getText(findWeightWidget())).not.toContain('None');

        await clearWeight();
        await expectWeightText('None');

        // Re-setting onto a cleared widget is the path the deleted Capybara example
        // started from, where the remove button is not rendered yet.
        await setWeight('5');
        await expectWeightText('5');
      });
    },
  );
});
