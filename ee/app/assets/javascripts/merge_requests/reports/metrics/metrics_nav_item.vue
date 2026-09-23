<script>
import { METRICS_ROUTE } from '~/merge_requests/reports/constants';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

export default {
  name: 'MetricsNavItem',
  components: {
    ReportListItem,
  },
  inject: ['isMetricsLoading', 'statusIconName'],
  routeNames: {
    METRICS_ROUTE,
  },
};
</script>

<template>
  <report-list-item
    :to="$options.routeNames.METRICS_ROUTE"
    :status-icon="statusIconName"
    :is-loading="isMetricsLoading"
  >
    {{ s__('MrReports|Metrics') }}
  </report-list-item>
</template>
