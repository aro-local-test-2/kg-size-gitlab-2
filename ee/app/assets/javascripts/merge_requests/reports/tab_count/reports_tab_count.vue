<script>
import { observable } from '~/lib/utils/observable';
import { SECURITY_SCAN_TO_REPORT_TYPE } from '~/vue_merge_request_widget/constants';
import mergeRequestData, { PIPELINE_STATE } from '~/merge_requests/reports/merge_request_data';

const SCAN_TYPES = Object.keys(SECURITY_SCAN_TO_REPORT_TYPE).filter(
  (type) => type !== 'clusterImageScanning',
);

const tabData = observable('mr_page_tab_data', { tabs: [] });

export default {
  name: 'ReportsTabCount',
  mixins: [mergeRequestData],
  computed: {
    text() {
      if (this.pipelineState !== PIPELINE_STATE.complete) return '-';

      const reports = [
        SCAN_TYPES.some((type) => this.mr.enabledReports?.[type]),
        this.hasLicenseComplianceReports,
        this.hasCodeQualityReports,
        this.hasBrowserPerformanceReports,
        this.hasLoadPerformanceReports,
        this.hasAccessibilityReports,
        this.hasMetricsReports,
      ];

      return String(reports.filter(Boolean).length);
    },
    // Populated in a requestIdleCallback, so it can arrive after the count does.
    stickyHeaderTab() {
      return tabData.tabs?.find(([key]) => key === 'reports');
    },
  },
  watch: {
    text: 'syncStickyHeader',
    stickyHeaderTab: 'syncStickyHeader',
  },
  methods: {
    syncStickyHeader() {
      if (this.stickyHeaderTab) this.stickyHeaderTab[3] = this.text;
    },
  },
};
</script>

<template>
  <span class="js-reports-tab-count">{{ text }}</span>
</template>
