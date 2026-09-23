<script>
import { n__, s__, sprintf } from '~/locale';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

export default {
  name: 'MetricsContent',
  components: {
    ReportSection,
  },
  inject: ['isMetricsLoading', 'statusMessage', 'numberOfChanges', 'statusIconName', 'sections'],
  i18n: {
    loading: s__('Reports|Metrics reports are loading'),
  },
  computed: {
    summary() {
      if (this.statusMessage) {
        return { title: this.statusMessage };
      }
      if (this.numberOfChanges === 0) {
        return { title: s__('Reports|Metrics report scanning detected no new changes') };
      }

      return {
        title: sprintf(
          s__('Reports|Metrics reports: %{strong_start}%{numberOfChanges}%{strong_end} %{changes}'),
          {
            numberOfChanges: this.numberOfChanges,
            changes: n__('change', 'changes', this.numberOfChanges),
          },
        ),
      };
    },
  },
};
</script>

<template>
  <report-section
    :is-loading="isMetricsLoading"
    :loading-text="$options.i18n.loading"
    :summary="summary"
    :status-icon-name="statusIconName"
    :sections="sections"
  />
</template>
