<script>
import { computed } from 'vue';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import pollUntilComplete from '~/lib/utils/poll_until_complete';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import {
  metricChangeCount,
  metricSections,
} from 'ee/vue_merge_request_widget/widgets/metrics/utils';

export default normalizeRender({
  name: 'MetricsProvider',
  provide() {
    return {
      isMetricsLoading: computed(() => this.isFetching),
      statusMessage: computed(() => this.statusMessage),
      statusIconName: computed(() => this.statusIconName),
      numberOfChanges: computed(() => this.numberOfChanges),
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
      responseData: null,
    };
  },
  computed: {
    metricsEndpoint() {
      return this.mr.metricsReportsPath;
    },
    numberOfChanges() {
      return metricChangeCount(this.responseData);
    },
    sections() {
      return metricSections(this.responseData);
    },
    statusIconName() {
      if (this.hasError) {
        return EXTENSION_ICONS.error;
      }
      if (this.statusMessage || this.numberOfChanges > 0) {
        return EXTENSION_ICONS.warning;
      }
      return EXTENSION_ICONS.success;
    },
  },
  mounted() {
    this.fetchData();
  },
  methods: {
    async fetchData() {
      if (!this.metricsEndpoint) {
        this.statusMessage = s__('Reports|Metrics reports results are not available');
        this.isFetching = false;
        return;
      }

      try {
        const { data } = await pollUntilComplete(this.metricsEndpoint);
        this.responseData = data;
      } catch (error) {
        const statusReason = error.response?.data?.status_reason;
        this.statusMessage = statusReason || s__('Reports|Metrics reports failed to load results');
        this.hasError = !statusReason;

        if (this.hasError) Sentry.captureException(error);
      }

      this.isFetching = false;
    },
  },
  render() {
    return getSlotFunction(this)?.();
  },
});
</script>
