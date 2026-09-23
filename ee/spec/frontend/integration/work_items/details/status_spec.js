import namespaceWorkItem from 'test_fixtures/graphql/work_items/integration/namespace_work_item.query.graphql.json';
import namespaceWorkItemTypes from 'test_fixtures/graphql/work_items/integration/namespace_work_item_types.query.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  namespaceWorkItem as namespaceWorkItemVariants,
  namespaceWorkItemFeatures as namespaceWorkItemFeaturesVariants,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
  describeNoRefetchOnMutation,
  FORBIDDEN_LIST_REFETCHES,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const { workItemType, widgets } = namespaceWorkItem.data.namespace.workItem;

// The fixture seeds a status, so the spec moves the widget off it rather than assuming
// which one is seeded.
const SEEDED_STATUS = widgets.find(({ type }) => type === 'STATUS').status.name;

// Unlike health status, the options are not a client-side constant: they come from the
// allowed statuses the namespace defines for this work item type.
const ALLOWED_STATUSES = namespaceWorkItemTypes.data.namespace.workItemTypes.nodes
  .find(({ name }) => name === workItemType.name)
  .widgetDefinitions.find(({ type }) => type === 'STATUS')
  .allowedStatuses.map(({ name }) => name);

const OTHER_STATUS = ALLOWED_STATUSES.find((name) => name !== SEEDED_STATUS);

describe('Work item status widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // The widget renders on the presence of the STATUS widget in the detail query, so opening
  // the drawer exercises the same component tree as the full-page work item route.
  const findStatusWidget = () => workItemsHelpers.findInDrawer('work-item-status');
  // Child items in the hierarchy section render status badges of their own, so this stays
  // scoped to the widget rather than searching the whole drawer.
  const findStatusBadge = () => {
    const widget = findStatusWidget();
    return widget ? testHelpers.within(widget).queryByTestId('work-item-status-badge') : null;
  };

  // The list row carries a status badge of its own, read off the work item in the Apollo
  // cache. The widget shows the picked option before the mutation resolves, so the row is
  // what proves the response landed - and that the list stays in step with the drawer.
  const findRowStatusBadge = () => {
    const row = workItemsHelpers.findIssueToEdit();
    return row ? testHelpers.within(row).queryByTestId('work-item-status-badge') : null;
  };

  const findOption = (name) => () => {
    const widget = findStatusWidget();
    return widget ? testHelpers.within(widget).queryByRole('option', { name }) : null;
  };

  const findOptionNames = () =>
    testHelpers
      .within(findStatusWidget())
      .queryAllByRole('option')
      .map((option) => testHelpers.getText(option));

  const startEditing = () => workItemsHelpers.startEditing(findStatusWidget);

  const selectStatus = async (name) => {
    await startEditing();
    await testHelpers.waitAndClick(findOption(name));
  };

  const openDrawer = async () => {
    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findStatusWidget);
  };

  const expectStatus = (name) =>
    testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(findStatusBadge())).toContain(name);
    });

  const expectRowStatus = (name) =>
    testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(findRowStatusBadge())).toContain(name);
    });

  // The mutation returns `features` rather than `widgets` once the flag is on, and the
  // widget reads `features.status` first, so both shapes have to keep the UI in sync.
  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(() => {
        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });
        return openDrawer();
      });

      it('changes the status and moves the list row with it', async () => {
        await expectStatus(SEEDED_STATUS);
        await expectRowStatus(SEEDED_STATUS);

        await selectStatus(OTHER_STATUS);

        await expectStatus(OTHER_STATUS);
        await expectRowStatus(OTHER_STATUS);
      });

      // The dropdown only fetches the work item types, and with them the allowed statuses,
      // once it is opened, so this covers that deferred query as well as the options.
      it('offers the statuses the namespace allows for this work item type', async () => {
        await startEditing();

        await testHelpers.waitForAssertion(() => {
          expect(findOptionNames()).toEqual(ALLOWED_STATUSES);
        });
      });
    },
  );

  const selectStatusFromDrawer = async () => {
    await openDrawer();
    await startEditing();

    // Snapshot once the dropdown has its options, just before the update mutation fires.
    const option = await testHelpers.waitForElement(findOption(OTHER_STATUS));
    const baseline = snapshotRequests();

    option.click();

    // The list row only turns over once the mutation result is in the cache, so any
    // cache-miss refetch has been issued by this point. The widget badge is no use here:
    // it renders the picked option straight away, ahead of the response.
    await expectRowStatus(OTHER_STATUS);

    return baseline;
  };

  // Changing the status must update the Apollo cache in place via the workItemUpdate
  // mutation and must NOT refetch the work item list or the detail query.
  describeNoRefetchOnMutation({
    router,
    description: 'changes the status without refetching the work item list',
    perform: selectStatusFromDrawer,
    expectOps: ['workItemUpdate'],
    forbidOps: [...FORBIDDEN_LIST_REFETCHES, 'namespaceWorkItem'],
  });

  // The frontend has no notion of a licence: the widget renders on the presence of the STATUS
  // widget in the payload, and an unlicensed namespace leaves it out. The fixtures are
  // captured from such a namespace, so this keeps proving what one actually returns, in
  // whichever shape the flag asks for. Activating the detail variant also switches the list
  // to its unlicensed payload - see the handler for why it has to.
  describe.each([false, true])(
    'when the namespace is not licensed for status and the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(async () => {
        setQueryVariant(namespaceWorkItemVariants).statusUnlicensed();
        setQueryVariant(namespaceWorkItemFeaturesVariants).statusUnlicensed();

        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });

        await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
        await workItemsHelpers.selectIssue();
      });

      it('shows no status on the work item or its list row', async () => {
        // Waits on a sibling widget so the sidebar has rendered before the assertion,
        // otherwise an empty drawer would pass this on its own.
        await testHelpers.waitForElement(workItemsHelpers.findAssigneesWidget);

        expect(findStatusWidget()).toBe(null);
        expect(findRowStatusBadge()).toBe(null);
      });
    },
  );
});
