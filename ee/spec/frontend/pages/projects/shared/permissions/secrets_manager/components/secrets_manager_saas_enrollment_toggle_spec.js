import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlToggle } from '@gitlab/ui';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SaasEnrollmentToggle from 'ee/pages/projects/shared/permissions/secrets_manager/components/secrets_manager_saas_enrollment_toggle.vue';
import SecretsManagerDisableModal from 'ee/ci/secrets/components/secrets_manager_disable_modal.vue';
import enrollMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import unenrollMutation from 'ee/pages/projects/shared/permissions/secrets_manager/graphql/unenroll_namespace_secrets_manager.mutation.graphql';
import { enrollNamespaceResponse, unenrollNamespaceResponse } from '../mock_data';

const mockToastShow = jest.fn();
Vue.use(VueApollo);

describe('SecretsManagerPermissionsSettings', () => {
  let wrapper;
  let mockApollo;
  let mockEnrollment;
  let mockUnenrollment;

  const createComponent = async ({ props, secretsManagerPaidExperience = false } = {}) => {
    const handlers = [
      [enrollMutation, mockEnrollment],
      [unenrollMutation, mockUnenrollment],
    ];

    mockApollo = createMockApollo(handlers);

    wrapper = shallowMountExtended(SaasEnrollmentToggle, {
      apolloProvider: mockApollo,
      provide: {
        glFeatures: {
          secretsManagerPaidExperience,
        },
      },
      propsData: {
        canManageEnrollment: true,
        fullPath: '/path/to/group',
        hasEnrollmentQueryError: false,
        isEnrolled: false,
        disabled: false,
        ...props,
      },
      mocks: {
        $toast: { show: mockToastShow },
      },
    });

    await waitForPromises();
    await nextTick();
  };

  const findEnrollmentToggle = () => wrapper.findComponent(GlToggle);
  const findDisableModal = () => wrapper.findComponent(SecretsManagerDisableModal);
  const findErrorMessage = () => wrapper.findByTestId('gsm-enrollment-error');

  const flipToggle = async () => {
    findEnrollmentToggle().vm.$emit('change');
    await waitForPromises();
    await nextTick();
  };

  beforeEach(() => {
    mockEnrollment = jest.fn().mockResolvedValue(enrollNamespaceResponse());
    mockUnenrollment = jest.fn().mockResolvedValue(unenrollNamespaceResponse());
  });

  describe('template', () => {
    it('disables toggle when user has no permission to manage enrollment', async () => {
      await createComponent({ props: { canManageEnrollment: false } });

      expect(findEnrollmentToggle().props('disabled')).toBe(true);
    });

    const DESCRIPTION = 'Allow the secrets manager to be enabled';

    it('shows the label and description by default', async () => {
      await createComponent();

      expect(wrapper.find('label').exists()).toBe(true);
      expect(wrapper.text()).toContain(DESCRIPTION);
    });

    // In the settings block the block heading + description own the naming, so
    // the toggle drops its own label and description in both experiences.
    it.each([
      ['beta', false],
      ['paid', true],
    ])('drops the label and description in a settings block (%s experience)', async (_, paid) => {
      await createComponent({
        props: { hideInlineText: true },
        secretsManagerPaidExperience: paid,
      });

      expect(wrapper.find('label').exists()).toBe(false);
      expect(wrapper.text()).not.toContain(DESCRIPTION);
      expect(findEnrollmentToggle().exists()).toBe(true);
    });

    it('disables toggle when enrollment query fails', async () => {
      await createComponent({ props: { hasEnrollmentQueryError: true } });

      expect(findEnrollmentToggle().props('disabled')).toBe(true);
    });

    it('sets toggle value based on enrollment status', async () => {
      await createComponent({ props: { isEnrolled: true } });

      expect(findEnrollmentToggle().props('value')).toBe(true);
    });
  });

  describe('enrolling the namespace', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('disables the toggle while mutation is loading', async () => {
      expect(findEnrollmentToggle().props('disabled')).toBe(false);
      expect(findEnrollmentToggle().props('isLoading')).toBe(false);

      flipToggle();
      await nextTick();

      expect(findEnrollmentToggle().props('disabled')).toBe(true);
      expect(findEnrollmentToggle().props('isLoading')).toBe(true);
    });

    it('calls the mutation with the correct variables', () => {
      flipToggle();

      expect(mockEnrollment).toHaveBeenCalledWith({
        fullPath: '/path/to/group',
      });
    });

    describe('when enrollment succeeds', () => {
      beforeEach(async () => {
        await createComponent();
        await flipToggle();
      });

      it('emits toggled event', () => {
        expect(wrapper.emitted('toggled')).toHaveLength(1);
      });

      it('shows toast message', () => {
        expect(mockToastShow).toHaveBeenCalledWith(
          'GitLab Secrets Manager is enabled for this namespace.',
        );
      });

      it('resets toggle loading state', () => {
        expect(findEnrollmentToggle().props('isLoading')).toBe(false);
      });
    });

    describe('when enrollment fails', () => {
      beforeEach(async () => {
        mockEnrollment = jest
          .fn()
          .mockResolvedValue(
            enrollNamespaceResponse({ errors: ['Enrollment error message from API'] }),
          );

        await createComponent();
        await flipToggle();
      });

      it('shows error message', () => {
        expect(findErrorMessage().text()).toBe('Enrollment error message from API');
      });

      it('resets toggle loading state', () => {
        expect(findEnrollmentToggle().props('isLoading')).toBe(false);
      });
    });
  });

  describe('unenrolling the namespace', () => {
    beforeEach(async () => {
      await createComponent({ props: { isEnrolled: true } });
    });

    it('does not show the disable confirmation modal', async () => {
      await flipToggle();

      expect(findDisableModal().props('visible')).toBe(false);
    });

    it('disables the toggle and sets loading state while mutation is loading', async () => {
      expect(findEnrollmentToggle().props('disabled')).toBe(false);
      expect(findEnrollmentToggle().props('isLoading')).toBe(false);

      findEnrollmentToggle().vm.$emit('change');
      await nextTick();

      expect(findEnrollmentToggle().props('disabled')).toBe(true);
      expect(findEnrollmentToggle().props('isLoading')).toBe(true);
    });

    it('calls the mutation with the correct variables', () => {
      findEnrollmentToggle().vm.$emit('change');

      expect(mockUnenrollment).toHaveBeenCalledWith({
        fullPath: '/path/to/group',
      });
    });

    describe('when unenrollment succeeds', () => {
      beforeEach(async () => {
        await createComponent({ props: { isEnrolled: true } });
        await flipToggle();
      });

      it('emits toggled event', () => {
        expect(wrapper.emitted('toggled')).toHaveLength(1);
      });

      it('shows toast message', () => {
        expect(mockToastShow).toHaveBeenCalledWith(
          'GitLab Secrets Manager is disabled for this namespace.',
        );
      });

      it('resets toggle loading state', () => {
        expect(findEnrollmentToggle().props('isLoading')).toBe(false);
      });
    });

    describe('when unenrollment fails', () => {
      beforeEach(async () => {
        mockUnenrollment = jest
          .fn()
          .mockResolvedValue(
            unenrollNamespaceResponse({ errors: ['Unenrollment error message from API'] }),
          );

        await createComponent({ props: { isEnrolled: true } });
        await flipToggle();
      });

      it('shows error message', () => {
        expect(findErrorMessage().text()).toBe('Unenrollment error message from API');
      });

      it('resets toggle loading state', () => {
        expect(findEnrollmentToggle().props('isLoading')).toBe(false);
      });
    });
  });

  describe('when secretsManagerPaidExperience feature flag is disabled', () => {
    beforeEach(async () => {
      await createComponent({ secretsManagerPaidExperience: false });
    });

    it('ignores disabled prop', async () => {
      await createComponent({
        secretsManagerPaidExperience: false,
        props: { disabled: true },
      });

      expect(findEnrollmentToggle().props('disabled')).toBe(false);
    });
  });

  describe('when secretsManagerPaidExperience feature flag is enabled', () => {
    it('disables toggle based on disabled prop value', async () => {
      await createComponent({
        secretsManagerPaidExperience: true,
        props: { disabled: true },
      });

      expect(findEnrollmentToggle().props('disabled')).toBe(true);
    });

    describe('unenrolling the namespace with the disable confirmation modal', () => {
      beforeEach(async () => {
        await createComponent({
          secretsManagerPaidExperience: true,
          props: { isEnrolled: true },
        });
      });

      it('shows the disable confirmation modal instead of calling the mutation', async () => {
        expect(findDisableModal().props('visible')).toBe(false);

        await flipToggle();

        expect(findDisableModal().props('visible')).toBe(true);
        expect(mockUnenrollment).not.toHaveBeenCalled();
      });

      it('shows the trial note in the modal', () => {
        expect(findDisableModal().props('showTrialNote')).toBe(true);
      });

      it('hides the modal without calling the mutation when the modal is dismissed', async () => {
        await flipToggle();

        findDisableModal().vm.$emit('hide');
        await nextTick();

        expect(findDisableModal().props('visible')).toBe(false);
        expect(mockUnenrollment).not.toHaveBeenCalled();
      });

      describe('when the modal confirms unenrollment', () => {
        beforeEach(async () => {
          await flipToggle();
        });

        it('sets the modal to loading while the mutation is in flight', async () => {
          findDisableModal().vm.$emit('unenroll');
          await nextTick();

          expect(findDisableModal().props('loading')).toBe(true);
        });

        it('calls the mutation and hides the modal on success', async () => {
          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(mockUnenrollment).toHaveBeenCalledWith({
            fullPath: '/path/to/group',
          });
          expect(findDisableModal().props('visible')).toBe(false);
          expect(wrapper.emitted('toggled')).toHaveLength(1);
          expect(mockToastShow).toHaveBeenCalledWith(
            'GitLab Secrets Manager is disabled for this namespace.',
          );
        });

        it('keeps the modal open and shows the error in the modal when unenrollment fails', async () => {
          mockUnenrollment = jest
            .fn()
            .mockResolvedValue(
              unenrollNamespaceResponse({ errors: ['Unenrollment error message from API'] }),
            );
          await createComponent({
            secretsManagerPaidExperience: true,
            props: { isEnrolled: true },
          });
          await flipToggle();

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(findDisableModal().props('visible')).toBe(true);
          expect(findDisableModal().props('errorMessage')).toBe(
            'Unenrollment error message from API',
          );
          expect(findErrorMessage().exists()).toBe(false);
        });

        it('clears the modal error on a successful retry', async () => {
          mockUnenrollment = jest
            .fn()
            .mockResolvedValueOnce(
              unenrollNamespaceResponse({ errors: ['Unenrollment error message from API'] }),
            )
            .mockResolvedValueOnce(unenrollNamespaceResponse());
          await createComponent({
            secretsManagerPaidExperience: true,
            props: { isEnrolled: true },
          });
          await flipToggle();

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          expect(findDisableModal().props('errorMessage')).toBe('');
          expect(findDisableModal().props('visible')).toBe(false);
          expect(wrapper.emitted('toggled')).toHaveLength(1);
        });

        it('clears the modal error when the modal is dismissed', async () => {
          mockUnenrollment = jest
            .fn()
            .mockResolvedValue(
              unenrollNamespaceResponse({ errors: ['Unenrollment error message from API'] }),
            );
          await createComponent({
            secretsManagerPaidExperience: true,
            props: { isEnrolled: true },
          });
          await flipToggle();

          findDisableModal().vm.$emit('unenroll');
          await waitForPromises();

          findDisableModal().vm.$emit('hide');
          await nextTick();

          expect(findDisableModal().props('visible')).toBe(false);
          expect(findDisableModal().props('errorMessage')).toBe('');
          expect(findErrorMessage().exists()).toBe(false);
        });
      });
    });
  });
});
