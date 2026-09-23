<script>
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import { s__ } from '~/locale';
import overviewQuery from '../queries/mr_ai_overview.query.graphql';
import mergeStatusSubscription from '../queries/mr_ai_overview.subscription.graphql';
import MergeReadiness from './merge_readiness.vue';

export default {
  name: 'AiOverviewApp',
  components: {
    GlAlert,
    GlLoadingIcon,
    MergeReadiness,
  },
  inject: ['projectPath', 'iid'],
  data() {
    return {
      mergeRequest: null,
      hasError: false,
    };
  },
  apollo: {
    mergeRequest: {
      query: overviewQuery,
      variables() {
        return { projectPath: this.projectPath, iid: this.iid };
      },
      update: (data) => data?.project?.mergeRequest,
      error() {
        this.hasError = true;
      },
      // The checks change while the page is open - a pipeline finishes, a thread is resolved.
      // The subscription payload is the same merge request, so the cache update re-renders the
      // rows without a refetch.
      subscribeToMore: {
        document: mergeStatusSubscription,
        skip() {
          return !this.mergeRequest?.id;
        },
        variables() {
          return { issuableId: this.mergeRequest?.id };
        },
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.mergeRequest.loading;
    },
  },
  methods: {
    retry() {
      this.hasError = false;
      this.$apollo.queries.mergeRequest.refetch();
    },
  },
  i18n: {
    heading: s__('AiOverview|AI Overview'),
    errorTitle: s__('AiOverview|Could not load this merge request'),
    retry: s__('AiOverview|Retry'),
  },
};
</script>

<template>
  <div class="gl-py-5">
    <h2 class="gl-sr-only">{{ $options.i18n.heading }}</h2>

    <gl-alert
      v-if="hasError"
      variant="danger"
      :title="$options.i18n.errorTitle"
      :primary-button-text="$options.i18n.retry"
      :dismissible="false"
      @primary-action="retry"
    />

    <div v-else-if="isLoading" class="gl-flex gl-justify-center gl-py-6">
      <gl-loading-icon size="lg" />
    </div>

    <div v-else-if="mergeRequest" class="ai-overview-body gl-grid gl-gap-6 gl-p-6">
      <!-- MAIN COLUMN -->
      <div class="gl-flex gl-min-w-0 gl-flex-col gl-gap-5">
        <merge-readiness :merge-request="mergeRequest" />
      </div>
    </div>
  </div>
</template>
