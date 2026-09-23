<script>
import { InternalEvents } from '~/tracking';
import {
  BROWSER_PERFORMANCE_ROUTE,
  VIEW_MERGE_REQUEST_REPORT,
  TRACKING_LABEL_BY_ROUTE,
} from '~/merge_requests/reports/constants';
import BrowserPerformanceProvider from './browser_performance_provider.vue';
import BrowserPerformanceContent from './browser_performance_content.vue';

export default {
  name: 'BrowserPerformancePage',
  components: {
    BrowserPerformanceProvider,
    BrowserPerformanceContent,
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
      label: TRACKING_LABEL_BY_ROUTE[BROWSER_PERFORMANCE_ROUTE],
    });
  },
};
</script>

<template>
  <browser-performance-provider :mr="mr">
    <browser-performance-content />
  </browser-performance-provider>
</template>
