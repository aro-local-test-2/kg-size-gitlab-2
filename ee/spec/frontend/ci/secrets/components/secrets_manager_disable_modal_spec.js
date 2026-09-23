import { GlAlert, GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsManagerDisableModal from 'ee/ci/secrets/components/secrets_manager_disable_modal.vue';

describe('SecretsManagerDisableModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SecretsManagerDisableModal, {
      propsData: {
        visible: true,
        ...props,
      },
      stubs: { GlAlert, GlModal },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findErrorAlert = () => wrapper.findComponent(GlAlert);
  const findTrialNote = () => wrapper.findByTestId('disable-modal-trial-note');
  const findBillingNote = () => wrapper.findByTestId('disable-modal-billing-note');

  describe('template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is not dismissable outside of the action buttons', () => {
      expect(findModal().attributes()).toMatchObject({
        hideheaderclose: 'true',
        nocloseonbackdrop: 'true',
        nocloseonesc: 'true',
      });
    });

    it('renders the trial note by default', () => {
      expect(findTrialNote().text()).toBe(
        'If you have started a free 30-day trial, you can re-enable GitLab Secrets Manager at any time before the end of your trial period.',
      );
    });

    it('does not render an error alert by default', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('describes the namespace scope by default', () => {
      expect(findModal().text()).toContain(
        'This will disable GitLab Secrets Manager for all groups and projects in this namespace.',
      );
    });

    it('describes GitLab Credits in the billing note by default', () => {
      expect(findBillingNote().text()).toBe(
        'GitLab Secrets Manager will not use GitLab Credits when disabled.',
      );
    });
  });

  describe('when isOfflineLicense is true', () => {
    it('describes subscription billing in the billing note', () => {
      createComponent({ isOfflineLicense: true });

      expect(findBillingNote().text()).toBe(
        'GitLab Secrets Manager will no longer be billed when disabled.',
      );
    });
  });

  describe('when isInstance is true', () => {
    it('describes the instance scope', () => {
      createComponent({ isInstance: true });

      expect(findModal().text()).toContain(
        'This will disable GitLab Secrets Manager for all groups and projects in this instance.',
      );
    });
  });

  describe('when errorMessage is provided', () => {
    beforeEach(() => {
      createComponent({ errorMessage: 'Something went wrong.' });
    });

    it('renders a non-dismissible danger alert with the message', () => {
      expect(findErrorAlert().text()).toBe('Something went wrong.');
      expect(findErrorAlert().props()).toMatchObject({
        variant: 'danger',
        dismissible: false,
      });
    });
  });

  describe('when showTrialNote is false', () => {
    it('does not render the trial note', () => {
      createComponent({ showTrialNote: false });

      expect(findTrialNote().exists()).toBe(false);
    });
  });

  describe('when loading', () => {
    beforeEach(() => {
      createComponent({ loading: true });
    });

    it('sets the primary action to loading', () => {
      expect(findModal().props('actionPrimary').attributes.loading).toBe(true);
    });

    it('disables the cancel action', () => {
      expect(findModal().props('actionCancel').attributes.disabled).toBe(true);
    });
  });

  describe('events', () => {
    beforeEach(() => {
      createComponent();
    });

    it('emits `unenroll` when the confirming the modal', () => {
      findModal().vm.$emit('primary', { preventDefault: jest.fn() });

      expect(wrapper.emitted('unenroll')).toHaveLength(1);
    });

    it('emits `hide` when the modal is hidden', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });
});
