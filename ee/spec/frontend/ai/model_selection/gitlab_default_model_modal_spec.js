import { GlFormCheckbox, GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import { RENDER_ALL_SLOTS_TEMPLATE, stubComponent } from 'helpers/stub_component';
import {
  GITLAB_DEFAULT_MODEL,
  SUPPRESS_DEFAULT_MODEL_MODAL_KEY,
} from 'ee/ai/model_selection/constants';
import GitlabDefaultModelModal from 'ee/ai/model_selection/gitlab_default_model_modal.vue';

describe('GitlabDefaultModelModal', () => {
  useLocalStorageSpy();

  let wrapper;
  const mockHideModal = jest.fn();

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GitlabDefaultModelModal, {
      propsData: {
        ...props,
      },
      stubs: {
        GlModal: stubComponent(GlModal, {
          template: RENDER_ALL_SLOTS_TEMPLATE,
          methods: {
            hide: mockHideModal,
          },
        }),
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findModalGlSprintf = () => wrapper.findComponent(GlSprintf);
  const findCancelButton = () => wrapper.findByTestId('cancel-button');
  const findConfirmButton = () => wrapper.findComponentByTestId('confirm-button');
  const findModalDismissCheckbox = () => wrapper.findComponent(GlFormCheckbox);

  beforeEach(() => {
    createComponent();
  });

  it('renders the component', () => {
    expect(findModal().exists()).toBe(true);
  });

  it('renders the correct title and description', () => {
    expect(findModal().props('title')).toMatch('GitLab default model');
    expect(findModalGlSprintf().attributes('message')).toMatch(
      'When you select the GitLab default model, GitLab uses the current default model for this feature. This model is updated automatically.',
    );
    expect(findModal().text()).toMatch('Alternatively, you can select a specific model to use.');
  });

  describe('when `isAutoOption` is true', () => {
    beforeEach(() => {
      createComponent({ isAutoOption: true });
    });

    it('renders the Auto title and description', () => {
      expect(findModal().props('title')).toMatch('GitLab automatic routing');
      expect(findModalGlSprintf().attributes('message')).toMatch(
        'When you select %{boldStart}Auto%{boldEnd}, GitLab routes each request to the most suitable model based on the task at hand.',
      );
      expect(findModal().text()).toMatch('Alternatively, you can select a specific model to use.');
    });
  });

  it('has a confirm button', () => {
    expect(findConfirmButton().exists()).toBe(true);
  });

  it('has a cancel button', () => {
    expect(findCancelButton().exists()).toBe(true);
  });

  it('has a modal dismiss checkbox', () => {
    expect(findModalDismissCheckbox().exists()).toBe(true);
  });

  describe('onSubmit', () => {
    describe('when the "do not show again" checkbox is not checked', () => {
      beforeEach(() => {
        findConfirmButton().vm.$emit('click');
      });

      it('does not set set item in localStorage', () => {
        expect(localStorage.setItem).not.toHaveBeenCalled();
      });

      it('emits `confirm-submit` event', () => {
        expect(wrapper.emitted('confirm-submit')).toStrictEqual([[GITLAB_DEFAULT_MODEL]]);
      });

      it('closes the modal', () => {
        expect(mockHideModal).toHaveBeenCalled();
      });
    });

    describe('when the "do not show again" checkbox is checked', () => {
      beforeEach(() => {
        findModalDismissCheckbox().vm.$emit('input', true);
        findConfirmButton().vm.$emit('click');
      });

      it('sets item in localStorage', () => {
        expect(localStorage.setItem).toHaveBeenCalledWith(SUPPRESS_DEFAULT_MODEL_MODAL_KEY, 'true');
      });

      it('emits `confirm-submit` event', () => {
        expect(wrapper.emitted('confirm-submit')).toStrictEqual([[GITLAB_DEFAULT_MODEL]]);
      });

      it('closes the modal', () => {
        expect(mockHideModal).toHaveBeenCalled();
      });
    });
  });
});
