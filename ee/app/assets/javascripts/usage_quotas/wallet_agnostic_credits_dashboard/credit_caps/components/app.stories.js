import VueApollo from 'vue-apollo';
import {
  mockCreditCapsData,
  mockCreditCapsDataDisabled,
  mockCreditCapsNullCap,
  mockCreditCapsBudgetCapsNull,
  mockCreditCapsDataZeroCap,
  mockUpsertFlatUserCapSuccess,
  mockUpsertFlatUserCapErrors,
  mockUserOverridesData,
  mockUserOverridesEmpty,
  mockUserOverridesPage1of2,
  mockUserOverridesPage2of2,
  mockUpsertUserOverridesSuccess,
  mockUpsertUserOverridesErrors,
  mockSearchAllUsersResult,
  mockSearchGroupUsersResult,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';
import { createMockClient } from 'helpers/mock_apollo_helper';
import searchAllUsersQuery from '~/graphql_shared/queries/users_search_all.query.graphql';
import searchGroupUsersQuery from '~/graphql_shared/queries/group_users_search.query.graphql';
import getCreditCapsQuery from '../graphql/get_credit_caps.query.graphql';
import upsertFlatUserCapMutation from '../graphql/upsert_flat_user_cap.mutation.graphql';
import getUserOverridesQuery from '../graphql/get_user_overrides.query.graphql';
import upsertUserOverridesMutation from '../graphql/upsert_user_overrides.mutation.graphql';
import CreditCapsDashboardApp from './app.vue';

const meta = {
  title: 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/app',
  component: CreditCapsDashboardApp,
};

export default meta;

const createTemplate = ({
  queryHandler,
  mutationHandler,
  overridesHandler,
  overridesSaveHandler,
  searchAllUsersHandler,
  searchGroupUsersHandler,
  namespacePath = null,
} = {}) => {
  const defaultClient = createMockClient([
    [getCreditCapsQuery, queryHandler ?? (() => Promise.resolve(mockCreditCapsData))],
    [
      upsertFlatUserCapMutation,
      mutationHandler ?? (() => Promise.resolve(mockUpsertFlatUserCapSuccess)),
    ],
    [getUserOverridesQuery, overridesHandler ?? (() => Promise.resolve(mockUserOverridesData))],
    [
      upsertUserOverridesMutation,
      overridesSaveHandler ?? (() => Promise.resolve(mockUpsertUserOverridesSuccess)),
    ],
    [
      searchAllUsersQuery,
      searchAllUsersHandler ?? (() => Promise.resolve(mockSearchAllUsersResult)),
    ],
    [
      searchGroupUsersQuery,
      searchGroupUsersHandler ?? (() => Promise.resolve(mockSearchGroupUsersResult)),
    ],
  ]);

  const apolloProvider = new VueApollo({ defaultClient });

  return (args, { argTypes }) => ({
    apolloProvider,
    components: { CreditCapsDashboardApp },
    provide: { namespacePath },
    props: Object.keys(argTypes),
    template: `<credit-caps-dashboard-app />`,
  });
};

export const Default = {
  render: createTemplate(),
};

export const CapDisabled = {
  render: createTemplate({
    queryHandler: () => Promise.resolve(mockCreditCapsDataDisabled),
  }),
};

export const NullCap = {
  render: createTemplate({
    queryHandler: () => Promise.resolve(mockCreditCapsNullCap),
    overridesHandler: () => Promise.resolve(mockUserOverridesEmpty),
  }),
};

export const ZeroCapEnabled = {
  render: createTemplate({
    queryHandler: () => Promise.resolve(mockCreditCapsDataZeroCap),
  }),
};

export const GroupScoped = {
  render: createTemplate({ namespacePath: 'my-group' }),
};

export const OverridesEmpty = {
  render: createTemplate({
    overridesHandler: () => Promise.resolve(mockUserOverridesEmpty),
  }),
};

export const OverridesPaginated = {
  render: createTemplate({
    overridesHandler: (variables) => {
      if (variables.before) return Promise.resolve(mockUserOverridesPage1of2);
      if (variables.after) return Promise.resolve(mockUserOverridesPage2of2);
      return Promise.resolve(mockUserOverridesPage1of2);
    },
  }),
};

export const LoadingState = {
  render: createTemplate({
    queryHandler: () => new Promise(() => {}),
    overridesHandler: () => new Promise(() => {}),
  }),
};

export const ErrorState = {
  render: createTemplate({
    queryHandler: () => Promise.reject(new Error('Failed to fetch credit cap data')),
    overridesHandler: () => Promise.reject(new Error('Failed to fetch overrides')),
  }),
};

export const NullBudgetCaps = {
  render: createTemplate({
    queryHandler: () => Promise.resolve(mockCreditCapsBudgetCapsNull),
  }),
};

export const Saving = {
  render: createTemplate({
    mutationHandler: () => new Promise(() => {}),
    overridesSaveHandler: () => new Promise(() => {}),
  }),
};

export const SaveError = {
  render: createTemplate({
    mutationHandler: () => Promise.resolve(mockUpsertFlatUserCapErrors),
  }),
};

export const OverridesSaveError = {
  render: createTemplate({
    overridesSaveHandler: () => Promise.resolve(mockUpsertUserOverridesErrors),
  }),
};

export const AddOverrideModalSaaS = {
  render: createTemplate({
    namespacePath: 'my-group',
  }),
};

export const WithSearchError = {
  render: createTemplate({
    searchAllUsersHandler: () => Promise.reject(new Error('Failed to search for users')),
    searchGroupUsersHandler: () => Promise.reject(new Error('Failed to search for users')),
  }),
};
