import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkPlanPanel from 'ee/work_items/components/ai_widget/work_plan_panel.vue';
import WorkPlanView from 'ee/work_items/components/ai_widget/work_plan_view.vue';
import WorkPlanEditor from 'ee/work_items/components/ai_widget/work_plan_editor.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import {
  WORKPLAN_GOAL_PREFIX,
  GENERATE_MR_BUTTON_OPTIONS,
} from 'ee/work_items/components/ai_widget/constants';

const MountingPortalStub = {
  name: 'MountingPortal',
  template: '<div data-testid="mounting-portal-stub"><slot /></div>',
};

const DynamicPanelStub = {
  name: 'DynamicPanel',
  props: ['shouldFillContent'],
  template: '<div><slot name="header"></slot><slot name="actions"></slot><slot></slot></div>',
};

const defaultProps = {
  open: true,
  workItemId: 'gid://gitlab/WorkItem/1',
  canUpdate: true,
  savedContent: '',
  savedContentHtml: '',
  draftContent: '',
  isEditing: false,
  isSaving: false,
  isLoading: false,
  workItemIid: '1',
  workItemType: 'Issue',
  workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
  hasRemoteFlowsEnabled: false,
};

describe('WorkPlanPanel', () => {
  let wrapper;

  const createComponent = ({ fullPath = 'group/project', ...props } = {}) => {
    wrapper = shallowMountExtended(WorkPlanPanel, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: { fullPath },
      stubs: {
        MountingPortal: MountingPortalStub,
        DynamicPanel: DynamicPanelStub,
      },
    });
  };

  const findPortal = () => wrapper.findByTestId('mounting-portal-stub');
  const findPanel = () => wrapper.findByTestId('work-plan-panel');
  const findDynamicPanel = () => wrapper.findComponent(DynamicPanel);
  const findView = () => wrapper.findComponent(WorkPlanView);
  const findEditor = () => wrapper.findComponent(WorkPlanEditor);
  const findEditButton = () => wrapper.findComponentByTestId('panel-edit-button');
  const findMoreActionsDropdown = () => wrapper.findComponentByTestId('panel-edit-more-actions');
  const findGenerateMrButton = () => wrapper.findByTestId('panel-generate-mr-with-duo');

  describe('rendering', () => {
    describe('when open is false', () => {
      beforeEach(() => {
        createComponent({ open: false });
      });

      it('does not render the portal', () => {
        expect(findPortal().exists()).toBe(false);
      });
    });

    describe('when open is true', () => {
      beforeEach(() => {
        createComponent({ open: true });
      });

      it('renders the panel chrome', () => {
        expect(findPanel().exists()).toBe(true);
      });
    });
  });

  describe('mode switching', () => {
    describe('when not editing', () => {
      beforeEach(() => {
        createComponent({ isEditing: false, savedContent: 'plan' });
      });

      it('renders the view and not the editor', () => {
        expect(findView().exists()).toBe(true);
        expect(findEditor().exists()).toBe(false);
      });

      it('does not fill the panel content', () => {
        expect(findDynamicPanel().props('shouldFillContent')).toBe(false);
      });

      it('forwards the view props', () => {
        expect(findView().props()).toMatchObject({
          isLoading: false,
          canUpdate: true,
          savedContent: 'plan',
          workItemId: 'gid://gitlab/WorkItem/1',
          workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
        });
      });

      describe('when the view emits start-edit', () => {
        beforeEach(() => {
          findView().vm.$emit('start-edit');
        });

        it('emits "start-edit"', () => {
          expect(wrapper.emitted('start-edit')).toHaveLength(1);
        });
      });
    });

    describe('when editing', () => {
      beforeEach(() => {
        createComponent({ isEditing: true, savedContent: 'plan', draftContent: 'draft' });
      });

      it('renders the editor and not the view', () => {
        expect(findEditor().exists()).toBe(true);
        expect(findView().exists()).toBe(false);
      });

      it('fills the panel content so the editor stretches to the panel height', () => {
        expect(findDynamicPanel().props('shouldFillContent')).toBe(true);
      });

      it('forwards the editor props', () => {
        expect(findEditor().props()).toMatchObject({
          savedContent: 'plan',
          draftContent: 'draft',
          isSaving: false,
        });
      });

      describe('when the editor emits save', () => {
        beforeEach(() => {
          findEditor().vm.$emit('save', 'updated plan');
        });

        it('emits "save" with the content', () => {
          expect(wrapper.emitted('save')).toEqual([['updated plan']]);
        });
      });

      describe('when the editor emits cancel-edit', () => {
        beforeEach(() => {
          findEditor().vm.$emit('cancel-edit');
        });

        it('emits "cancel-edit"', () => {
          expect(wrapper.emitted('cancel-edit')).toHaveLength(1);
        });
      });

      describe('when the editor emits draft-change', () => {
        beforeEach(() => {
          findEditor().vm.$emit('draft-change', 'half-typed');
        });

        it('emits "draft-change" with the value', () => {
          expect(wrapper.emitted('draft-change')).toEqual([['half-typed']]);
        });
      });
    });
  });

  describe('Generate MR action', () => {
    describe('when remote flows are enabled and content exists', () => {
      beforeEach(() => {
        createComponent({ savedContent: 'Some plan content', hasRemoteFlowsEnabled: true });
      });

      it('renders the button', () => {
        expect(findGenerateMrButton().exists()).toBe(true);
      });

      it('forwards the expected props to DuoWorkItemToMrAction', () => {
        expect(wrapper.findComponent(DuoWorkItemToMrAction).props()).toMatchObject({
          projectPath: 'group/project',
          workItemIid: '1',
          workItemType: 'Issue',
          workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
          additionalGoalContext: WORKPLAN_GOAL_PREFIX,
          generateMrButtonOptions: { ...GENERATE_MR_BUTTON_OPTIONS, size: 'small' },
        });
      });

      it('overrides the button size to small to match the header buttons', () => {
        expect(
          wrapper.findComponent(DuoWorkItemToMrAction).props('generateMrButtonOptions').size,
        ).toBe('small');
      });
    });

    describe('when there is no saved content', () => {
      beforeEach(() => {
        createComponent({ savedContent: '', hasRemoteFlowsEnabled: true });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });
    });

    describe('when remote flows are disabled', () => {
      beforeEach(() => {
        createComponent({ savedContent: 'Some plan content', hasRemoteFlowsEnabled: false });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });
    });

    describe('when in edit mode', () => {
      beforeEach(() => {
        createComponent({
          savedContent: 'Some plan content',
          hasRemoteFlowsEnabled: true,
          isEditing: true,
        });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });
    });
  });

  describe('more actions dropdown', () => {
    describe('with saved content', () => {
      let dropdownItems;

      beforeEach(() => {
        createComponent({ savedContent: 'Some plan', canUpdate: true });
        dropdownItems = findMoreActionsDropdown().props('items') || [];
      });

      it('exposes Delete workplan as an option', () => {
        expect(dropdownItems.map((i) => i.text)).toContain('Delete workplan');
      });

      it('exposes Regenerate workplan as an option', () => {
        expect(dropdownItems.map((i) => i.text)).toContain('Regenerate workplan');
      });

      describe('when the Regenerate item is activated', () => {
        beforeEach(() => {
          const regenerate = dropdownItems.find((i) => i.text === 'Regenerate workplan');
          regenerate.action();
        });

        it('emits "regenerate"', () => {
          expect(wrapper.emitted('regenerate')).toHaveLength(1);
        });
      });

      describe('when the Delete item is activated', () => {
        beforeEach(() => {
          const del = dropdownItems.find((i) => i.text === 'Delete workplan');
          del.action();
        });

        it('emits "delete"', () => {
          expect(wrapper.emitted('delete')).toHaveLength(1);
        });
      });
    });

    describe('without saved content', () => {
      beforeEach(() => {
        createComponent({ savedContent: '', canUpdate: true });
      });

      it('hides the dropdown so Regenerate is not exposed', () => {
        expect(findMoreActionsDropdown().exists()).toBe(false);
      });
    });

    describe('header actions while a run is replacing the plan', () => {
      beforeEach(() => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          canGenerateAsync: true,
          isFlowActive: true,
          hasRemoteFlowsEnabled: true,
        });
      });

      it('hides Edit, since the plan is about to be replaced', () => {
        expect(findEditButton().exists()).toBe(false);
      });

      it('hides Implement, so Duo cannot start from a plan on its way out', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });

      it('keeps More actions, whose items are disabled rather than hidden', () => {
        expect(findMoreActionsDropdown().exists()).toBe(true);
      });
    });

    describe('plan action availability while a run is active', () => {
      const findItem = (text) =>
        findMoreActionsDropdown()
          .props('items')
          .find((i) => i.text === text);
      const findRegenerateItem = () => findItem('Regenerate workplan');

      it('disables Delete too, so a run cannot silently undo it', () => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          canGenerateAsync: true,
          isFlowActive: true,
        });

        expect(findItem('Delete workplan').extraAttrs).toEqual({ disabled: true });
      });

      // The status lags the click, so the run is not active yet when the mutation fires.
      it.each(['Regenerate workplan', 'Delete workplan'])(
        'disables %s while the mutation is still in flight',
        (text) => {
          createComponent({
            savedContent: 'Some plan',
            canUpdate: true,
            canGenerateAsync: true,
            isFlowActive: false,
            isActionInFlight: true,
          });

          expect(findItem(text).extraAttrs).toEqual({ disabled: true });
        },
      );

      it.each`
        canGenerateAsync | isFlowActive | disabled | description
        ${true}          | ${true}      | ${true}  | ${'a run owns the workplan'}
        ${true}          | ${false}     | ${false} | ${'no run is in progress'}
        ${false}         | ${true}      | ${false} | ${'generation still goes through Duo Chat'}
      `(
        'is disabled=$disabled when $description',
        ({ canGenerateAsync, isFlowActive, disabled }) => {
          createComponent({
            savedContent: 'Some plan',
            canUpdate: true,
            canGenerateAsync,
            isFlowActive,
          });

          expect(findRegenerateItem().extraAttrs).toEqual({ disabled });
        },
      );
    });
  });

  describe('header buttons', () => {
    describe('when the user can update and is not editing', () => {
      beforeEach(() => {
        createComponent({ canUpdate: true });
      });

      it('shows the Edit button', () => {
        expect(findEditButton().exists()).toBe(true);
      });

      describe('when the Edit button is clicked', () => {
        beforeEach(() => {
          findEditButton().vm.$emit('click');
        });

        it('emits "start-edit"', () => {
          expect(wrapper.emitted('start-edit')).toHaveLength(1);
        });
      });

      describe('when the panel emits close', () => {
        beforeEach(async () => {
          await findDynamicPanel().vm.$emit('close');
        });

        it('emits "close"', () => {
          expect(wrapper.emitted('close')).toHaveLength(1);
        });
      });
    });

    describe('when the user cannot update', () => {
      beforeEach(() => {
        createComponent({ canUpdate: false });
      });

      it('hides the Edit button', () => {
        expect(findEditButton().exists()).toBe(false);
      });
    });

    describe('when editing', () => {
      beforeEach(() => {
        createComponent({ canUpdate: true, savedContent: 'plan', isEditing: true });
      });

      it('hides the Edit button', () => {
        expect(findEditButton().exists()).toBe(false);
      });
    });
  });

  describe('keyboard handling', () => {
    let addEventListenerSpy;
    let keydownHandler;

    beforeEach(() => {
      addEventListenerSpy = jest
        .spyOn(document, 'addEventListener')
        .mockImplementation((event, handler) => {
          if (event === 'keydown') keydownHandler = handler;
        });
    });

    afterEach(() => {
      addEventListenerSpy.mockRestore();
    });

    describe('when Escape is pressed while open', () => {
      beforeEach(() => {
        createComponent({ open: true });
        keydownHandler({ key: 'Escape' });
      });

      it('emits "close"', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when Escape is pressed while closed', () => {
      beforeEach(() => {
        createComponent({ open: false });
        keydownHandler({ key: 'Escape' });
      });

      it('does nothing', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('when a modal is open in the document', () => {
      beforeEach(() => {
        createComponent({ open: true });
        document.body.classList.add('modal-open');
        keydownHandler({ key: 'Escape' });
      });

      afterEach(() => {
        document.body.classList.remove('modal-open');
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });
});
