import createMockApollo from 'helpers/mock_apollo_helper';
import getUserCalloutsQuery from '~/graphql_shared/queries/get_user_callouts.query.graphql';
import ExploreDashboardsAlert from './explore_dashboards_alert.vue';

export default {
  component: ExploreDashboardsAlert,
  title: 'ee/analytics/analytics_dashboards/components/explore_dashboards_alert',
};

const apolloProvider = () =>
  createMockApollo([
    [
      getUserCalloutsQuery,
      () =>
        Promise.resolve({
          data: {
            currentUser: {
              id: 'gid://gitlab/User/1',
              callouts: { nodes: [] },
            },
          },
        }),
    ],
  ]);

const Template = (args) => ({
  components: { ExploreDashboardsAlert },
  apolloProvider: apolloProvider(),
  provide: {},
  data() {
    return { ...args };
  },
  template: `<explore-dashboards-alert :explore-dashboards-path="exploreDashboardsPath" />`,
});

export const Default = {
  render: Template,
  args: {
    exploreDashboardsPath: '/explore/analytics_dashboards',
  },
};
