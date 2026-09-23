import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlModal, GlToggle } from '@gitlab/ui';
import AddUserOverrideModal from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/add_user_override_modal.vue';
import UserOverrideSelect from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/user_override_select.vue';
import upsertUserOverridesMutation from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/upsert_user_overrides.mutation.graphql';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import {
  mockUpsertUserOverridesSuccess,
  mockUpsertUserOverridesErrors,
  mockUpsertUserOverridesMultipleErrors,
  mockSearchUsers,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

describe('CreditCapsAddUserOverrideModal', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type {jest.Mock} */
  let upsertUserOverridesHandler;

  const createComponent = ({ provide = {}, props = {} } = {}) => {
    const apolloProvider = createMockApollo([
      [upsertUserOverridesMutation, upsertUserOverridesHandler],
    ]);

    wrapper = shallowMountExtended(AddUserOverrideModal, {
      apolloProvider,
      propsData: { visible: true, ...props },
      provide: { namespacePath: null, ...provide },
      stubs: {
        GlModal,
        GlFormInputGroup: true,
        UserOverrideSelect: true,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findUserSelect = () => wrapper.findComponent(UserOverrideSelect);
  const findCapInput = () => wrapper.findComponentByTestId('add-cap-override-cap-input');
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findErrorAlert = () => wrapper.findByTestId('add-cap-override-error-alert');
  const findForm = () => wrapper.find('form');

  const triggerSubmit = () => findForm().trigger('submit');
  const triggerHidden = () => findModal().vm.$emit('hidden');

  const selectUsers = (users = [mockSearchUsers[0]]) => {
    findUserSelect().vm.$emit('input', users);
  };

  beforeEach(() => {
    upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesSuccess);
  });

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the modal', () => {
      expect(findModal().exists()).toBe(true);
    });

    it('renders the user select component', () => {
      expect(findUserSelect().exists()).toBe(true);
    });

    it('user select has no users selected by default', () => {
      expect(findUserSelect().props('value')).toEqual([]);
    });

    it('defaults cap to 0', () => {
      expect(findCapInput().props('value')).toBe(0);
    });

    it('cap input has required attribute', () => {
      expect(findCapInput().attributes('required')).toBeDefined();
    });

    it('defaults enabled toggle to true', () => {
      expect(findToggle().props('value')).toBe(true);
    });

    it('does not show error alert initially', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('save button is disabled when no user is selected', () => {
      expect(findModal().props('actionPrimary').attributes.disabled).toBe(true);
    });

    it('save button is enabled when a user is selected', async () => {
      selectUsers();
      await nextTick();
      expect(findModal().props('actionPrimary').attributes.disabled).toBe(false);
    });
  });

  describe('when modal is dismissed without saving', () => {
    it('emits hidden', () => {
      createComponent();
      triggerHidden();
      expect(wrapper.emitted('hidden')).toHaveLength(1);
    });

    it('resets form state', async () => {
      createComponent();
      selectUsers();
      findCapInput().vm.$emit('input', 42);
      triggerHidden();
      await nextTick();
      expect(findUserSelect().props('value')).toEqual([]);
      expect(findCapInput().props('value')).toBe(0);
    });
  });

  describe('when modal is dismissed during saving', () => {
    beforeEach(async () => {
      upsertUserOverridesHandler = jest.fn(() => new Promise(() => {}));
      createComponent();
      selectUsers();
      triggerSubmit();
      await nextTick();
      triggerHidden();
      await nextTick();
    });

    it('emits hidden', () => {
      expect(wrapper.emitted('hidden')).toHaveLength(1);
    });

    it('preserves form state', () => {
      expect(findUserSelect().props('value')).toHaveLength(1);
    });

    it('shows a background saving toast', () => {
      expect(toast).toHaveBeenCalledWith('Saving in the background.');
    });
  });

  describe('submit', () => {
    describe('when no user is selected', () => {
      it('does not call the mutation', async () => {
        createComponent();
        triggerSubmit();
        await waitForPromises();
        expect(upsertUserOverridesHandler).not.toHaveBeenCalled();
      });
    });

    describe('when already saving', () => {
      it('does not call the mutation again', async () => {
        createComponent();
        selectUsers();
        triggerSubmit();
        triggerSubmit();
        await waitForPromises();
        expect(upsertUserOverridesHandler).toHaveBeenCalledTimes(1);
      });
    });

    describe('when mutation succeeds', () => {
      beforeEach(async () => {
        createComponent();
        selectUsers();
        triggerSubmit();
        await waitForPromises();
      });

      it('calls the mutation with the correct variables', () => {
        expect(upsertUserOverridesHandler).toHaveBeenCalledWith({
          namespacePath: null,
          overrides: [{ userId: mockSearchUsers[0].id, cap: 0, enabled: true }],
        });
      });

      it('calls the mutation with all selected users', async () => {
        createComponent();
        selectUsers(mockSearchUsers);
        triggerSubmit();
        await waitForPromises();
        expect(upsertUserOverridesHandler).toHaveBeenCalledWith({
          namespacePath: null,
          overrides: mockSearchUsers.map(({ id }) => ({ userId: id, cap: 0, enabled: true })),
        });
      });

      it('shows a success toast', () => {
        expect(toast).toHaveBeenCalledWith('Override saved.');
      });

      it('emits saved', () => {
        expect(wrapper.emitted('saved')).toHaveLength(1);
      });

      it('emits hidden to close the modal', () => {
        expect(wrapper.emitted('hidden')).toHaveLength(1);
      });

      it('resets form state', () => {
        expect(findUserSelect().props('value')).toEqual([]);
        expect(findCapInput().props('value')).toBe(0);
      });
    });

    describe('when mutation succeeds with namespacePath', () => {
      it('passes namespacePath to the mutation', async () => {
        createComponent({ provide: { namespacePath: 'my-group' } });
        selectUsers();
        triggerSubmit();
        await waitForPromises();

        expect(upsertUserOverridesHandler).toHaveBeenCalledWith(
          expect.objectContaining({ namespacePath: 'my-group' }),
        );
      });
    });

    describe('when mutation returns payload errors', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesErrors);
        createComponent();
        selectUsers();
        triggerSubmit();
        await waitForPromises();
      });

      it('shows the error alert', () => {
        expect(findErrorAlert().exists()).toBe(true);
      });

      it('shows the error message', () => {
        expect(findErrorAlert().text()).toBe('Something went wrong');
      });

      it('does not show a toast', () => {
        expect(toast).not.toHaveBeenCalled();
      });

      it('does not emit saved', () => {
        expect(wrapper.emitted('saved')).toBeUndefined();
      });

      it('logs the error', () => {
        expect(logError).toHaveBeenCalledWith(expect.any(Error));
      });

      it('captures the exception in Sentry', () => {
        expect(captureException).toHaveBeenCalledWith(expect.any(Error));
      });
    });

    describe('when mutation returns multiple payload errors', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest
          .fn()
          .mockResolvedValue(mockUpsertUserOverridesMultipleErrors);
        createComponent();
        selectUsers();
        triggerSubmit();
        await waitForPromises();
      });

      it('shows the error alert', () => {
        expect(findErrorAlert().exists()).toBe(true);
      });

      it('shows the aggregate error message', () => {
        expect(findErrorAlert().text()).toBe('An error occurred while saving user cap override.');
      });

      it('does not emit saved', () => {
        expect(wrapper.emitted('saved')).toBeUndefined();
      });
    });

    describe('when mutation fails with a network error', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent();
        selectUsers();
        triggerSubmit();
        await waitForPromises();
      });

      it('shows the error alert', () => {
        expect(findErrorAlert().exists()).toBe(true);
      });

      it('shows the error message', () => {
        expect(findErrorAlert().text()).toBe('Network error');
      });

      it('does not show a toast', () => {
        expect(toast).not.toHaveBeenCalled();
      });

      it('logs the error', () => {
        expect(logError).toHaveBeenCalledWith(expect.any(Error));
      });
    });
  });
});
