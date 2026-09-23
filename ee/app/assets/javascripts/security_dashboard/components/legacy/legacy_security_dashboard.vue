<script>
import IndexLayout from '~/vue_shared/components/index_layout.vue';
import LegacyPdfExportButton from 'ee/security_dashboard/components/legacy/legacy_pdf_export_button.vue';
import LegacyVulnerabilitySeverities from './legacy_project_security_status_chart.vue';
import LegacyVulnerabilitiesOverTimeChart from './legacy_vulnerabilities_over_time_chart.vue';
import LegacyNoLongerDetectedVulnerabilitiesAlert from './legacy_no_longer_detected_vulnerabilities_alert.vue';

export default {
  name: 'LegacySecurityDashboard',
  components: {
    LegacyVulnerabilitiesOverTimeChart,
    LegacyVulnerabilitySeverities,
    LegacyNoLongerDetectedVulnerabilitiesAlert,
    IndexLayout,
    LegacyPdfExportButton,
  },
  inject: ['groupFullPath'],
  props: {
    historyQuery: {
      type: Object,
      required: true,
    },
    gradesQuery: {
      type: Object,
      required: true,
    },
    showExport: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      vulnerabilitiesChartFn: null,
      vulnerabilitySeveritiesChartFn: null,
    };
  },
  computed: {
    showExportButton() {
      return this.showExport;
    },
  },
  methods: {
    getReportData() {
      return {
        group_vulnerabilities_over_time: this.vulnerabilitiesChartFn?.() || {},
        project_security_status: this.vulnerabilitySeveritiesChartFn?.() || {},
        full_path: this.groupFullPath,
      };
    },
  },
};
</script>

<template>
  <index-layout
    :heading="s__('SecurityReports|Security dashboard')"
    data-testid="legacy-security-dashboard"
  >
    <template #actions>
      <legacy-pdf-export-button v-if="showExportButton" :get-report-data="getReportData" />
    </template>

    <legacy-no-longer-detected-vulnerabilities-alert />

    <div class="security-charts gl-grid">
      <legacy-vulnerabilities-over-time-chart
        :query="historyQuery"
        @chart-report-data-registered="vulnerabilitiesChartFn = $event"
      />
      <legacy-vulnerability-severities
        :query="gradesQuery"
        @chart-report-data-registered="vulnerabilitySeveritiesChartFn = $event"
      />
    </div>
  </index-layout>
</template>
