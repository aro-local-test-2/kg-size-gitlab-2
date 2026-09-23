<script>
import { computed } from 'vue';
import { s__ } from '~/locale';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import axios from '~/lib/utils/axios_utils';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import {
  compareLoadPerformanceMetrics,
  loadPerformanceSections,
  loadPerformanceStatusIcon,
  loadPerformanceSummary,
} from 'ee/vue_merge_request_widget/widgets/load_performance/utils';

export default normalizeRender({
  name: 'LoadPerformanceProvider',
  provide() {
    return {
      isLoadPerformanceLoading: computed(() => this.isFetching),
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
      headMetrics: null,
      baseMetrics: null,
    };
  },
  computed: {
    comparison() {
      return compareLoadPerformanceMetrics(this.headMetrics, this.baseMetrics);
    },
    sections() {
      return loadPerformanceSections(this.comparison);
    },
    summary() {
      if (this.statusMessage) return { title: this.statusMessage };

      return loadPerformanceSummary(this.comparison);
    },
    statusIconName() {
      if (this.hasError) return EXTENSION_ICONS.error;
      if (this.statusMessage) return EXTENSION_ICONS.warning;

      return loadPerformanceStatusIcon(this.comparison);
    },
  },
  mounted() {
    this.fetchData();
  },
  methods: {
    async fetchData() {
      const { head_path: headPath, base_path: basePath } = this.mr.loadPerformance || {};

      if (!headPath || !basePath) {
        this.statusMessage = s__('Reports|Load performance test results are not available');
        this.isFetching = false;
        return;
      }

      try {
        const [head, base] = await Promise.all([axios.get(headPath), axios.get(basePath)]);

        this.headMetrics = head.data;
        this.baseMetrics = base.data;
      } catch (error) {
        const statusReason = error.response?.data?.status_reason;
        this.statusMessage =
          statusReason || s__('Reports|Load performance test failed to load results');
        this.hasError = !statusReason;
      }

      this.isFetching = false;
    },
  },
  render() {
    return getSlotFunction(this)?.();
  },
});
</script>
