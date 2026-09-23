import { GlToggle } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import SecretsManagerDisableModal from 'ee/ci/secrets/components/secrets_manager_disable_modal.vue';
import SecretsManagerInstanceEnrollmentToggle from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/components/secrets_manager_instance_enrollment_toggle.vue';
import enrollInstanceSecretsManagerMutation from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/mutations/enroll_instance_secrets_manager.mutation.graphql';
import unenrollInstanceSecretsManagerMutation from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/mutations/unenroll_instance_secrets_manager.mutation.graphql';

Vue.use(VueApollo);
jest.mock('~/lib/logger');

describe('SecretsManagerInstanceEnrollmentToggle', () => {
  let wrapper;
  let mockEnrollMutation;
  let mockUnenrollMutation;
  const mockToastShow = jest.fn();

  const enrollMutationResponse = (errors = []) => ({
    data: { instanceSecretsManagerEnroll: { errors } },
  });
  const unenrollMutationResponse = (errors = []) => ({
    data: { instanceSecretsManagerUnenroll: { errors } },
  });

  const findToggle = () => wrapper.findComponent(GlToggle);
  const findDisableModal = () => wrapper.findComponent(SecretsManagerDisableModal);
  const findErrorAlert = () => wrapper.findComponentByTestId('enrollment-error-alert');

  const flipToggle = async (value) => {
    findToggle().vm.$emit('change', value);
    await waitForPromises();
  };

  const createComponent = ({ props = {}, secretsManagerPaidExperience = false } = {}) => {
    const apolloProvider = createMockApollo([
      [enrollInstanceSecretsManagerMutation, mockEnrollMutation],
      [unenrollInstanceSecretsManagerMutation, mockUnenrollMutation],
    ]);

    wrapper = shallowMountExtended(SecretsManagerInstanceEnrollmentToggle, {
      apolloProvider,
      propsData: {
        isEnrolled: false,
        ...props,
      },
      provide: {
        glFeatures: {
          secretsManagerPaidExperience,
        },
      },
      mocks: {
        $toast: { show: mockToastShow },
      },
    });
  };

  beforeEach(() => {
    mockEnrollMutation = jest.fn().mockResolvedValue(enrollMutationResponse());
    mockUnenrollMutation = jest.fn().mockResolvedValue(unenrollMutationResponse());
    mockToastShow.mockClear();
  });

  describe('rendering', () => {
    it('reflects the isEnrolled prop on the toggle', () => {
      createComponent({ props: { isEnrolled: true } });

      expect(findToggle().props('value')).toBe(true);
    });

    it('disables the toggle when the disabled prop is set', () => {
      createComponent({ props: { disabled: true } });

      expect(findToggle().props('disabled')).toBe(true);
    });

    it('sets the toggle to loading when the loading prop is set', () => {
      createComponent({ props: { loading: true } });

      expect(findToggle().props('isLoading')).toBe(true);
      expect(findToggle().props('disabled')).toBe(true);
    });

    it('does not render the error alert initially', () => {
      createComponent();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('toggling on', () => {
    beforeEach(() => {
      createComponent();
    });

    it('calls the enroll mutation and emits the new state', async () => {
      await flipToggle(true);

      expect(mockEnrollMutation).toHaveBeenCalledTimes(1);
      expect(mockUnenrollMutation).not.toHaveBeenCalled();
      expect(wrapper.emitted('toggled')).toEqual([[true]]);
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('disables the toggle while the mutation is in flight', async () => {
      expect(findToggle().props('disabled')).toBe(false);
      expect(findToggle().props('isLoading')).toBe(false);

      flipToggle(true);
      await nextTick();

      expect(findToggle().props('disabled')).toBe(true);
      expect(findToggle().props('isLoading')).toBe(true);
    });

    it('re-enables the toggle after the mutation resolves', async () => {
      await flipToggle(true);

      expect(findToggle().props('disabled')).toBe(false);
      expect(findToggle().props('isLoading')).toBe(false);
    });

    it('shows the enroll-specific success toast', async () => {
      await flipToggle(true);

      expect(mockToastShow).toHaveBeenCalledTimes(1);
      expect(mockToastShow).toHaveBeenCalledWith('Secrets Manager is enabled.');
    });

    it('renders an inline error when the mutation returns errors', async () => {
      mockEnrollMutation.mockResolvedValueOnce(enrollMutationResponse(['nope']));

      await flipToggle(true);

      expect(findErrorAlert().exists()).toBe(true);
      expect(wrapper.emitted('toggled')).toBeUndefined();
      expect(mockToastShow).not.toHaveBeenCalled();
    });

    it('renders an inline error when the mutation throws', async () => {
      mockEnrollMutation.mockRejectedValueOnce(new Error('boom'));

      await flipToggle(true);

      expect(findErrorAlert().exists()).toBe(true);
      expect(wrapper.emitted('toggled')).toBeUndefined();
      expect(mockToastShow).not.toHaveBeenCalled();
    });

    it('clears a previous error before the next mutation attempt', async () => {
      mockEnrollMutation.mockRejectedValueOnce(new Error('boom'));
      await flipToggle(true);
      expect(findErrorAlert().exists()).toBe(true);

      mockEnrollMutation.mockResolvedValueOnce(enrollMutationResponse());
      await flipToggle(true);

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('toggling off', () => {
    beforeEach(() => {
      createComponent({ props: { isEnrolled: true } });
    });

    it('calls the unenroll mutation and emits the new state', async () => {
      await flipToggle(false);

      expect(mockUnenrollMutation).toHaveBeenCalledTimes(1);
      expect(mockEnrollMutation).not.toHaveBeenCalled();
      expect(wrapper.emitted('toggled')).toEqual([[false]]);
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('does not show the disable confirmation modal', async () => {
      await flipToggle(false);

      expect(findDisableModal().props('visible')).toBe(false);
    });

    it('shows the unenroll-specific success toast', async () => {
      await flipToggle(false);

      expect(mockToastShow).toHaveBeenCalledTimes(1);
      expect(mockToastShow).toHaveBeenCalledWith('Secrets Manager is disabled.');
    });

    it('renders an inline error when the mutation returns errors', async () => {
      mockUnenrollMutation.mockResolvedValueOnce(unenrollMutationResponse(['nope']));

      await flipToggle(false);

      expect(findErrorAlert().exists()).toBe(true);
      expect(wrapper.emitted('toggled')).toBeUndefined();
    });
  });

  describe('dismissing the error alert', () => {
    beforeEach(async () => {
      mockEnrollMutation.mockRejectedValueOnce(new Error('boom'));
      createComponent();
      await flipToggle(true);
    });

    it('hides the alert when dismissed', async () => {
      expect(findErrorAlert().exists()).toBe(true);

      findErrorAlert().vm.$emit('dismiss');
      await nextTick();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('when secretsManagerPaidExperience feature flag is enabled', () => {
    describe('toggling off with the disable confirmation modal', () => {
      beforeEach(() => {
        createComponent({ props: { isEnrolled: true }, secretsManagerPaidExperience: true });
      });

      it('shows the disable confirmation modal instead of calling the mutation', async () => {
        expect(findDisableModal().props('visible')).toBe(false);

        await flipToggle(false);

        expect(findDisableModal().props('visible')).toBe(true);
        expect(mockUnenrollMutation).not.toHaveBeenCalled();
      });

      it('shows the trial note by default', () => {
        expect(findDisableModal().props('showTrialNote')).toBe(true);
      });

      it('hides the trial note when the showTrialNote prop is false', () => {
        createComponent({
          props: { isEnrolled: true, showTrialNote: false },
          secretsManagerPaidExperience: true,
        });

        expect(findDisableModal().props('showTrialNote')).toBe(false);
      });

      it('hides the modal without calling the mutation when the modal is dismissed', async () => {
        await flipToggle(false);

        findDisableModal().vm.$emit('hide');
        await nextTick();

        expect(findDisableModal().props('visible')).toBe(false);
        expect(mockUnenrollMutation).not.toHaveBeenCalled();
      });

      describe('when the modal confirms unenrollment', () => {
        beforeEach(async () => {
          await flipToggle(false);
        });

        it('sets the modal to loading while the mutation is in flight', async () => {
          findDisableModal().vm.$emit('unenroll');
          await nextTick();

          expect(findDisableModal().props('loading')).toBe(true);
        });

        it('calls the mutation and hides the modal on success', async () => {
          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(mockUnenrollMutation).toHaveBeenCalledTimes(1);
          expect(findDisableModal().props('visible')).toBe(false);
          expect(wrapper.emitted('toggled')).toEqual([[false]]);
          expect(mockToastShow).toHaveBeenCalledWith('Secrets Manager is disabled.');
        });

        it('keeps the modal open and shows the error in the modal when unenrollment fails', async () => {
          mockUnenrollMutation.mockResolvedValueOnce(unenrollMutationResponse(['nope']));

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(findDisableModal().props('visible')).toBe(true);
          expect(findDisableModal().props('errorMessage')).toBe(
            'Failed to update Secrets Manager enrollment.',
          );
          expect(findErrorAlert().exists()).toBe(false);
          expect(wrapper.emitted('toggled')).toBeUndefined();
        });

        it('clears the modal error on a successful retry', async () => {
          mockUnenrollMutation.mockResolvedValueOnce(
            unenrollMutationResponse(['Unenrollment error message from API']),
          );
          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(findDisableModal().props('errorMessage')).toBe('');
          expect(findDisableModal().props('visible')).toBe(false);
          expect(wrapper.emitted('toggled')).toEqual([[false]]);
        });

        it('clears the modal error when the modal is dismissed', async () => {
          mockUnenrollMutation.mockResolvedValueOnce(
            unenrollMutationResponse(['Unenrollment error message from API']),
          );
          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          findDisableModal().vm.$emit('hide');
          await nextTick();

          expect(findDisableModal().props('visible')).toBe(false);
          expect(findDisableModal().props('errorMessage')).toBe('');
          expect(findErrorAlert().exists()).toBe(false);
        });
      });
    });

    describe('toggling on', () => {
      it('does not show the disable confirmation modal', async () => {
        createComponent({ secretsManagerPaidExperience: true });

        await flipToggle(true);

        expect(findDisableModal().props('visible')).toBe(false);
        expect(mockEnrollMutation).toHaveBeenCalledTimes(1);
      });
    });
  });
});
