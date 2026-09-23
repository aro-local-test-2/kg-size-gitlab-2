import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlTabs, GlSearchBoxByType, GlSkeletonLoader, GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ExploreAnalyticsDashboardsListEE from 'ee/explore/analytics_dashboards/pages/list.vue';
import DashboardHeroHeader from 'ee/explore/analytics_dashboards/components/dashboard_hero_header.vue';
import DashboardsList from '~/vue_shared/components/dashboards_list/dashboards_list.vue';
import EmptyState from '~/vue_shared/components/dashboards_list/empty_state.vue';
import getDashboardsQuery from '~/explore/analytics_dashboards/graphql/get_dashboards.query.graphql';
import {
  mockDashboardsListResponse,
  mockEmptyDashboardsListResponse,
  mockNullDashboardsListResponse,
} from 'jest/explore/analytics_dashboards/mock_data';

Vue.use(VueApollo);

jest.mock('~/sentry/sentry_browser_wrapper');

describe('ExploreAnalyticsDashboardsListEE', () => {
  let wrapper;

  const mockResolvedQuery = (queryResponse = mockDashboardsListResponse) =>
    createMockApollo([[getDashboardsQuery, jest.fn().mockResolvedValue({ data: queryResponse })]]);

  const mockRejectedQuery = (error = new Error('Network error')) =>
    createMockApollo([[getDashboardsQuery, jest.fn().mockRejectedValue(error)]]);

  const createComponent = ({ apolloProvider } = {}) => {
    wrapper = shallowMountExtended(ExploreAnalyticsDashboardsListEE, {
      provide: {
        exploreAnalyticsDashboardsPath: '/explore/analytics_dashboards',
      },
      apolloProvider: apolloProvider || mockResolvedQuery(),
    });
  };

  const findHeroHeader = () => wrapper.findComponent(DashboardHeroHeader);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findEmptyState = () => wrapper.findComponent(EmptyState);
  const findDashboardsList = () => wrapper.findComponent(DashboardsList);

  describe('page layout', () => {
    beforeEach(async () => {
      createComponent();

      await waitForPromises();
    });

    // The hero header's contents are covered by dashboard_hero_header_spec.js.
    it('renders the hero header', () => {
      expect(findHeroHeader().exists()).toBe(true);
    });

    it('does not render tabs', () => {
      expect(wrapper.findComponent(GlTabs).exists()).toBe(false);
    });

    it('does not render a search box', () => {
      expect(wrapper.findComponent(GlSearchBoxByType).exists()).toBe(false);
    });
  });

  describe('while the dashboards request is pending', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render the dashboards list, alert, or empty state', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when the request succeeds with dashboards', () => {
    beforeEach(async () => {
      createComponent();

      await waitForPromises();
    });

    it('renders a single dashboards list', () => {
      expect(wrapper.findAllComponents(DashboardsList)).toHaveLength(1);
    });

    it('passes the dashboards to the list', () => {
      const dashboards = findDashboardsList().props('dashboards');

      expect(dashboards).toHaveLength(2);
      expect(dashboards[0].name).toBe('Fake trends');
    });

    it('builds the dashboard URL from the numeric ID for custom dashboards', () => {
      const [customDashboard] = findDashboardsList().props('dashboards');

      expect(customDashboard.dashboardUrl).toBe('/explore/analytics_dashboards/3');
    });

    it('builds the dashboard URL from the slug for system dashboards', () => {
      const dashboards = findDashboardsList().props('dashboards');
      const systemDashboard = dashboards.find((dashboard) => dashboard.system);

      expect(systemDashboard.dashboardUrl).toBe('/explore/analytics_dashboards/merge_requests');
    });

    it('does not render the skeleton loader, alert, or empty state', () => {
      expect(findSkeletonLoader().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when there are no dashboards', () => {
    beforeEach(async () => {
      createComponent({ apolloProvider: mockResolvedQuery(mockEmptyDashboardsListResponse) });

      await waitForPromises();
    });

    it('renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not render the dashboards list or an alert', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the dashboards query is unauthorized', () => {
    beforeEach(async () => {
      createComponent({ apolloProvider: mockResolvedQuery(mockNullDashboardsListResponse) });

      await waitForPromises();
    });

    it('renders the empty state instead of erroring', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the request fails', () => {
    const testError = new Error('Test error');

    beforeEach(async () => {
      createComponent({ apolloProvider: mockRejectedQuery(testError) });

      await waitForPromises();
    });

    it('renders the error alert', () => {
      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().text()).toContain('Failed to load dashboards list. Please try again.');
    });

    it('does not render the dashboards list or empty state', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });

    it('calls Sentry.captureException with the error', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(testError);
    });
  });
});
