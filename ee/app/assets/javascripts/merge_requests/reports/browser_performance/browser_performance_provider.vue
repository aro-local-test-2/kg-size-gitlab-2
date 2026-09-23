<script>
import { computed } from 'vue';
import { s__ } from '~/locale';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import axios from '~/lib/utils/axios_utils';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import {
  browserPerformanceStatusIcon,
  browserPerformanceSummary,
  compareBrowserPerformanceMetrics,
} from 'ee/vue_merge_request_widget/widgets/browser_performance/utils';

export default normalizeRender({
  name: 'BrowserPerformanceProvider',
  provide() {
    return {
      isBrowserPerformanceLoading: computed(() => this.isFetching),
      statusIconName: computed(() => this.statusIconName),
      summary: computed(() => this.summary),
      sections: computed(() => this.sections),
    };
  },
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isFetching: true,
      statusMessage: '',
      hasError: false,
      headMetrics: [],
      baseMetrics: [],
    };
  },
  computed: {
    endpoints() {
      const { head_path: headPath, base_path: basePath } = this.mr.browserPerformance || {};

      return [headPath, basePath];
    },
    comparedMetrics() {
      return compareBrowserPerformanceMetrics(this.headMetrics, this.baseMetrics);
    },
    summary() {
      return this.statusMessage
        ? { title: this.statusMessage }
        : browserPerformanceSummary(this.comparedMetrics);
    },
    sections() {
      const { improved, degraded, same } = this.comparedMetrics;
      const children = [...improved, ...degraded, ...same];

      return children.length ? [{ children }] : [];
    },
    statusIconName() {
      if (this.hasError) {
        return EXTENSION_ICONS.error;
      }
      if (this.statusMessage) {
        return EXTENSION_ICONS.warning;
      }
      return browserPerformanceStatusIcon(this.comparedMetrics);
    },
  },
  mounted() {
    this.fetchData();
  },
  methods: {
    async fetchData() {
      if (!this.endpoints.every(Boolean)) {
        this.statusMessage = s__('ciReport|Browser performance results are not available');
        this.isFetching = false;
        return;
      }

      try {
        const [head, base] = await Promise.all(this.endpoints.map((path) => axios.get(path)));
        this.headMetrics = head.data;
        this.baseMetrics = base.data;
      } catch {
        this.statusMessage = s__('ciReport|Browser performance failed loading results');
        this.hasError = true;
      }

      this.isFetching = false;
    },
  },
  render() {
    return getSlotFunction(this)?.();
  },
});
</script>
