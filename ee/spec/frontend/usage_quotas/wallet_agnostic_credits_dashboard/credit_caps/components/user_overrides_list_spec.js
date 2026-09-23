import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlKeysetPagination, GlLoadingIcon, GlTableLite } from '@gitlab/ui';
import UserOverridesList from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/user_overrides_list.vue';
import AddUserOverrideModal from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/add_user_override_modal.vue';
import getUserOverridesQuery from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/get_user_overrides.query.graphql';
import upsertUserOverridesMutation from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/upsert_user_overrides.mutation.graphql';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import {
  mockUserOverride,
  mockUserOverridesData,
  mockUserOverridesEmpty,
  mockUserOverridesNullBudgetCaps,
  mockUserOverridesWithNullUser,
  mockUserOverridesPage1of2,
  mockUserOverridesPage2of2,
  mockUpsertUserOverridesSuccess,
  mockUpsertUserOverridesErrors,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

describe('CreditCapsUserOverridesList', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type {jest.Mock} */
  let getUserOverridesHandler;
  /** @type {jest.Mock} */
  let upsertUserOverridesHandler;

  const createComponent = ({ provide = {}, mountFn = shallowMountExtended } = {}) => {
    const apolloProvider = createMockApollo([
      [getUserOverridesQuery, getUserOverridesHandler],
      [upsertUserOverridesMutation, upsertUserOverridesHandler],
    ]);

    wrapper = mountFn(UserOverridesList, {
      apolloProvider,
      provide: {
        namespacePath: null,
        ...provide,
      },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findErrorAlert = () => wrapper.findByTestId('user-credit-caps-overrides-error-alert');
  const findAddOverrideButton = () =>
    wrapper.findComponentByTestId('user-credit-caps-add-override-button');
  const findAddOverrideModal = () => wrapper.findComponent(AddUserOverrideModal);
  const findEmptyState = () => wrapper.findByTestId('user-credit-caps-overrides-empty-state');
  const findTable = () => wrapper.findComponent(GlTableLite);
  const findForms = () => wrapper.findAllByTestId('user-credit-caps-overrides-form');
  const findFirstForm = () => wrapper.findByTestId('user-credit-caps-overrides-form');
  const findSaveErrorAlert = () =>
    wrapper.findByTestId('user-credit-caps-overrides-save-error-alert');
  const findSaveButton = () =>
    wrapper.findComponentByTestId('user-credit-caps-overrides-save-button');
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);

  beforeEach(() => {
    getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesData);
    upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesSuccess);
  });

  describe('loading state', () => {
    beforeEach(() => {
      getUserOverridesHandler = jest.fn().mockReturnValue(new Promise(() => {}));
      createComponent();
    });

    it('shows loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });

    it('does not show error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('does not show table', () => {
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when data loads successfully', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('does not show loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('does not show error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('renders the overrides table', () => {
      expect(findTable().exists()).toBe(true);
    });

    it('passes overrides as items to the table', () => {
      expect(findTable().props('items')).toHaveLength(2);
    });

    it('passes the first override as the first item', () => {
      expect(findTable().props('items')[0]).toMatchObject({
        cap: mockUserOverride.cap,
        enabled: mockUserOverride.capEnabled,
        user: mockUserOverride.user,
      });
    });

    it('renders a form per override row', () => {
      expect(findForms()).toHaveLength(2);
    });

    it('does not show pagination when only one page', () => {
      expect(findPagination().exists()).toBe(false);
    });
  });

  describe('when some overrides have a null user', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesWithNullUser);
      createComponent();
      await waitForPromises();
    });

    it('filters out null-user overrides', () => {
      expect(findTable().props('items')).toHaveLength(1);
    });

    it('keeps overrides with a valid user', () => {
      expect(findTable().props('items')[0]).toMatchObject({
        cap: mockUserOverride.cap,
        enabled: mockUserOverride.capEnabled,
        user: mockUserOverride.user,
      });
    });
  });

  describe('when data is empty', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesEmpty);
      createComponent();
      await waitForPromises();
    });

    it('shows empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not show table', () => {
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when a subsequent query succeeds after a fetch failure', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();

      getUserOverridesHandler.mockResolvedValue(mockUserOverridesData);
      wrapper.vm.$apollo.queries.userOverrides.refetch();
      await waitForPromises();
    });

    it('clears the error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('renders the overrides table', () => {
      expect(findTable().exists()).toBe(true);
    });
  });

  describe('when budgetCaps is null', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesNullBudgetCaps);
      createComponent();
      await waitForPromises();
    });

    it('shows error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });

    it('logs the error', () => {
      expect(logError).toHaveBeenCalled();
    });

    it('captures the exception', () => {
      expect(captureException).toHaveBeenCalled();
    });
  });

  describe('when fetch fails', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();
    });

    it('shows error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });

    it('does not show table', () => {
      expect(findTable().exists()).toBe(false);
    });

    it('logs the error', () => {
      expect(logError).toHaveBeenCalled();
    });

    it('captures the exception', () => {
      expect(captureException).toHaveBeenCalled();
    });
  });

  describe('pagination', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesPage1of2);
      createComponent();
      await waitForPromises();
    });

    it('shows pagination when hasNextPage is true', () => {
      expect(findPagination().exists()).toBe(true);
    });

    describe('when next page is requested', () => {
      beforeEach(async () => {
        getUserOverridesHandler.mockResolvedValue(mockUserOverridesPage2of2);
        findPagination().vm.$emit('next', 'cursor-page-1');
        await waitForPromises();
      });

      it('fetches the next page', () => {
        expect(getUserOverridesHandler).toHaveBeenCalledWith(
          expect.objectContaining({ after: 'cursor-page-1', first: 20 }),
        );
      });

      it('resets saving state and errors on navigation', async () => {
        upsertUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent({ mountFn: mountExtended });
        await waitForPromises();

        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(true);

        getUserOverridesHandler.mockResolvedValue(mockUserOverridesPage2of2);
        findPagination().vm.$emit('next', 'cursor-page-1');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(false);
      });
    });

    describe('when previous page is requested', () => {
      beforeEach(async () => {
        getUserOverridesHandler.mockResolvedValue(mockUserOverridesPage1of2);
        findPagination().vm.$emit('prev', 'cursor-page-1');
        await waitForPromises();
      });

      it('fetches the previous page', () => {
        expect(getUserOverridesHandler).toHaveBeenCalledWith(
          expect.objectContaining({ before: 'cursor-page-1', last: 20 }),
        );
      });

      it('resets saving state and errors on navigation', async () => {
        upsertUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent({ mountFn: mountExtended });
        await waitForPromises();

        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(true);

        getUserOverridesHandler.mockResolvedValue(mockUserOverridesPage1of2);
        findPagination().vm.$emit('prev', 'cursor-page-1');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(false);
      });
    });
  });

  describe('saveOverride', () => {
    beforeEach(async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();
    });

    describe('when mutation succeeds', () => {
      it('calls the mutation with correct variables', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(upsertUserOverridesHandler).toHaveBeenCalledWith({
          namespacePath: null,
          overrides: [
            {
              userId: mockUserOverride.user.id,
              cap: mockUserOverride.cap,
              enabled: mockUserOverride.capEnabled,
            },
          ],
        });
      });

      it('shows a success toast', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(toast).toHaveBeenCalledTimes(1);
      });

      it('hides the save button loading state after resolving', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveButton().props('loading')).toBe(false);
      });

      it('clears a prior save error for the row when retrying', async () => {
        upsertUserOverridesHandler
          .mockRejectedValueOnce(new Error('err'))
          .mockResolvedValueOnce(mockUpsertUserOverridesSuccess);

        createComponent({ mountFn: mountExtended });
        await waitForPromises();

        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(true);

        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(false);
      });
    });

    describe('when mutation returns a payload error', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesErrors);
        createComponent({ mountFn: mountExtended });
        await waitForPromises();
      });

      it('shows the error in a row-details subrow', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(true);
      });

      it('logs the error', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(logError).toHaveBeenCalledWith(expect.any(Error));
      });

      it('does not show a toast', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(toast).not.toHaveBeenCalled();
      });
    });

    describe('when mutation fails with a network error', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent({ mountFn: mountExtended });
        await waitForPromises();
      });

      it('shows the error in a row-details subrow', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(findSaveErrorAlert().exists()).toBe(true);
      });

      it('captures the exception in Sentry', async () => {
        await findFirstForm().trigger('submit');
        await waitForPromises();

        expect(captureException).toHaveBeenCalledWith(expect.any(Error));
      });
    });
  });

  describe('add override modal', () => {
    beforeEach(async () => {
      getUserOverridesHandler = jest.fn().mockResolvedValue(mockUserOverridesData);
      createComponent();
      await waitForPromises();
    });

    it('renders the Add override button', () => {
      expect(findAddOverrideButton().exists()).toBe(true);
    });

    it('renders AddUserOverrideModal with visible=false initially', () => {
      expect(findAddOverrideModal().props('visible')).toBe(false);
    });

    it('opens the modal when Add override button is clicked', async () => {
      await findAddOverrideButton().vm.$emit('click');

      expect(findAddOverrideModal().props('visible')).toBe(true);
    });

    it('closes the modal when it emits hidden', async () => {
      await findAddOverrideButton().vm.$emit('click');
      findAddOverrideModal().vm.$emit('hidden');
      await Vue.nextTick();

      expect(findAddOverrideModal().props('visible')).toBe(false);
    });

    it('closes the modal when it emits saved', async () => {
      await findAddOverrideButton().vm.$emit('click');
      findAddOverrideModal().vm.$emit('saved');
      await Vue.nextTick();

      expect(findAddOverrideModal().props('visible')).toBe(false);
    });

    it('refetches overrides when modal emits saved', async () => {
      findAddOverrideModal().vm.$emit('saved');
      await waitForPromises();

      expect(getUserOverridesHandler).toHaveBeenCalledTimes(2);
    });
  });
});
