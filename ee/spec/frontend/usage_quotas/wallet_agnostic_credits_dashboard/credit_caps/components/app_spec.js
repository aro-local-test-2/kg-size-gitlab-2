import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlLoadingIcon } from '@gitlab/ui';
import CreditCapsDashboardApp from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/app.vue';
import FlatUserCapControl from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/flat_user_cap_control.vue';
import UserOverridesList from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/user_overrides_list.vue';
import getCreditCapsQuery from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/get_credit_caps.query.graphql';
import upsertFlatUserCapMutation from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/upsert_flat_user_cap.mutation.graphql';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import {
  mockCreditCapsData,
  mockCreditCapsDataDisabled,
  mockCreditCapsBudgetCapsNull,
  mockCreditCapsDataZeroCap,
  mockCreditCapsNullCap,
  mockUpsertFlatUserCapSuccess,
  mockUpsertFlatUserCapErrors,
  mockUpsertFlatUserCapMultipleErrors,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

describe('CreditCapsDashboardApp', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type {jest.Mock} */
  let getCreditCapsHandler;
  /** @type {jest.Mock} */
  let upsertFlatUserCapHandler;

  const createComponent = ({ provide = {} } = {}) => {
    const apolloProvider = createMockApollo([
      [getCreditCapsQuery, getCreditCapsHandler],
      [upsertFlatUserCapMutation, upsertFlatUserCapHandler],
    ]);

    wrapper = shallowMountExtended(CreditCapsDashboardApp, {
      apolloProvider,
      provide: {
        namespacePath: null,
        ...provide,
      },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findFlatCapSaveErrorAlert = () => wrapper.findByTestId('flat-cap-save-error-alert');
  const findFlatUserCapControl = () => wrapper.findComponent(FlatUserCapControl);
  const findUserOverridesList = () => wrapper.findComponent(UserOverridesList);
  const findOverridesUnavailableAlert = () => wrapper.findByTestId('overrides-unavailable-alert');

  const triggerSave = (payload = { flatUserCap: 300, flatUserCapEnabled: false }) =>
    findFlatUserCapControl().vm.$emit('save', payload);

  beforeEach(() => {
    getCreditCapsHandler = jest.fn().mockResolvedValue(mockCreditCapsData);
    upsertFlatUserCapHandler = jest.fn().mockResolvedValue(mockUpsertFlatUserCapSuccess);
  });

  describe('loading state', () => {
    beforeEach(() => {
      getCreditCapsHandler = jest.fn().mockReturnValue(new Promise(() => {}));
      createComponent();
    });

    it('shows loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });

    it('does not show error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('does not show flat user cap control', () => {
      expect(findFlatUserCapControl().exists()).toBe(false);
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

    it('renders the heading', () => {
      expect(wrapper.findByTestId('credit-caps-heading').text()).toBe('Credit caps');
    });

    it('renders flat user cap control', () => {
      expect(findFlatUserCapControl().exists()).toBe(true);
    });

    it('renders user overrides list', () => {
      expect(findUserOverridesList().exists()).toBe(true);
    });

    it('passes correct props to flat user cap control', () => {
      expect(findFlatUserCapControl().props()).toMatchObject({
        flatUserCap: 500,
        flatUserCapEnabled: true,
      });
    });

    it('passes isSaving as false to flat user cap control', () => {
      expect(findFlatUserCapControl().props('isSaving')).toBe(false);
    });

    it('calls the query once', () => {
      expect(getCreditCapsHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('when namespacePath is provided', () => {
    beforeEach(async () => {
      createComponent({ provide: { namespacePath: 'my-group' } });
      await waitForPromises();
    });

    it('passes namespacePath to the query', () => {
      expect(getCreditCapsHandler).toHaveBeenCalledWith({ namespacePath: 'my-group' });
    });
  });

  describe('error state', () => {
    beforeEach(async () => {
      getCreditCapsHandler = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();
    });

    it('does not show loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('shows error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });

    it('renders error alert as non-dismissible with danger variant', () => {
      expect(findErrorAlert().attributes()).toMatchObject({ variant: 'danger' });
      expect(findErrorAlert().attributes('dismissible')).toBeUndefined();
    });

    it('does not show flat user cap control', () => {
      expect(findFlatUserCapControl().exists()).toBe(false);
    });

    it('logs the error', () => {
      expect(logError).toHaveBeenCalledWith(expect.any(Error));
    });

    it('captures the exception in Sentry', () => {
      expect(captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  describe('when flatUserCap is 0 and cap is enabled', () => {
    beforeEach(async () => {
      getCreditCapsHandler = jest.fn().mockResolvedValue(mockCreditCapsDataZeroCap);
      createComponent();
      await waitForPromises();
    });

    it('does not show error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('passes zero cap to flat user cap control', () => {
      expect(findFlatUserCapControl().props()).toMatchObject({
        flatUserCap: 0,
        flatUserCapEnabled: true,
      });
    });
  });

  describe('when cap is disabled', () => {
    beforeEach(async () => {
      getCreditCapsHandler = jest.fn().mockResolvedValue(mockCreditCapsDataDisabled);
      createComponent();
      await waitForPromises();
    });

    it('renders user overrides list', () => {
      expect(findUserOverridesList().exists()).toBe(true);
    });
  });

  describe('when flatUserCapEnabled is null', () => {
    beforeEach(async () => {
      getCreditCapsHandler = jest.fn().mockResolvedValue(mockCreditCapsNullCap);
      createComponent();
      await waitForPromises();
    });

    it('does not show error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('does not render user overrides list', () => {
      expect(findUserOverridesList().exists()).toBe(false);
    });

    it('renders flat user cap control', () => {
      expect(findFlatUserCapControl().exists()).toBe(true);
    });

    it('shows overrides unavailable alert', () => {
      expect(findOverridesUnavailableAlert().exists()).toBe(true);
    });

    it('renders overrides unavailable alert as non-dismissible tip', () => {
      expect(findOverridesUnavailableAlert().attributes()).toMatchObject({ variant: 'info' });
      expect(findOverridesUnavailableAlert().attributes('dismissible')).toBeUndefined();
    });
  });

  describe('when flatUserCapEnabled is not null', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('does not show overrides unavailable alert', () => {
      expect(findOverridesUnavailableAlert().exists()).toBe(false);
    });
  });

  describe('when budgetCaps returns null (read_subscription_usage denied on type)', () => {
    beforeEach(async () => {
      getCreditCapsHandler = jest.fn().mockResolvedValue(mockCreditCapsBudgetCapsNull);
      createComponent();
      await waitForPromises();
    });

    it('shows error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });

    it('does not show flat user cap control', () => {
      expect(findFlatUserCapControl().exists()).toBe(false);
    });

    it('logs the error', () => {
      expect(logError).toHaveBeenCalledWith(expect.any(Error));
    });

    it('captures the exception in Sentry', () => {
      expect(captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  describe('onSaveFlatCap', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    describe('while mutation is in flight', () => {
      it('passes isSaving as true to flat user cap control after triggering save', async () => {
        upsertFlatUserCapHandler = jest.fn().mockReturnValue(new Promise(() => {}));
        createComponent();
        await waitForPromises();

        triggerSave();
        await Vue.nextTick();

        expect(findFlatUserCapControl().props('isSaving')).toBe(true);
      });
    });

    describe('when mutation succeeds', () => {
      it('calls the mutation with correct variables', async () => {
        triggerSave({ flatUserCap: 300, flatUserCapEnabled: false });
        await waitForPromises();

        expect(upsertFlatUserCapHandler).toHaveBeenCalledWith({
          input: { namespacePath: null, flatUserCap: 300, flatUserCapEnabled: false },
        });
      });

      it('patches creditCaps with returned values', async () => {
        triggerSave({ flatUserCap: 300, flatUserCapEnabled: false });
        await waitForPromises();

        expect(findFlatUserCapControl().props()).toMatchObject({
          flatUserCap: 300,
          flatUserCapEnabled: false,
        });
      });

      it('does not show the save error alert', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatCapSaveErrorAlert().exists()).toBe(false);
      });

      it('shows a toast on success', async () => {
        triggerSave();
        await waitForPromises();

        expect(toast).toHaveBeenCalledTimes(1);
      });

      it('sets isSaving back to false after resolving', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatUserCapControl().props('isSaving')).toBe(false);
      });
    });

    describe('when mutation returns a single payload error', () => {
      beforeEach(async () => {
        upsertFlatUserCapHandler = jest.fn().mockResolvedValue(mockUpsertFlatUserCapErrors);
        createComponent();
        await waitForPromises();
      });

      it('shows the save error alert', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatCapSaveErrorAlert().exists()).toBe(true);
      });

      it('logs a plain Error', async () => {
        triggerSave();
        await waitForPromises();

        const [[error]] = logError.mock.calls;
        expect(error).toBeInstanceOf(Error);
        expect(error.message).toBe('Something went wrong');
      });

      it('captures a plain Error in Sentry', async () => {
        triggerSave();
        await waitForPromises();

        const [[error]] = captureException.mock.calls;
        expect(error).toBeInstanceOf(Error);
        expect(error.message).toBe('Something went wrong');
      });

      it('does not update the cap props', async () => {
        triggerSave({ flatUserCap: 300, flatUserCapEnabled: false });
        await waitForPromises();

        expect(findFlatUserCapControl().props()).toMatchObject({
          flatUserCap: 500,
          flatUserCapEnabled: true,
        });
      });
    });

    describe('when mutation returns multiple payload errors', () => {
      beforeEach(async () => {
        upsertFlatUserCapHandler = jest.fn().mockResolvedValue(mockUpsertFlatUserCapMultipleErrors);
        createComponent();
        await waitForPromises();
      });

      it('shows the save error alert', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatCapSaveErrorAlert().exists()).toBe(true);
      });

      it('logs an AggregateError with individual sub-errors', async () => {
        triggerSave();
        await waitForPromises();

        const [[error]] = logError.mock.calls;
        expect(error).toBeInstanceOf(AggregateError);
        expect(error.errors).toHaveLength(2);
        expect(error.errors[0].message).toBe('First error');
        expect(error.errors[1].message).toBe('Second error');
      });

      it('captures an AggregateError in Sentry', async () => {
        triggerSave();
        await waitForPromises();

        const [[error]] = captureException.mock.calls;
        expect(error).toBeInstanceOf(AggregateError);
      });
    });

    describe('when mutation fails with a network error', () => {
      beforeEach(async () => {
        upsertFlatUserCapHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent();
        await waitForPromises();
      });

      it('shows the save error alert', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatCapSaveErrorAlert().exists()).toBe(true);
      });

      it('sets isSaving back to false after error', async () => {
        triggerSave();
        await waitForPromises();

        expect(findFlatUserCapControl().props('isSaving')).toBe(false);
      });

      it('logs the error', async () => {
        triggerSave();
        await waitForPromises();

        expect(logError).toHaveBeenCalledWith(expect.any(Error));
      });

      it('captures the exception in Sentry', async () => {
        triggerSave();
        await waitForPromises();

        expect(captureException).toHaveBeenCalledWith(expect.any(Error));
      });
    });
  });
});
