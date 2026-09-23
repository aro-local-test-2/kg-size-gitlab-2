<script>
import { BROWSER_PERFORMANCE_ROUTE } from '~/merge_requests/reports/constants';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

export default {
  name: 'BrowserPerformanceNavItem',
  components: {
    ReportListItem,
  },
  inject: ['isBrowserPerformanceLoading', 'statusIconName'],
  routeNames: {
    BROWSER_PERFORMANCE_ROUTE,
  },
};
</script>

<template>
  <report-list-item
    :to="$options.routeNames.BROWSER_PERFORMANCE_ROUTE"
    :status-icon="statusIconName"
    :is-loading="isBrowserPerformanceLoading"
  >
    {{ s__('MrReports|Browser performance') }}
  </report-list-item>
</template>
