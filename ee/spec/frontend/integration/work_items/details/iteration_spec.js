import namespaceWorkItem from 'test_fixtures/graphql/work_items/integration/namespace_work_item.query.graphql.json';
import projectIterations from 'test_fixtures/graphql/work_items/integration/project_iterations.query.graphql.json';
import projectIterationsSearch from 'test_fixtures/graphql/work_items/integration/project_iterations_search.query.graphql.json';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
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

// Closed iterations are absent because the dropdown queries `state: opened`; the fixture
// generator asserts that filter, so everything here is the open set.
const openIterations = projectIterations.data.namespace.attributes.nodes;
const seededIteration = namespaceWorkItem.data.namespace.workItem.widgets.find(
  ({ type }) => type === 'ITERATION',
).iteration;

const [targetIteration] = projectIterationsSearch.data.namespace.attributes.nodes;

const uniqueCadenceTitles = (iterations) =>
  [...new Set(iterations.map(({ iterationCadence }) => iterationCadence.title))].sort();

describe('Work item iteration widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // The widget renders on the presence of the ITERATION widget in the detail query, so
  // opening the drawer exercises the same component tree as the full-page work item route.
  const findIterationWidget = () => workItemsHelpers.findInDrawer('work-item-iteration');
  const findIterationLink = () => workItemsHelpers.findInDrawer('work-item-iteration-link');
  const findListbox = () => findIterationWidget()?.querySelector('[role="listbox"]') ?? null;
  const findSearchInput = () =>
    findIterationWidget()?.querySelector('input[type="search"]') ?? null;

  const findCadenceGroups = () =>
    Array.from(findListbox()?.querySelectorAll('[role="group"]') ?? []);
  const cadenceTitleOf = (group) =>
    testHelpers.getText(group.querySelector('[role="presentation"]'));
  const findVisibleCadenceTitles = () => findCadenceGroups().map(cadenceTitleOf).sort();
  const findAllOptions = () => Array.from(findListbox()?.querySelectorAll('[role="option"]') ?? []);

  const findTargetOption = () => {
    const group = findCadenceGroups().find(
      (candidate) => cadenceTitleOf(candidate) === targetIteration.iterationCadence.title,
    );
    return group?.querySelector('[role="option"]') ?? null;
  };

  const findClearButton = () => testHelpers.findButtonByText('Clear', findIterationWidget());

  const startEditing = () => workItemsHelpers.startEditing(findIterationWidget);

  const openDrawer = async () => {
    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findIterationWidget);
  };

  const reopenDrawer = async () => {
    workItemsHelpers.clickIssue();
    await testHelpers.waitForElementToBeNull(workItemsHelpers.findWorkItemDetail);
    await openDrawer();
  };

  const expectIterationLinkTo = (iteration) =>
    testHelpers.waitForAssertion(() => {
      const link = findIterationLink();
      expect(link).not.toBe(null);
      expect(link.dataset.iteration).toBe(String(getIdFromGraphQLId(iteration.id)));
      expect(link.getAttribute('href')).toBe(iteration.webUrl);
      expect(testHelpers.getText(findIterationWidget())).toContain(
        iteration.iterationCadence.title,
      );
    });

  describe('the dropdown', () => {
    beforeEach(() => {
      mountWorkItemsListApp({ router });
      return openDrawer();
    });

    it('lists every open iteration grouped by its cadence', async () => {
      await startEditing();

      await testHelpers.waitForAssertion(() => {
        expect(findAllOptions()).toHaveLength(openIterations.length);
        expect(findVisibleCadenceTitles()).toEqual(uniqueCadenceTitles(openIterations));
      });
    });

    it('narrows the list to the cadence matching the search term', async () => {
      await startEditing();
      await testHelpers.waitForAssertion(() => {
        expect(findVisibleCadenceTitles()).toEqual(uniqueCadenceTitles(openIterations));
      });

      await testHelpers.waitAndSetValue(findSearchInput, 'plan');

      await testHelpers.waitForAssertion(() => {
        expect(findVisibleCadenceTitles()).toEqual(
          uniqueCadenceTitles(projectIterationsSearch.data.namespace.attributes.nodes),
        );
      });
    });
  });

  // The mutation returns `features` rather than `widgets` once the flag is on, and the
  // widget reads `features.iteration` first, so both shapes have to keep the UI in sync.
  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(() => {
        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });
        return openDrawer();
      });

      it('clears the iteration and selects one from another cadence', async () => {
        await expectIterationLinkTo(seededIteration);

        await startEditing();
        await testHelpers.waitAndClick(findClearButton);

        await testHelpers.waitForAssertion(() => {
          expect(testHelpers.getText(findIterationWidget())).toContain('None');
          expect(findIterationLink()).toBe(null);
        });

        await startEditing();
        const option = await testHelpers.waitForElement(findTargetOption);
        const optionText = testHelpers.getText(option);
        option.click();

        await expectIterationLinkTo(targetIteration);
        // The readonly view and the dropdown must render the same iteration period.
        expect(testHelpers.getText(findIterationLink())).toBe(optionText);

        await reopenDrawer();
        await expectIterationLinkTo(targetIteration);
      });
    },
  );

  const selectIterationFromDrawer = async () => {
    await openDrawer();
    await startEditing();

    // Snapshot once the dropdown has its options, just before the update mutation fires.
    const option = await testHelpers.waitForElement(findTargetOption);
    const baseline = snapshotRequests();

    option.click();

    // The readonly view only renders the new iteration once the mutation has resolved and
    // its result is in the cache, so any cache-miss refetch has been issued by this point.
    await expectIterationLinkTo(targetIteration);

    return baseline;
  };

  // Selecting an iteration must update the Apollo cache in place via the workItemUpdate
  // mutation and must NOT refetch the work item list or the detail query.
  describeNoRefetchOnMutation({
    router,
    description: 'selects an iteration without refetching the work item list',
    perform: selectIterationFromDrawer,
    expectOps: ['workItemUpdate'],
    forbidOps: [...FORBIDDEN_LIST_REFETCHES, 'namespaceWorkItem'],
  });
});
