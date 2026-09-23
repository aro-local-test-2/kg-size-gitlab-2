import { nextTick } from 'vue';
import { GlAlert, GlFormGroup, GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { visitUrl } from '~/lib/utils/url_utility';
import ProjectRedirectModal from 'ee/ai/catalog/components/project_redirect_modal.vue';
import FormProjectDropdown from 'ee/ai/catalog/components/form_project_dropdown.vue';
import { mockAgent, mockFlow, mockProjects } from '../mock_data';

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));

describe('ProjectRedirectModal', () => {
  let wrapper;

  const mockProject = mockProjects[0];

  // `state` and `invalidFeedback` are inherited from BFormGroup, so the default stub drops them.
  const GlFormGroupStub = stubComponent(GlFormGroup, {
    props: ['state', 'invalidFeedback'],
  });

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(ProjectRedirectModal, {
      propsData: {
        item: mockAgent,
        open: true,
        ...props,
      },
      stubs: { GlFormGroup: GlFormGroupStub },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findProjectDropdown = () => wrapper.findComponent(FormProjectDropdown);
  const findErrorAlert = () => wrapper.findComponent(GlAlert);

  const selectProject = (project = mockProject) =>
    findProjectDropdown().vm.$emit('select', project);
  const emitError = (message = 'Failed to load projects') =>
    findProjectDropdown().vm.$emit('error', message);
  const clickContinue = () => findModal().vm.$emit('primary', { preventDefault: jest.fn() });

  describe('rendering', () => {
    it('renders the modal with the given modal id and actions', () => {
      createComponent({ props: { modalId: 'custom-modal-id' } });

      expect(findModal().props()).toMatchObject({
        modalId: 'custom-modal-id',
        title: 'Choose a project',
        actionPrimary: { text: 'Continue', attributes: { variant: 'confirm' } },
        actionCancel: { text: 'Cancel' },
      });
    });

    it('is closed unless the open prop is set', () => {
      createComponent({ props: { open: false } });

      expect(findModal().props('visible')).toBe(false);
    });

    it('is open when the open prop is set', () => {
      createComponent();

      expect(findModal().props('visible')).toBe(true);
    });

    it('renders the project dropdown, with no project selected', () => {
      createComponent();

      expect(findProjectDropdown().props()).toMatchObject({
        value: null,
        isValid: true,
      });
    });

    it('renders no error alert', () => {
      createComponent();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('when selecting a project', () => {
    beforeEach(async () => {
      createComponent();
      selectProject();
      await nextTick();
    });

    it('passes the selected project id back to the dropdown', () => {
      expect(findProjectDropdown().props('value')).toBe(mockProject.id);
    });
  });

  describe('when the project dropdown emits an error', () => {
    beforeEach(async () => {
      createComponent();
      emitError('Failed to load projects');
      await nextTick();
    });

    it('renders the error alert with the emitted message', () => {
      expect(findErrorAlert().props('variant')).toBe('danger');
      expect(findErrorAlert().text()).toBe('Failed to load projects');
    });

    it('hides the error alert once dismissed', async () => {
      findErrorAlert().vm.$emit('dismiss');
      await nextTick();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('when continuing without a project selected', () => {
    beforeEach(async () => {
      createComponent();
      clickContinue();
      await nextTick();
    });

    it('does not navigate', () => {
      expect(visitUrl).not.toHaveBeenCalled();
    });

    it('keeps the modal open', () => {
      expect(findModal().props('visible')).toBe(true);
    });

    it('marks the project field as invalid', () => {
      expect(findFormGroup().props()).toMatchObject({
        state: false,
        invalidFeedback: 'Project is required.',
      });
      expect(findProjectDropdown().props('isValid')).toBe(false);
    });
  });

  describe('when continuing with a project selected', () => {
    it.each`
      itemType   | item         | expectedUrl
      ${'agent'} | ${mockAgent} | ${'/group/project-1/-/automate/agents/1/duplicate'}
      ${'flow'}  | ${mockFlow}  | ${'/group/project-1/-/automate/flows/4/duplicate'}
    `(
      'navigates to the $itemType duplicate page in the selected project',
      ({ item, expectedUrl }) => {
        createComponent({ props: { item } });
        selectProject();
        clickContinue();

        expect(visitUrl).toHaveBeenCalledWith(expectedUrl);
      },
    );

    it('closes the modal', async () => {
      createComponent();
      selectProject();
      clickContinue();
      await nextTick();

      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('when the modal is hidden', () => {
    beforeEach(async () => {
      createComponent();
      selectProject();
      emitError();
      await nextTick();
      findModal().vm.$emit('hidden');
      await nextTick();
    });

    it('emits hide', () => {
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('clears the selected project', () => {
      expect(findProjectDropdown().props('value')).toBe(null);
    });

    it('clears the error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });
  });
});
