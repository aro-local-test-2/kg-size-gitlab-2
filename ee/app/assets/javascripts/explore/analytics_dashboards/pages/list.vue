<script>
import { GlSkeletonLoader, GlAlert } from '@gitlab/ui';
import { s__ } from '~/locale';
import { joinPaths } from '~/lib/utils/url_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DashboardsList from '~/vue_shared/components/dashboards_list/dashboards_list.vue';
import EmptyState from '~/vue_shared/components/dashboards_list/empty_state.vue';
import { getDashboardIdFromGraphQLId } from '~/explore/analytics_dashboards/utils';
import getDashboardsQuery from '~/explore/analytics_dashboards/graphql/get_dashboards.query.graphql';
import DashboardHeroHeader from '../components/dashboard_hero_header.vue';

export default {
  name: 'ExploreAnalyticsDashboardsListEE',
  components: {
    DashboardHeroHeader,
    DashboardsList,
    EmptyState,
    GlSkeletonLoader,
    GlAlert,
  },
  inject: ['exploreAnalyticsDashboardsPath'],
  data() {
    return {
      dashboards: [],
      errorText: '',
    };
  },
  computed: {
    isLoading() {
      return Boolean(this.$apollo.queries.dashboards?.loading);
    },
    hasError() {
      return this.errorText !== '';
    },
    hasDashboards() {
      return Boolean(this.dashboards.length);
    },
    enrichedDashboards() {
      // Enriches the raw results with any FE computed fields we need
      return this.dashboards.map((data) => ({
        ...data,
        dashboardUrl: data.system
          ? joinPaths(this.exploreAnalyticsDashboardsPath, data.slug)
          : joinPaths(
              this.exploreAnalyticsDashboardsPath,
              String(getDashboardIdFromGraphQLId(data.id)),
            ),
      }));
    },
  },
  apollo: {
    dashboards: {
      query: getDashboardsQuery,
      update({ customDashboards }) {
        // `customDashboards` is null when the query is unauthorized fall back to an
        // empty list so the empty state renders instead of erroring.
        return customDashboards?.nodes ?? [];
      },
      error(err) {
        this.errorText = s__(
          'AnalyticsDashboards|Failed to load dashboards list. Please try again.',
        );
        Sentry.captureException(err);
      },
    },
  },
};
</script>
<template>
  <div class="gl-@container">
    <dashboard-hero-header />

    <!-- Shares the hero text's horizontal gutter so the left edges align. -->
    <div class="gl-px-5">
      <gl-skeleton-loader v-if="isLoading" class="gl-mt-8" />
      <gl-alert v-else-if="hasError" variant="danger" :dismissible="false" class="gl-mt-8">{{
        errorText
      }}</gl-alert>
      <dashboards-list v-else-if="hasDashboards" class="gl-mt-8" :dashboards="enrichedDashboards" />
      <empty-state v-else class="gl-mt-8" />
    </div>
  </div>
</template>
