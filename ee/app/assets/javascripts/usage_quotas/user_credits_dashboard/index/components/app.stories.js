import VueApollo from 'vue-apollo';
import {
  MOCK_GROUPS,
  buildBillingPeriodUsageResponse,
  buildCreditsUsageResponse,
  usageForGroup,
} from 'ee_jest/usage_quotas/user_credits_dashboard/mock_data';
import { createMockClient } from 'helpers/mock_apollo_helper';
import billingPeriodUsageQuery from '../graphql/get_billing_period_usage.query.graphql';
import userCreditsUsageQuery from '../graphql/get_user_credits_usage.query.graphql';
import UserCreditsDashboardApp from './app.vue';

const meta = {
  title: 'ee/usage_quotas/user_credits_dashboard/app',
  component: UserCreditsDashboardApp,
};

export default meta;

const pending = () => new Promise(() => {});

// Both handlers key off the requested group, so switching groups changes the data.
const billingPeriodFor =
  (overrides = {}) =>
  ({ namespacePath }) =>
    Promise.resolve(
      buildBillingPeriodUsageResponse({
        creditsUsed: usageForGroup(namespacePath).creditsUsed,
        ...overrides,
      }),
    );

const creditsUsageFor =
  (overrides = {}) =>
  ({ namespacePath }) =>
    Promise.resolve(buildCreditsUsageResponse({ ...usageForGroup(namespacePath), ...overrides }));

const createTemplate = (config = {}) => {
  const { billingPeriodHandler = billingPeriodFor(), creditsUsageHandler = creditsUsageFor() } =
    config;

  const defaultClient = createMockClient([
    [billingPeriodUsageQuery, billingPeriodHandler],
    [userCreditsUsageQuery, creditsUsageHandler],
  ]);
  const apolloProvider = new VueApollo({ defaultClient });

  return (args, { argTypes }) => ({
    apolloProvider,
    components: { UserCreditsDashboardApp },
    provide: {
      groups: MOCK_GROUPS,
      ...config.provide,
    },
    props: Object.keys(argTypes),
    template: `<user-credits-dashboard-app />`,
  });
};

export const Default = {
  render: createTemplate(),
};

// Only one eligible group, so no selector is rendered.
export const SingleGroup = {
  render: (...args) => createTemplate({ provide: { groups: MOCK_GROUPS.slice(0, 1) } })(...args),
};

export const LoadingState = {
  render: (...args) =>
    createTemplate({ billingPeriodHandler: pending, creditsUsageHandler: pending })(...args),
};

// The billing-period card and the filters are resolved while the filter-scoped
// data is still in flight.
export const FilteredUsageLoading = {
  render: (...args) => createTemplate({ creditsUsageHandler: pending })(...args),
};

export const FilteredUsageError = {
  render: (...args) =>
    createTemplate({
      creditsUsageHandler: () =>
        Promise.reject(new Error('Failed to fetch filtered credit usage data')),
    })(...args),
};

export const ErrorState = {
  render: (...args) =>
    createTemplate({
      billingPeriodHandler: () => Promise.reject(new Error('Failed to fetch credit usage data')),
    })(...args),
};

export const UsageBillingDisabled = {
  render: (...args) =>
    createTemplate({ billingPeriodHandler: billingPeriodFor({ enabled: false }) })(...args),
};

export const OutdatedClient = {
  render: (...args) =>
    createTemplate({ billingPeriodHandler: billingPeriodFor({ isOutdatedClient: true }) })(...args),
};

export const Blocked = {
  render: (...args) =>
    createTemplate({
      resolver: (...resolverArgs) => ({
        ...creditsUsageFor(...resolverArgs),
        blockedStatus: {
          __typename: 'GitlabSubscriptionUsageBlockedStatus',
          blocked: true,
          capType: 'FLAT_USER_CAP',
        },
      }),
    })(...args),
};

export const NoUsage = {
  render: (...args) =>
    createTemplate({ creditsUsageHandler: creditsUsageFor({ creditsUsed: 0, dailyUsage: [] }) })(
      ...args,
    ),
};
