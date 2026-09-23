<script>
import { LOAD_PERFORMANCE_ROUTE } from '~/merge_requests/reports/constants';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

export default {
  name: 'LoadPerformanceNavItem',
  components: {
    ReportListItem,
  },
  inject: ['isLoadPerformanceLoading', 'statusIconName'],
  routeNames: {
    LOAD_PERFORMANCE_ROUTE,
  },
};
</script>

<template>
  <report-list-item
    :to="$options.routeNames.LOAD_PERFORMANCE_ROUTE"
    :status-icon="statusIconName"
    :is-loading="isLoadPerformanceLoading"
  >
    {{ s__('MrReports|Load performance') }}
  </report-list-item>
</template>
