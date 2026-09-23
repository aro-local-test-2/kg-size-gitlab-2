<script>
import { InternalEvents } from '~/tracking';
import {
  LOAD_PERFORMANCE_ROUTE,
  VIEW_MERGE_REQUEST_REPORT,
  TRACKING_LABEL_BY_ROUTE,
} from '~/merge_requests/reports/constants';
import LoadPerformanceProvider from './load_performance_provider.vue';
import LoadPerformanceContent from './load_performance_content.vue';

export default {
  name: 'LoadPerformancePage',
  components: {
    LoadPerformanceProvider,
    LoadPerformanceContent,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
  mounted() {
    this.trackEvent(VIEW_MERGE_REQUEST_REPORT, {
      label: TRACKING_LABEL_BY_ROUTE[LOAD_PERFORMANCE_ROUTE],
    });
  },
};
</script>

<template>
  <load-performance-provider :mr="mr">
    <load-performance-content />
  </load-performance-provider>
</template>
