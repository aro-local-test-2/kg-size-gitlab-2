const CURRENT_USER_ID = 'gid://gitlab/User/1';

const BILLING_PERIOD_START = '2026-09-01';
const BILLING_PERIOD_END = '2026-09-14';

// Mirrors the shape the controller exposes as `groups_with_gitlab_credits`.
export const MOCK_GROUPS = [
  { name: 'Dunder Mifflin', path: 'dunder-mifflin' },
  { name: 'Lumon Industries', path: 'lumon-industries' },
];

// Keyed by group path so a group switch visibly changes every card and the
// chart. Daily credits are positional: index 0 is the 1st of the month.
const USAGE_BY_GROUP = {
  'dunder-mifflin': {
    creditsUsed: 19.1,
    dailyCredits: [1.2, 0.8, 2.1, 1.5, 0.3, 1.9, 2.4, 0.6, 1.1, 3.0, 0.9, 1.7, 2.2, 0.4],
  },
  'lumon-industries': {
    creditsUsed: 6.5,
    dailyCredits: [0.2, 0.9, 0.0, 0.4, 1.3, 0.7, 0.1, 0.5, 0.0, 0.3, 0.8, 0.2, 0.6, 0.5],
  },
};

const buildDailyUsage = (dailyCredits) =>
  dailyCredits.map((creditsUsed, index) => ({
    __typename: 'GitlabSubscriptionUserCreditsUsageDailyUsage',
    date: `2026-09-${String(index + 1).padStart(2, '0')}`,
    creditsUsed,
  }));

const defaultGroupUsage = USAGE_BY_GROUP[MOCK_GROUPS[0].path];

export const mockBillingPeriodUsage = {
  __typename: 'GitlabSubscriptionUserCreditsUsage',
  enabled: true,
  isOutdatedClient: false,
  startDate: BILLING_PERIOD_START,
  endDate: BILLING_PERIOD_END,
  creditsUsed: defaultGroupUsage.creditsUsed,
};

export const mockCreditsUsage = {
  __typename: 'GitlabSubscriptionUserCreditsUsage',
  startDate: BILLING_PERIOD_START,
  endDate: BILLING_PERIOD_END,
  creditsUsed: defaultGroupUsage.creditsUsed,
  dailyUsage: buildDailyUsage(defaultGroupUsage.dailyCredits),
  products: [
    {
      __typename: 'GitlabSubscriptionUserCreditsUsageProduct',
      id: 'duo_agent_platform',
      title: 'GitLab Duo Agent Platform',
      flowTypes: [
        {
          __typename: 'GitlabSubscriptionUsageFlowTypeInfo',
          id: 'chat',
          title: 'Chat',
        },
        {
          __typename: 'GitlabSubscriptionUsageFlowTypeInfo',
          id: 'code_suggestions',
          title: 'Code Suggestions',
        },
      ],
    },
  ],
  blockedStatus: {
    __typename: 'GitlabSubscriptionUsageBlockedStatus',
    blocked: false,
    capType: null,
  },
};

// Lets a query handler vary its response by the requested group.
export const usageForGroup = (namespacePath) => {
  const { creditsUsed, dailyCredits } = USAGE_BY_GROUP[namespacePath] ?? defaultGroupUsage;

  return { creditsUsed, dailyUsage: buildDailyUsage(dailyCredits) };
};

export const buildBillingPeriodUsageResponse = (creditsUsage = {}) => ({
  data: {
    currentUser: {
      __typename: 'CurrentUser',
      id: CURRENT_USER_ID,
      creditsUsage: { ...mockBillingPeriodUsage, ...creditsUsage },
    },
  },
});

export const buildCreditsUsageResponse = (creditsUsage = {}) => ({
  data: {
    currentUser: {
      __typename: 'CurrentUser',
      id: CURRENT_USER_ID,
      creditsUsage: { ...mockCreditsUsage, ...creditsUsage },
    },
  },
});
