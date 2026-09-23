import { GlButtonGroup, GlDisclosureDropdown, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { assertProps } from 'helpers/assert_props';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import WorkPlanInlineRow from 'ee/work_items/components/ai_widget/work_plan_inline_row.vue';
import AiWidgetSegment from 'ee/vue_shared/components/work_items/ai_widget_segment.vue';
import WorkPlanStatusBar from 'ee/work_items/components/ai_widget/work_plan_status_bar.vue';
import DuoChatQuickAction from 'ee/ai/shared/widgets/duo_chat_quick_action.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import { GENERATION_STATUSES_ACTIVE } from 'ee/work_items/components/ai_widget/constants';

describe('WorkPlanInlineRow', () => {
  let wrapper;

  const duoMrActionProps = {
    projectPath: 'group/project',
    workItemIid: '42',
    workItemType: 'Epic',
    workItemWebUrl: '/group/project/-/work_items/42',
    generateMrButtonOptions: { size: 'medium', variant: 'confirm', category: 'primary' },
  };

  const duoMrActionComponentProps = {
    hasContent: true,
    canUpdate: true,
    hasRemoteFlowsEnabled: true,
    ...duoMrActionProps,
  };

  const defaultProps = {
    workItemId: 'gid://gitlab/WorkItem/1',
    isLoading: false,
  };

  // Takes the run state flat and assembles the `generation` prop, so each test reads as
  // the scenario it describes rather than as an object literal.
  const createComponent = (
    {
      generationStatus = null,
      hasAwaitedInput = false,
      isFlowActionInFlight = false,
      isRunning = GENERATION_STATUSES_ACTIVE.includes(generationStatus),
      isStarting = isRunning && !GENERATION_STATUSES_ACTIVE.includes(generationStatus),
      ...props
    } = {},
    provide = {},
  ) => {
    wrapper = shallowMountExtended(WorkPlanInlineRow, {
      propsData: {
        ...defaultProps,
        generation: {
          status: generationStatus,
          hasAwaitedInput,
          actionInFlight: isFlowActionInFlight,
          isRunning,
          isStarting,
        },
        ...props,
      },
      provide: { glFeatures: {}, ...provide },
      stubs: { DuoWorkItemToMrAction: true, AiWidgetSegment, HelpPopover, GlSprintf },
    });
  };

  const findRow = () => wrapper.findByTestId('work-plan-inline-row');
  const findOpenButton = () => wrapper.findComponentByTestId('open-work-plan-button');
  const findDuoWorkItemToMrAction = () => wrapper.findComponent(DuoWorkItemToMrAction);
  const findButtonGroup = () => wrapper.findComponent(GlButtonGroup);
  const findDisclosureDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findDuoChatAction = () => wrapper.findComponent(DuoChatQuickAction);
  const findGenerateButton = () => wrapper.findComponentByTestId('inline-generate-button');
  const findHelpPopover = () => wrapper.findComponent(HelpPopover);
  const findHelpPopoverLink = () => findHelpPopover().findComponent(GlLink);
  const findWorkPlanStatusBar = () => wrapper.findComponent(WorkPlanStatusBar);
  const findAwaitingInputIcon = () => wrapper.findComponentByTestId('awaiting-input-icon');
  const findRetryButton = () => wrapper.findComponentByTestId('retry-workplan-button');
  const findContinueButton = () => wrapper.findComponentByTestId('continue-workplan-button');

  describe('help popover', () => {
    it('is shown before a workplan exists', () => {
      createComponent({ hasContent: false });
      expect(findHelpPopover().exists()).toBe(true);
    });

    it('is hidden once a workplan exists', () => {
      createComponent({ hasContent: true });
      expect(findHelpPopover().exists()).toBe(false);
    });

    it('explains what a workplan is and links to the docs', () => {
      createComponent({ hasContent: false });
      expect(findHelpPopover().props('options').title).toBe('What is a workplan?');
      expect(findHelpPopover().text()).toContain('breaks a work item into clear, ordered steps');
      expect(findHelpPopoverLink().text()).toBe('Learn more');
      expect(findHelpPopoverLink().attributes('href')).toBe('/help/user/work_items/workplan');
    });
  });

  describe('status label', () => {
    describe('when there is no content', () => {
      describe('and user can update', () => {
        beforeEach(() => {
          createComponent({ hasContent: false, canUpdate: true });
        });

        it('shows "Not yet created"', () => {
          expect(findRow().text()).toContain('Workplan');
          expect(findRow().text()).toContain('Not yet created');
        });
      });

      describe('and user cannot update', () => {
        beforeEach(() => {
          createComponent({ hasContent: false, canUpdate: false });
        });

        it('shows "No workplan"', () => {
          expect(findRow().text()).toContain('No workplan');
        });
      });
    });

    describe('when there is content', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: true });
      });

      it('shows "Ready for review"', () => {
        expect(findRow().text()).toContain('Ready for review');
      });
    });
  });

  describe('create actions (empty state)', () => {
    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({ hasContent: false, canUpdate: false });
      });

      it('does not show a create action', () => {
        expect(findOpenButton().exists()).toBe(false);
        expect(findButtonGroup().exists()).toBe(false);
      });
    });

    describe('while the plan is still loading', () => {
      beforeEach(() => {
        createComponent({ hasContent: false, canUpdate: true, isLoading: true });
      });

      it('does not offer the create action until the fetch settles', () => {
        expect(findDisclosureDropdown().exists()).toBe(false);
      });
    });
  });

  describe('Split button with dropdown', () => {
    describe('when there is no content and user can update', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
          canUpdate: true,
        });
      });

      it('shows the button group', () => {
        expect(findButtonGroup().exists()).toBe(true);
      });

      it('shows the disclosure dropdown', () => {
        expect(findDisclosureDropdown().exists()).toBe(true);
      });

      it('dropdown contains "Create manually" option', () => {
        const dropdownItems = findDisclosureDropdown().props('items');
        expect(dropdownItems).toHaveLength(1);
        expect(dropdownItems[0].text).toBe('Create manually');
      });

      it('emits "create-manually" when dropdown action is triggered', async () => {
        await findDisclosureDropdown().vm.$emit('action');
        expect(wrapper.emitted('create-manually')).toHaveLength(1);
        expect(wrapper.emitted('open')).toBeUndefined();
      });
    });

    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({
          hasContent: true,
          canUpdate: true,
          workItemId: 'gid://gitlab/WorkItem/1',
        });
      });

      it('does not show the split button', () => {
        expect(findButtonGroup().exists()).toBe(false);
      });
    });
  });

  describe('View toggle button', () => {
    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: true });
      });

      it('shows "View" button', () => {
        expect(findOpenButton().text()).toBe('View');
      });

      it('emits "open" when clicked', async () => {
        await findOpenButton().vm.$emit('click');
        expect(wrapper.emitted('open')).toHaveLength(1);
      });
    });

    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: false });
      });

      it('still shows the button (read-only viewers can view)', () => {
        expect(findOpenButton().exists()).toBe(true);
      });
    });

    describe('when panel is open', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, isPanelOpen: true });
      });

      it('reflects the panel-open state via aria-pressed', () => {
        expect(findOpenButton().attributes('aria-pressed')).toBe('true');
      });
    });
  });

  describe('Duo actions', () => {
    describe('when content is missing', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
          canUpdate: true,
          workItemId: 'gid://gitlab/WorkItem/1',
        });
      });

      it('shows Generate-workplan chat action', () => {
        expect(findDuoChatAction().exists()).toBe(true);
      });

      it('does not show Generate-MR action', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });

      it('emits "open-chat-request" when DuoChatQuickAction is clicked', async () => {
        await findDuoChatAction().vm.$emit('click');
        expect(wrapper.emitted('open-chat-request')).toHaveLength(1);
      });

      it('emits "open-chat-completed" when DuoChatQuickAction emits "chat-opened"', async () => {
        await findDuoChatAction().vm.$emit('chat-opened');
        expect(wrapper.emitted('open-chat-completed')).toHaveLength(1);
        expect(wrapper.emitted('open')).toBeUndefined();
      });
    });

    describe('when content exists', () => {
      describe('and remote flows are enabled', () => {
        beforeEach(() => {
          createComponent({
            ...duoMrActionComponentProps,
            canUpdate: true,
            workItemId: 'gid://gitlab/WorkItem/1',
          });
        });

        it('does not show Generate-workplan chat action', () => {
          expect(findDuoChatAction().exists()).toBe(false);
        });

        it('shows Generate-MR action', () => {
          expect(findDuoWorkItemToMrAction().exists()).toBe(true);
        });

        it('passes correct props to Generate-MR action', () => {
          expect(findDuoWorkItemToMrAction().props()).toMatchObject({
            ...duoMrActionProps,
          });
        });
      });

      describe('and remote flows are disabled', () => {
        beforeEach(() => {
          createComponent({
            hasContent: true,
            canUpdate: true,
            workItemId: 'gid://gitlab/WorkItem/1',
            hasRemoteFlowsEnabled: false,
          });
        });

        it('does not show Generate-workplan button', () => {
          expect(wrapper.findByTestId('inline-generate-with-duo-button').exists()).toBe(false);
        });

        it('does not show Generate-MR action', () => {
          expect(findDuoWorkItemToMrAction().exists()).toBe(false);
        });
      });
    });
  });

  describe('Duo "Generate MR" button', () => {
    describe('when content exists and remote flows are enabled', () => {
      beforeEach(() => {
        createComponent(duoMrActionComponentProps);
      });

      it('is shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(true);
      });

      it('passes correct props', () => {
        expect(findDuoWorkItemToMrAction().props()).toMatchObject({
          ...duoMrActionProps,
        });
      });
    });

    describe('when content is empty', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
          hasRemoteFlowsEnabled: true,
        });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    describe('when remote flows are disabled', () => {
      beforeEach(() => {
        createComponent({
          hasContent: true,
          hasRemoteFlowsEnabled: false,
        });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({
          hasContent: true,
          canUpdate: false,
          hasRemoteFlowsEnabled: true,
        });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    it('passes correct props', () => {
      createComponent({
        hasContent: true,
        canUpdate: true,
        hasRemoteFlowsEnabled: true,
        projectPath: 'group/project',
        workItemIid: '42',
        workItemType: 'Epic',
        workItemWebUrl: '/group/project/-/work_items/42',
      });
      expect(findDuoWorkItemToMrAction().props()).toMatchObject({
        projectPath: 'group/project',
        workItemIid: '42',
        workItemType: 'Epic',
        workItemWebUrl: '/group/project/-/work_items/42',
      });
    });
  });

  describe('signal bar', () => {
    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({ hasContent: true });
      });

      it('uses the success variant', () => {
        expect(findWorkPlanStatusBar().props('variant')).toBe('success');
      });

      it('labels the bar with the status', () => {
        expect(findWorkPlanStatusBar().attributes('aria-label')).toBe('Ready for review');
      });
    });

    describe('when content is missing', () => {
      beforeEach(() => {
        createComponent({ hasContent: false });
      });

      it('uses the neutral variant', () => {
        expect(findWorkPlanStatusBar().props('variant')).toBe('neutral');
      });
    });
  });

  describe('async generation states', () => {
    describe.each`
      scenario                              | generationStatus | hasAwaitedInput | hasContent | label                       | variant
      ${'a run is reviewing the work item'} | ${'GENERATING'}  | ${false}        | ${false}   | ${'Reviewing work item...'} | ${'info'}
      ${'a resumed run is writing a plan'}  | ${'GENERATING'}  | ${true}         | ${false}   | ${'Generating workplan...'} | ${'info'}
      ${'a run is waiting on the user'}     | ${'NEEDS_INPUT'} | ${false}        | ${false}   | ${'Awaiting input'}         | ${'warning'}
      ${'a run ended without a plan'}       | ${'FAILED'}      | ${false}        | ${false}   | ${'Generation failed'}      | ${'error'}
      ${'a run is writing over a plan'}     | ${'GENERATING'}  | ${false}        | ${true}    | ${'Generating workplan...'} | ${'info'}
      ${'a resumed run has a saved plan'}   | ${'GENERATING'}  | ${true}         | ${true}    | ${'Generating workplan...'} | ${'info'}
      ${'a run with a plan wants input'}    | ${'NEEDS_INPUT'} | ${false}        | ${true}    | ${'Awaiting input'}         | ${'warning'}
      ${'a plan outlives a failed run'}     | ${'FAILED'}      | ${false}        | ${true}    | ${'Ready for review'}       | ${'success'}
    `('when $scenario', ({ generationStatus, hasAwaitedInput, hasContent, label, variant }) => {
      beforeEach(() => {
        createComponent({ generationStatus, hasAwaitedInput, hasContent, canUpdate: true });
      });

      it(`reports "${label}"`, () => {
        expect(findRow().text()).toContain(label);
      });

      it(`marks the status bar ${variant}`, () => {
        expect(findWorkPlanStatusBar().props('variant')).toBe(variant);
      });
    });

    describe.each`
      scenario                              | generationStatus | hasContent | generate | retry    | continueRun
      ${'a run is reviewing the work item'} | ${'GENERATING'}  | ${false}   | ${false} | ${false} | ${false}
      ${'a run is waiting on the user'}     | ${'NEEDS_INPUT'} | ${false}   | ${false} | ${false} | ${true}
      ${'a regenerate wants input'}         | ${'NEEDS_INPUT'} | ${true}    | ${false} | ${false} | ${true}
      ${'a run ended without a plan'}       | ${'FAILED'}      | ${false}   | ${false} | ${true}  | ${false}
      ${'a plan outlives a failed run'}     | ${'FAILED'}      | ${true}    | ${false} | ${false} | ${false}
      ${'no run is in progress'}            | ${'COMPLETED'}   | ${false}   | ${true}  | ${false} | ${false}
    `('when $scenario', ({ generationStatus, hasContent, generate, retry, continueRun }) => {
      beforeEach(() => {
        createComponent({ generationStatus, hasContent, canUpdate: true });
      });

      it(`${generate ? 'offers' : 'withholds'} the Generate action`, () => {
        expect(findButtonGroup().exists()).toBe(generate);
      });

      it(`${retry ? 'offers' : 'withholds'} Try again`, () => {
        expect(findRetryButton().exists()).toBe(retry);
      });

      it(`${continueRun ? 'offers' : 'withholds'} Continue`, () => {
        expect(findContinueButton().exists()).toBe(continueRun);
      });
    });

    describe('when a run is waiting on the user and no plan exists yet', () => {
      beforeEach(() => {
        createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: false, canUpdate: true });
      });

      it('marks the status with the awaiting-input icon', () => {
        expect(findAwaitingInputIcon().props()).toMatchObject({
          name: 'status',
          variant: 'warning',
        });
      });

      it('hides the help popover, leaving the status as the only claim about the plan', () => {
        expect(findHelpPopover().exists()).toBe(false);
      });
    });

    it('keeps the awaiting-input icon when a regenerate wants input over a saved plan', () => {
      createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: true, canUpdate: true });

      expect(findAwaitingInputIcon().exists()).toBe(true);
    });

    it('offers Continue over View, so a paused regenerate can be answered', () => {
      createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: true, canUpdate: true });

      expect(findContinueButton().exists()).toBe(true);
      expect(findOpenButton().exists()).toBe(false);
    });

    it('reads as ready the moment a first run lands its plan, before the status catches up', () => {
      createComponent({
        generationStatus: 'GENERATING',
        hasContent: true,
        isRunning: false,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Ready for review');
      expect(findWorkPlanStatusBar().props('variant')).toBe('success');
    });

    it('reports the run before its status arrives, so a click is acknowledged at once', () => {
      createComponent({
        generationStatus: 'COMPLETED',
        hasContent: true,
        isRunning: true,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Preparing to generate...');
      expect(findWorkPlanStatusBar().props('variant')).toBe('info');
    });

    it('drops the preparing status once the run reports itself', () => {
      createComponent({
        generationStatus: 'GENERATING',
        hasContent: true,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Generating workplan...');
    });

    describe('while a run is regenerating the plan', () => {
      beforeEach(() => {
        createComponent({
          generationStatus: 'GENERATING',
          hasContent: true,
          canUpdate: true,
          hasRemoteFlowsEnabled: true,
        });
      });

      it('hides View, since the plan is about to be replaced', () => {
        expect(findOpenButton().exists()).toBe(false);
      });

      it('hides Implement, so Duo cannot start from a plan on its way out', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    it('drops the awaiting-input icon when no run is waiting', () => {
      createComponent({ generationStatus: 'GENERATING', hasContent: false, canUpdate: true });

      expect(findAwaitingInputIcon().exists()).toBe(false);
    });

    describe('when a run is waiting on the user', () => {
      it('asks the parent to resume the run', () => {
        createComponent({ generationStatus: 'NEEDS_INPUT', canUpdate: true });

        findContinueButton().vm.$emit('click');

        expect(wrapper.emitted('continue')).toHaveLength(1);
      });

      it('withholds Continue from a user who cannot update the work item', () => {
        createComponent({ generationStatus: 'NEEDS_INPUT', canUpdate: false });

        expect(findContinueButton().exists()).toBe(false);
      });

      it('marks Continue as loading while the resume is in flight', () => {
        createComponent({
          generationStatus: 'NEEDS_INPUT',
          canUpdate: true,
          isFlowActionInFlight: true,
        });

        expect(findContinueButton().props('loading')).toBe(true);
      });
    });

    describe('when a run ended without a plan', () => {
      it('asks the parent to retry', () => {
        createComponent({ generationStatus: 'FAILED', canUpdate: true });

        findRetryButton().vm.$emit('click');

        expect(wrapper.emitted('retry')).toHaveLength(1);
      });

      it('withholds Try again from a user who cannot update the work item', () => {
        createComponent({ generationStatus: 'FAILED', canUpdate: false });

        expect(findRetryButton().exists()).toBe(false);
      });
    });
  });

  describe('when async generation is enabled', () => {
    beforeEach(() => {
      createComponent({ hasContent: false, canUpdate: true, canGenerateAsync: true });
    });

    it('offers Generate as a plain action rather than a Duo Chat hand-off', () => {
      expect(findGenerateButton().exists()).toBe(true);
      expect(findDuoChatAction().exists()).toBe(false);
    });

    it('asks the parent to start a run', () => {
      findGenerateButton().vm.$emit('click');

      expect(wrapper.emitted('generate')).toHaveLength(1);
    });

    it('keeps the Create manually option alongside it', () => {
      expect(findDisclosureDropdown().exists()).toBe(true);
    });

    it('shows Generate as loading while a run is starting', () => {
      createComponent({
        hasContent: false,
        canUpdate: true,
        canGenerateAsync: true,
        isFlowActionInFlight: true,
      });

      expect(findGenerateButton().props('loading')).toBe(true);
    });
  });

  describe('when async generation is disabled', () => {
    it('keeps the Duo Chat hand-off', () => {
      createComponent({ hasContent: false, canUpdate: true, canGenerateAsync: false });

      expect(findDuoChatAction().exists()).toBe(true);
      expect(findGenerateButton().exists()).toBe(false);
    });
  });

  describe('generation prop validation', () => {
    it.each(['NOT_STARTED', 'GENERATING', 'NEEDS_INPUT', 'COMPLETED', 'FAILED', null])(
      'accepts the %s status',
      (status) => {
        expect(() =>
          assertProps(WorkPlanInlineRow, { ...defaultProps, generation: { status } }),
        ).not.toThrow();
      },
    );

    it('rejects a status the backend enum cannot return', () => {
      expect(() =>
        assertProps(WorkPlanInlineRow, { ...defaultProps, generation: { status: 'PENDING' } }),
      ).toThrow();
    });
  });
});
