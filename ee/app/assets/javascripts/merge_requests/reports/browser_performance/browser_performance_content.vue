<script>
import { s__ } from '~/locale';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

export default {
  name: 'BrowserPerformanceContent',
  components: {
    ReportSection,
  },
  inject: ['isBrowserPerformanceLoading', 'statusIconName', 'summary', 'sections'],
  i18n: {
    loading: s__('ciReport|Browser performance test metrics results are being parsed'),
  },
};
</script>

<template>
  <report-section
    :is-loading="isBrowserPerformanceLoading"
    :loading-text="$options.i18n.loading"
    :summary="summary"
    :status-icon-name="statusIconName"
    :sections="sections"
  />
</template>
