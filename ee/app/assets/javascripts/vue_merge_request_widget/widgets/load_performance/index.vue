<script>
import { s__ } from '~/locale';
import axios from '~/lib/utils/axios_utils';
import { joinPaths } from '~/lib/utils/url_utility';
import {
  LOAD_PERFORMANCE_ROUTE,
  CLICK_VIEW_REPORT_ON_MERGE_REQUEST_WIDGET,
  TRACKING_LABEL_BY_ROUTE,
} from '~/merge_requests/reports/constants';
import { InternalEvents } from '~/tracking';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import {
  compareLoadPerformanceMetrics,
  loadPerformanceStatusIcon,
  loadPerformanceSummary,
} from './utils';

export default {
  name: 'WidgetLoadPerformance',
  i18n: {
    loading: s__('ciReport|Load performance test metrics results are being parsed'),
  },
  components: {
    MrWidget,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
  emits: ['loaded'],
  data() {
    return {
      headMetrics: [],
      baseMetrics: [],
    };
  },
  computed: {
    comparison() {
      return compareLoadPerformanceMetrics(this.headMetrics, this.baseMetrics);
    },
    summary() {
      return loadPerformanceSummary(this.comparison);
    },
    statusIcon() {
      return loadPerformanceStatusIcon(this.comparison);
    },
    shouldCollapse() {
      return this.content.length > 0;
    },
    content() {
      const { improved, degraded, same } = this.comparison;
      return [...improved, ...degraded, ...same];
    },
    actionButtons() {
      if (!this.mr.reportsTabPath) return [];

      return [
        {
          text: s__('MrReports|View report'),
          href: joinPaths(this.mr.reportsTabPath, LOAD_PERFORMANCE_ROUTE),
          onClick: (action, e) => {
            e.preventDefault();
            this.trackEvent(CLICK_VIEW_REPORT_ON_MERGE_REQUEST_WIDGET, {
              label: TRACKING_LABEL_BY_ROUTE[LOAD_PERFORMANCE_ROUTE],
            });
            window.history.pushState(null, null, action.href);
            window.dispatchEvent(new PopStateEvent('popstate'));
          },
        },
      ];
    },
  },
  methods: {
    fetchHeadAndBaseReports() {
      const { head_path: headPath, base_path: basePath } = this.mr.loadPerformance;

      return [headPath, basePath].map((endpoint) => () => {
        return axios.get(endpoint).then((response) => {
          if (endpoint === headPath) {
            this.headMetrics = response.data;
          } else if (endpoint === basePath) {
            this.baseMetrics = response.data;
          }

          this.$emit('loaded', this.comparison.degraded.length);

          return response;
        });
      });
    },
  },
};
</script>
<template>
  <mr-widget
    :action-buttons="actionButtons"
    :status-icon-name="statusIcon"
    :loading-text="$options.i18n.loading"
    :widget-name="$options.name"
    :is-collapsible="shouldCollapse"
    :expand-button-label="s__('ciReport|Expand load performance details')"
    :collapse-button-label="s__('ciReport|Collapse load performance details')"
    :fetch-collapsed-data="fetchHeadAndBaseReports"
    :summary="summary"
    :content="content"
    multi-polling
  />
</template>
