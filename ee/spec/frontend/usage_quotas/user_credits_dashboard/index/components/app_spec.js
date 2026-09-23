import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlSprintf } from '@gitlab/ui';
import UserCreditsDashboardApp from 'ee/usage_quotas/user_credits_dashboard/index/components/app.vue';
import TotalUsageCard from 'ee/usage_quotas/user_credits_dashboard/index/components/total_usage_card.vue';
import UsageStatisticsCards from 'ee/usage_quotas/user_credits_dashboard/index/components/usage_statistics_cards.vue';
import billingPeriodUsageQuery from 'ee/usage_quotas/user_credits_dashboard/index/graphql/get_billing_period_usage.query.graphql';
import userCreditsUsageQuery from 'ee/usage_quotas/user_credits_dashboard/index/graphql/get_user_credits_usage.query.graphql';
import CreditsConsumptionChart from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index/components/credits_consumption_chart.vue';
import ProductsDropdownFilter from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index/components/products_dropdown_filter.vue';
import {
  LAST_MONTH,
  THIS_MONTH,
  TODAY,
} from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/shared/components/constants';
import DateRangeFilter from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/shared/components/date_range_filter.vue';
import {
  buildBillingPeriodUsageResponse,
  buildCreditsUsageResponse,
  mockBillingPeriodUsage,
  mockCreditsUsage,
} from 'ee_jest/usage_quotas/user_credits_dashboard/mock_data';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { logError } from '~/lib/logger';
import { newDate } from '~/lib/utils/datetime/date_calculation_utility';
import { toISODateFormat } from '~/lib/utils/datetime/date_format_utility';
import { captureException } from '~/sentry/sentry_browser_wrapper';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('UserCreditsDashboardApp', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const namespacePath = 'my-group';
  const otherNamespacePath = 'my-other-group';
  const groups = [{ name: 'My group', path: namespacePath }];
  const multipleGroups = [...groups, { name: 'My other group', path: otherNamespacePath }];
  const pending = () => new Promise(() => {});

  let billingPeriodHandler;
  let creditsUsageHandler;

  const createComponent = ({ billingPeriod, creditsUsage, provide } = {}) => {
    billingPeriodHandler = jest.fn(
      billingPeriod ?? (() => Promise.resolve(buildBillingPeriodUsageResponse())),
    );
    creditsUsageHandler = jest.fn(
      creditsUsage ?? (() => Promise.resolve(buildCreditsUsageResponse())),
    );

    const apolloProvider = createMockApollo([
      [billingPeriodUsageQuery, billingPeriodHandler],
      [userCreditsUsageQuery, creditsUsageHandler],
    ]);

    wrapper = shallowMountExtended(UserCreditsDashboardApp, {
      apolloProvider,
      provide: { groups, ...provide },
      stubs: { GlSprintf },
    });
  };

  const findLoadingIndicator = () => wrapper.findByTestId('skeleton-loader');
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findDisabledAlert = () => wrapper.findByTestId('usage-billing-disabled-alert');
  const findBlockedAlert = () => wrapper.findByTestId('user-credits-dashboard');
  const findOutdatedClientAlert = () => wrapper.findByTestId('outdated-client-alert');
  const findDashboard = () => wrapper.findByTestId('user-credits-dashboard');
  const findTotalUsageCard = () => wrapper.findComponent(TotalUsageCard);
  const findCreditsConsumptionChart = () => wrapper.findComponent(CreditsConsumptionChart);
  const findDateRangeFilter = () => wrapper.findComponent(DateRangeFilter);
  const findProductsDropdownFilter = () => wrapper.findComponent(ProductsDropdownFilter);
  const findFilteredLoadingIndicator = () => wrapper.findByTestId('filtered-usage-skeleton-loader');
  const findFilteredErrorAlert = () => wrapper.findByTestId('filtered-usage-error-alert');
  const findUsageStatisticsCards = () => wrapper.findComponent(UsageStatisticsCards);
  const findGroupSelector = () => wrapper.findComponentByTestId('group-selector');
  const findGroupDescription = () => wrapper.findByTestId('group-description');

  describe('while the dashboard query is loading', () => {
    beforeEach(() => {
      createComponent({ billingPeriod: pending, creditsUsage: pending });
    });

    it('shows the loading indicator', () => {
      expect(findLoadingIndicator().exists()).toBe(true);
    });

    it('queries the current billing period with only the namespace path', () => {
      expect(billingPeriodHandler).toHaveBeenCalledTimes(1);
      expect(billingPeriodHandler).toHaveBeenCalledWith({ namespacePath });
    });

    it('queries the selected range with the namespace path and the default filters', () => {
      expect(creditsUsageHandler).toHaveBeenCalledTimes(1);
      expect(creditsUsageHandler).toHaveBeenCalledWith({
        namespacePath,
        startDate: THIS_MONTH.startDate,
        endDate: THIS_MONTH.endDate,
        flowTypes: [],
      });
    });

    it('does not render the dashboard, the total usage card, or the filters', () => {
      expect(findDashboard().exists()).toBe(false);
      expect(findTotalUsageCard().exists()).toBe(false);
      expect(findDateRangeFilter().exists()).toBe(false);
      expect(findProductsDropdownFilter().exists()).toBe(false);
    });
  });

  describe('while only the filter-scoped query is loading', () => {
    beforeEach(async () => {
      createComponent({ creditsUsage: pending });
      await waitForPromises();
    });

    it('renders the total usage card and the filters', () => {
      expect(findTotalUsageCard().props()).toMatchObject({
        creditsUsed: mockBillingPeriodUsage.creditsUsed,
        startDate: mockBillingPeriodUsage.startDate,
        endDate: mockBillingPeriodUsage.endDate,
      });
      expect(findDateRangeFilter().exists()).toBe(true);
      expect(findProductsDropdownFilter().exists()).toBe(true);
    });

    it('shows the filtered usage skeleton instead of the dashboard one', () => {
      expect(findFilteredLoadingIndicator().exists()).toBe(true);
      expect(findLoadingIndicator().exists()).toBe(false);
    });

    it('marks the products dropdown as loading', () => {
      expect(findProductsDropdownFilter().props('loading')).toBe(true);
    });
  });

  describe('when data loads successfully', () => {
    beforeEach(async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 25 })),
      });
      await waitForPromises();
    });

    it('renders the dashboard container', () => {
      expect(findDashboard().exists()).toBe(true);
    });

    it('renders the total usage card with the billing-period values', () => {
      expect(findTotalUsageCard().props()).toMatchObject({
        creditsUsed: mockBillingPeriodUsage.creditsUsed,
        startDate: mockBillingPeriodUsage.startDate,
        endDate: mockBillingPeriodUsage.endDate,
      });
    });

    it('renders the usage statistics cards with the range-scoped values and peak day', () => {
      expect(findUsageStatisticsCards().props()).toMatchObject({
        totalUsedCredits: 25,
        peakDayUsage: 3,
        peakDayDate: '2026-09-10',
      });
    });

    it('renders the credits consumption chart with the selected range and daily usage', () => {
      expect(findCreditsConsumptionChart().props()).toMatchObject({
        startDate: THIS_MONTH.startDate,
        endDate: THIS_MONTH.endDate,
        dailyUsage: mockCreditsUsage.dailyUsage,
        totalCredits: 25,
      });
    });

    it('does not show the loading, error, or disabled states', () => {
      expect(findLoadingIndicator().exists()).toBe(false);
      expect(findFilteredLoadingIndicator().exists()).toBe(false);
      expect(findErrorAlert().exists()).toBe(false);
      expect(findFilteredErrorAlert().exists()).toBe(false);
      expect(findDisabledAlert().exists()).toBe(false);
    });

    it('does not show the outdated client alert', () => {
      expect(findOutdatedClientAlert().exists()).toBe(false);
    });

    it('renders the date range and product filters', () => {
      expect(findDateRangeFilter().exists()).toBe(true);
      expect(findProductsDropdownFilter().exists()).toBe(true);
    });

    it('defaults the date range to the current month', () => {
      expect(findDateRangeFilter().props('value')).toEqual(THIS_MONTH);
    });

    // Jest pins the process to GMT (jest.config.base.js), so this locks the
    // derivation rather than reproducing the drift a local start-of-day causes
    // at negative UTC offsets.
    it('caps the custom range at the current UTC date', () => {
      expect(findDateRangeFilter().props('customDateRangeMaxDate')).toEqual(
        newDate(toISODateFormat(TODAY, true)),
      );
    });

    it('builds the products dropdown from the fetched products', () => {
      expect(findProductsDropdownFilter().props('products')).toEqual([
        {
          text: 'GitLab Duo Agent Platform',
          options: [
            { value: 'chat', text: 'Chat' },
            { value: 'code_suggestions', text: 'Code Suggestions' },
          ],
        },
      ]);
    });
  });

  describe('daily average', () => {
    const findDailyAverage = () => findUsageStatisticsCards().props('dailyAverage');

    const selectRange = async (range) => {
      findDateRangeFilter().vm.$emit('input', range);
      await waitForPromises();
    };

    const daysElapsedThisMonth = TODAY.getUTCDate();

    it('divides the range total by the elapsed days of a range ending in the future', async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 30 })),
      });
      await waitForPromises();

      expect(findDailyAverage()).toBe(30 / daysElapsedThisMonth);
    });

    it('divides the range total by every day of a fully elapsed range', async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 62 })),
      });
      await waitForPromises();
      await selectRange(LAST_MONTH);

      // LAST_MONTH spans a whole calendar month, so its end date is the length.
      const daysInLastMonth = newDate(LAST_MONTH.endDate).getDate();

      expect(findDailyAverage()).toBe(62 / daysInLastMonth);
    });

    it('is zero when no credits were used', async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 0 })),
      });
      await waitForPromises();

      expect(findDailyAverage()).toBe(0);
    });

    it('is zero when creditsUsed is null', async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: null })),
      });
      await waitForPromises();

      expect(findDailyAverage()).toBe(0);
    });

    it('is zero for a range that has not started yet', async () => {
      createComponent({
        creditsUsage: () => Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 10 })),
      });
      await waitForPromises();

      const nextYear = TODAY.getUTCFullYear() + 1;
      await selectRange({
        value: 'custom',
        startDate: `${nextYear}-01-01`,
        endDate: `${nextYear}-01-31`,
      });

      expect(findDailyAverage()).toBe(0);
    });
  });

  describe('when a filter changes', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      creditsUsageHandler.mockClear();
      billingPeriodHandler.mockClear();
    });

    it('refetches the filtered query when the date range changes', async () => {
      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();

      expect(creditsUsageHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          startDate: LAST_MONTH.startDate,
          endDate: LAST_MONTH.endDate,
        }),
      );
    });

    it('refetches the filtered query when the product filter changes', async () => {
      findProductsDropdownFilter().vm.$emit('select', ['chat']);
      await waitForPromises();

      expect(creditsUsageHandler).toHaveBeenCalledWith(
        expect.objectContaining({ flowTypes: ['chat'] }),
      );
    });

    it('does not refetch the billing-period query', async () => {
      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();

      expect(billingPeriodHandler).not.toHaveBeenCalled();
    });

    it('keeps the filters mounted and the total usage card intact while refetching', async () => {
      creditsUsageHandler.mockImplementation(pending);

      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();
      await nextTick();

      expect(findDateRangeFilter().exists()).toBe(true);
      expect(findProductsDropdownFilter().exists()).toBe(true);
      expect(findProductsDropdownFilter().props('loading')).toBe(true);
      expect(findTotalUsageCard().props()).toMatchObject({
        creditsUsed: mockBillingPeriodUsage.creditsUsed,
        startDate: mockBillingPeriodUsage.startDate,
        endDate: mockBillingPeriodUsage.endDate,
      });
      expect(findLoadingIndicator().exists()).toBe(false);
      expect(findFilteredLoadingIndicator().exists()).toBe(true);
    });
  });

  describe('group selection', () => {
    describe('with a single eligible group', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('does not render the selector', () => {
        expect(findGroupSelector().exists()).toBe(false);
      });

      it('names the group in the description', () => {
        expect(findGroupDescription().text()).toBe(
          'Track your GitLab Credits consumption for My group group.',
        );
      });
    });

    describe('with multiple eligible groups', () => {
      // Distinct per group, so the cards and the chart can be asserted to
      // follow the selection rather than just the refetch.
      const creditsUsedFor = (path) => (path === otherNamespacePath ? 7 : 25);

      beforeEach(async () => {
        createComponent({
          billingPeriod: ({ namespacePath: path }) =>
            Promise.resolve(buildBillingPeriodUsageResponse({ creditsUsed: creditsUsedFor(path) })),
          creditsUsage: ({ namespacePath: path }) =>
            Promise.resolve(buildCreditsUsageResponse({ creditsUsed: creditsUsedFor(path) })),
          provide: { groups: multipleGroups },
        });
        await waitForPromises();
        billingPeriodHandler.mockClear();
        creditsUsageHandler.mockClear();
      });

      it('renders the selector with all eligible groups and the default selection', () => {
        expect(findGroupSelector().props()).toMatchObject({
          items: [
            { value: namespacePath, text: 'My group' },
            { value: otherNamespacePath, text: 'My other group' },
          ],
          selected: namespacePath,
          toggleText: 'My group',
        });
      });

      describe('when another group is selected', () => {
        beforeEach(async () => {
          findGroupSelector().vm.$emit('select', otherNamespacePath);
          await waitForPromises();
        });

        it('refetches both queries for the newly selected group', () => {
          expect(billingPeriodHandler).toHaveBeenCalledTimes(1);
          expect(billingPeriodHandler).toHaveBeenCalledWith({
            namespacePath: otherNamespacePath,
          });

          expect(creditsUsageHandler).toHaveBeenCalledTimes(1);
          expect(creditsUsageHandler).toHaveBeenCalledWith(
            expect.objectContaining({ namespacePath: otherNamespacePath }),
          );
        });

        it('names the newly selected group in the description', () => {
          expect(findGroupDescription().text()).toBe(
            'Track your GitLab Credits consumption for My other group group.',
          );
        });

        it('updates the cards and the chart with the new group usage', () => {
          expect(findTotalUsageCard().props('creditsUsed')).toBe(7);
          expect(findUsageStatisticsCards().props('totalUsedCredits')).toBe(7);
          expect(findCreditsConsumptionChart().props('totalCredits')).toBe(7);
        });
      });
    });

    describe('when the selected group has no usage', () => {
      beforeEach(async () => {
        createComponent({
          billingPeriod: () => Promise.resolve(buildBillingPeriodUsageResponse({ creditsUsed: 0 })),
          creditsUsage: () =>
            Promise.resolve(buildCreditsUsageResponse({ creditsUsed: 0, dailyUsage: [] })),
        });
        await waitForPromises();
      });

      it('renders the dashboard with zeroed values instead of an error', () => {
        expect(findDashboard().exists()).toBe(true);
        expect(findErrorAlert().exists()).toBe(false);
        expect(findFilteredErrorAlert().exists()).toBe(false);
        expect(findTotalUsageCard().props('creditsUsed')).toBe(0);
        expect(findUsageStatisticsCards().props()).toMatchObject({
          totalUsedCredits: 0,
          dailyAverage: 0,
          peakDayUsage: 0,
        });
      });
    });

    describe('when the user is blocked', () => {
      it('renders the blocked alert', async () => {
        createComponent({
          creditsUsage: () =>
            Promise.resolve(
              buildCreditsUsageResponse({
                blockedStatus: {
                  blocked: true,
                  capType: 'FLAT_USER_CAP',
                },
              }),
            ),
        });
        await waitForPromises();

        expect(findDashboard().exists()).toBe(true);
        expect(findBlockedAlert().exists()).toBe(true);
      });
    });
  });

  describe('when the filter-scoped query errors', () => {
    beforeEach(async () => {
      createComponent({ creditsUsage: () => Promise.reject(new Error('failure')) });
      await waitForPromises();
    });

    it('shows the filtered usage error alert', () => {
      expect(findFilteredErrorAlert().exists()).toBe(true);
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('keeps the total usage card and the filters visible', () => {
      expect(findDashboard().exists()).toBe(true);
      expect(findTotalUsageCard().exists()).toBe(true);
      expect(findDateRangeFilter().exists()).toBe(true);
      expect(findProductsDropdownFilter().exists()).toBe(true);
    });

    it('logs the error and reports it to Sentry', () => {
      expect(logError).toHaveBeenCalled();
      expect(captureException).toHaveBeenCalled();
    });

    it('clears the error once a filter change resolves', async () => {
      createComponent({
        creditsUsage: jest
          .fn()
          .mockRejectedValueOnce(new Error('failure'))
          .mockImplementation(() => Promise.resolve(buildCreditsUsageResponse())),
      });
      await waitForPromises();
      expect(findFilteredErrorAlert().exists()).toBe(true);

      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();

      expect(findFilteredErrorAlert().exists()).toBe(false);
    });
  });

  describe('when the dashboard query errors', () => {
    beforeEach(async () => {
      createComponent({ billingPeriod: () => Promise.reject(new Error('failure')) });
      await waitForPromises();
    });

    it('shows the error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });

    it('does not render the dashboard, the total usage card, or the filters', () => {
      expect(findDashboard().exists()).toBe(false);
      expect(findTotalUsageCard().exists()).toBe(false);
      expect(findDateRangeFilter().exists()).toBe(false);
      expect(findProductsDropdownFilter().exists()).toBe(false);
    });

    it('logs the error and reports it to Sentry', () => {
      expect(logError).toHaveBeenCalled();
      expect(captureException).toHaveBeenCalled();
    });

    it('clears the error once the query is refetched successfully', async () => {
      createComponent({
        billingPeriod: jest
          .fn()
          .mockRejectedValueOnce(new Error('failure'))
          .mockImplementation(() => Promise.resolve(buildBillingPeriodUsageResponse())),
      });
      await waitForPromises();
      expect(findErrorAlert().exists()).toBe(true);

      wrapper.vm.$apollo.queries.billingPeriodUsage.refetch();
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(false);
      expect(findDashboard().exists()).toBe(true);
    });
  });

  // `enabled` and `isOutdatedClient` describe the dashboard itself, so they are
  // read from the unfiltered query only. A filter selection must not be able to
  // toggle either alert.
  describe('when usage billing is disabled', () => {
    describe('according to the dashboard query', () => {
      beforeEach(async () => {
        createComponent({
          billingPeriod: () => Promise.resolve(buildBillingPeriodUsageResponse({ enabled: false })),
        });
        await waitForPromises();
      });

      it('shows the disabled alert', () => {
        expect(findDisabledAlert().exists()).toBe(true);
      });

      it('does not render the dashboard, the total usage card, or the filters', () => {
        expect(findDashboard().exists()).toBe(false);
        expect(findTotalUsageCard().exists()).toBe(false);
        expect(findDateRangeFilter().exists()).toBe(false);
        expect(findProductsDropdownFilter().exists()).toBe(false);
      });
    });
  });

  describe('when the client is outdated', () => {
    it('renders the outdated client alert when the dashboard query says so', async () => {
      createComponent({
        billingPeriod: () =>
          Promise.resolve(buildBillingPeriodUsageResponse({ isOutdatedClient: true })),
      });
      await waitForPromises();

      expect(findDashboard().exists()).toBe(true);
      expect(findOutdatedClientAlert().exists()).toBe(true);
    });
  });

  // The filter-scoped query does not select the dashboard-level fields, so a
  // filter change must not disturb either alert.
  describe('dashboard alerts across a filter change', () => {
    it('keeps the outdated client alert visible', async () => {
      createComponent({
        billingPeriod: () =>
          Promise.resolve(buildBillingPeriodUsageResponse({ isOutdatedClient: true })),
      });
      await waitForPromises();
      expect(findOutdatedClientAlert().exists()).toBe(true);

      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();

      expect(findOutdatedClientAlert().exists()).toBe(true);
    });

    it('does not raise the disabled alert', async () => {
      createComponent();
      await waitForPromises();

      findDateRangeFilter().vm.$emit('input', LAST_MONTH);
      await waitForPromises();

      expect(findDisabledAlert().exists()).toBe(false);
      expect(findDashboard().exists()).toBe(true);
    });
  });
});
