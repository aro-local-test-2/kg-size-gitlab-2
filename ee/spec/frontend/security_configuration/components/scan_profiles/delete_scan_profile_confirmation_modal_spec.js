import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DeleteScanProfileConfirmationModal from 'ee/security_configuration/components/scan_profiles/delete_scan_profile_confirmation_modal.vue';

describe('DeleteScanProfileConfirmationModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(DeleteScanProfileConfirmationModal, {
      propsData: {
        visible: true,
        profileName: 'Nightly secret detection',
        ...props,
      },
      stubs: {
        GlModal,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findProjectCountLine = () => wrapper.findByTestId('scan-profile-delete-project-count');

  it('renders the modal with the profile name in the title and small size', () => {
    createComponent();

    expect(findModal().props()).toMatchObject({
      visible: true,
      title: 'Delete Nightly secret detection',
      modalId: 'delete-scan-profile-confirmation-modal',
      size: 'sm',
    });
  });

  it('renders the confirmation message with the profile name in curly quotes', () => {
    createComponent();

    expect(wrapper.text()).toContain(
      'You are about to delete “Nightly secret detection”. Are you sure you want to proceed?',
    );
  });

  it('renders a Delete profile primary action with the danger variant', () => {
    createComponent();

    expect(findModal().props('actionPrimary')).toMatchObject({
      text: 'Delete profile',
      attributes: {
        variant: 'danger',
      },
    });
  });

  it('renders a Cancel action', () => {
    createComponent();

    expect(findModal().props('actionCancel')).toMatchObject({ text: 'Cancel' });
  });

  it.each([true, false])('passes visible %s through to the modal', (visible) => {
    createComponent({ visible });

    expect(findModal().props('visible')).toBe(visible);
  });

  it('emits confirm when the primary action is triggered', () => {
    createComponent();

    findModal().vm.$emit('primary');

    expect(wrapper.emitted('confirm')).toHaveLength(1);
  });

  it('emits cancel when the modal is hidden', () => {
    createComponent();

    findModal().vm.$emit('hidden');

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  describe('attached-projects warning', () => {
    it('is hidden when no projects use the profile', () => {
      createComponent({ projectCount: 0 });

      expect(findProjectCountLine().exists()).toBe(false);
    });

    it('is shown in singular form when one project uses the profile', () => {
      createComponent({ projectCount: 1 });

      expect(findProjectCountLine().text()).toBe(
        '1 project currently uses this profile and will be left without one.',
      );
    });

    it('is shown in plural form when more than one project uses the profile', () => {
      createComponent({ projectCount: 3 });

      expect(findProjectCountLine().text()).toBe(
        '3 projects currently use this profile and will be left without one.',
      );
    });
  });
});
