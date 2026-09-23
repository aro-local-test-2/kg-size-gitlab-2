import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { within } from '@testing-library/vue';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  findIssueToEdit,
  findWorkItemDetail,
  selectIssue,
} from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { snapshotRequests, expectGraphQLCalls } from 'ee_jest/integration/core/operation_helpers';
import {
  namespaceWorkItem,
  workItemAgentPlan,
} from 'ee_jest/integration/work_items/fixture_variants';
import { FORBIDDEN_LIST_REFETCHES } from '../drawer_shared_test_helpers';

Vue.use(VueApollo);

describe('Work item agent plan integration test', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  const withinDrawer = () => within(document.getElementById('contextual-panel-portal'));
  const findInlineRow = () => withinDrawer().queryByTestId('work-plan-inline-row');
  const findOpenButton = () => withinDrawer().queryByTestId('open-work-plan-button');
  const findRenderedPlan = () => withinDrawer().queryByTestId('work-plan-rendered');
  const findEmptyState = () => withinDrawer().queryByTestId('work-plan-empty-state');
  const findWorkplanEditor = () => withinDrawer().queryByTestId('work-plan-editor');
  const findCreateWorkplanDropdown = () => withinDrawer().queryByTestId('create-workplan-dropdown');
  const findPlanCta = () => withinDrawer().queryByTestId('work-item-plan-cta');
  const findPanelEditButton = () => withinDrawer().queryByTestId('panel-edit-button');
  const findSaveButton = () => withinDrawer().queryByTestId('save-work-plan-button');
  const findEditorTextarea = () => findWorkplanEditor()?.querySelector('textarea');
  // The numeric score only exists inside the lazily-rendered help popover, so assert the
  // always-visible confidence level: 72 is "Medium", and a dropped score renders nothing.
  const findMediumConfidence = () => withinDrawer().queryByLabelText('Confidence: Medium');
  const mountAndOpenWorkItem = async ({ glFeatures = {} } = {}) => {
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
        glFeatures,
      },
    });

    await waitForElement(findIssueToEdit);
    await selectIssue();
  };

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when the work item has no agent plan widget', () => {
    beforeEach(async () => {
      await mountAndOpenWorkItem();
    });

    it('does not render the workplan', async () => {
      await waitForElement(findWorkItemDetail);

      expect(findInlineRow()).toBe(null);
    });
  });

  describe('when the work item has an agent plan widget with AI disabled', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItem).withAgentPlanAiDisabled();
      await mountAndOpenWorkItem();
    });

    it('does not render the workplan but shows the Plan CTA', async () => {
      await waitForElement(findWorkItemDetail);
      await waitForElement(findPlanCta);

      expect(findInlineRow()).toBe(null);
    });

    describe('when the user clicks the Plan CTA', () => {
      beforeEach(async () => {
        await waitForElement(findWorkItemDetail);
        await waitAndClick(findPlanCta);
      });

      it('reveals the workplan and hides the CTA', async () => {
        await waitForElement(findInlineRow);

        expect(findPlanCta()).toBe(null);
      });
    });
  });

  describe('when the work item has an agent plan widget with AI disabled and no update permission', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItem).withAgentPlanAiDisabledNoUpdate();
      await mountAndOpenWorkItem();
    });

    it('renders neither the workplan nor the Plan CTA', async () => {
      await waitForElement(findWorkItemDetail);

      expect(findInlineRow()).toBe(null);
      expect(findPlanCta()).toBe(null);
    });
  });

  describe('when the work item has an agent plan widget', () => {
    describe('when the user has update permission', () => {
      describe('when there is no saved workplan', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withEmptyAgentPlan();
          await mountAndOpenWorkItem();
        });

        it('shows the workplan inline row with a create action', async () => {
          await waitForElement(findInlineRow);
          // The create action appears once the standalone agent-plan query settles.
          await waitForElement(findCreateWorkplanDropdown);

          expect(getText(findInlineRow())).toContain('Not yet created');
        });

        describe('when the user opens the panel through the create dropdown', () => {
          beforeEach(async () => {
            const dropdownToggle = await waitForElement(() =>
              within(findCreateWorkplanDropdown()).queryByTestId('base-dropdown-toggle'),
            );
            dropdownToggle.click();
            await waitAndClick(() => withinDrawer().queryByTestId('create-workplan-dropdown-item'));
          });

          it('opens the panel directly in edit mode, skipping the empty state', async () => {
            await waitForElement(findWorkplanEditor);

            expect(findWorkplanEditor()).not.toBe(null);
            expect(findEmptyState()).toBe(null);
          });
        });
      });

      describe('when there is a saved workplan', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withAgentPlan();
          setQueryVariant(workItemAgentPlan).withContent();
          await mountAndOpenWorkItem();
        });

        it('shows the workplan inline row ready to review', async () => {
          await waitForElement(findInlineRow);
          // "Ready for review" appears once the standalone agent-plan query resolves with content.
          await waitForElement(findOpenButton);

          expect(getText(findInlineRow())).toContain('Ready for review');
        });

        describe('when the user opens the panel', () => {
          beforeEach(async () => {
            await waitForElement(findInlineRow);
            await waitAndClick(findOpenButton);
          });

          it('renders the saved workplan content', async () => {
            await waitForElement(findRenderedPlan);

            expect(getText(findRenderedPlan())).toContain('Existing workplan content');
          });
        });
      });

      describe('when the workplan is scored and the score flag is on', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withAgentPlan();
          setQueryVariant(workItemAgentPlan).withContentAndScore();
          await mountAndOpenWorkItem({ glFeatures: { workplanScore: true } });
          await waitForElement(findInlineRow);
          await waitAndClick(findOpenButton);
        });

        it('renders the score alongside the plan', async () => {
          await waitForElement(findMediumConfidence);

          expect(findMediumConfidence()).not.toBe(null);
        });

        describe('when the content is edited and saved', () => {
          let baseline;

          beforeEach(async () => {
            await waitForElement(findMediumConfidence);

            await waitAndClick(findPanelEditButton);
            await waitForElement(findWorkplanEditor);
            await waitAndSetValue(findEditorTextarea, 'Updated workplan content');

            baseline = snapshotRequests();
            await waitAndClick(findSaveButton);

            await waitForAssertion(() => {
              expect(getText(findRenderedPlan())).toContain('Updated workplan content');
            });
          });

          it('renders the updated content', () => {
            expect(getText(findRenderedPlan())).toContain('Updated workplan content');
          });

          it('keeps the confidence score', () => {
            expect(findMediumConfidence()).not.toBe(null);
          });

          it('serves the update from the cache without refetching the plan', () => {
            // Forbidding the refetch is what proves the surviving score came from the
            // cache write rather than the server re-supplying it.
            expectGraphQLCalls(baseline, {
              expect: ['updateWorkItemAgentPlan'],
              forbid: ['workItemAgentPlan', ...FORBIDDEN_LIST_REFETCHES],
            });
          });
        });
      });
    });

    describe('when the user has no update permission', () => {
      beforeEach(async () => {
        setQueryVariant(namespaceWorkItem).withEmptyAgentPlanNoUpdate();
        await mountAndOpenWorkItem();
      });

      it('shows the workplan inline row without a create action', async () => {
        await waitForElement(findInlineRow);

        expect(getText(findInlineRow())).toContain('No workplan');
        expect(findOpenButton()).toBe(null);
        expect(findCreateWorkplanDropdown()).toBe(null);
      });
    });
  });
});
