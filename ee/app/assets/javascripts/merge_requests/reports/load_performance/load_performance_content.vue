<script>
import { s__ } from '~/locale';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

export default {
  name: 'LoadPerformanceContent',
  components: {
    ReportSection,
  },
  inject: ['isLoadPerformanceLoading', 'statusIconName', 'summary', 'sections'],
  i18n: {
    loading: s__('ciReport|Load performance test metrics results are being parsed'),
  },
};
</script>

<template>
  <report-section
    :is-loading="isLoadPerformanceLoading"
    :loading-text="$options.i18n.loading"
    :summary="summary"
    :status-icon-name="statusIconName"
    :sections="sections"
  />
</template>
