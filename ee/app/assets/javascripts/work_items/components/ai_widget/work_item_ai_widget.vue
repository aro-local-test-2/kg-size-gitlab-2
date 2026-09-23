<script>
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { findAgentPlanWidget } from 'ee/work_items/utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanUpdatedSubscription from 'ee/work_items/graphql/work_item_agent_plan.subscription.graphql';
import WorkItemConfidenceScore from './work_item_confidence_score.vue';
import WorkPlan from './work_plan.vue';
import { ACTIVE_RUN_POLL_INTERVAL_MS, GENERATION_STATUSES_ACTIVE } from './constants';

export default {
  name: 'WorkItemAiWidget',
  components: {
    WorkItemConfidenceScore,
    WorkPlan,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    workItem: {
      type: Object,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    isInDrawer: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['request-panel'],
  data() {
    return {
      agentPlan: null,
      isRunActive: false,
    };
  },
  apollo: {
    agentPlan: {
      query: workItemAgentPlanQuery,
      variables() {
        return this.agentPlanVariables;
      },
      skip() {
        return !this.workItemId;
      },
      update(data) {
        return findAgentPlanWidget(data?.workItem) || null;
      },
      error(error) {
        Sentry.captureException(error);
      },
      subscribeToMore: {
        document: workItemAgentPlanUpdatedSubscription,
        variables() {
          return this.agentPlanVariables;
        },
        skip() {
          return !this.workItemId;
        },
      },
      pollInterval() {
        return this.shouldPollPlan ? ACTIVE_RUN_POLL_INTERVAL_MS : 0;
      },
    },
  },
  computed: {
    workItemId() {
      return this.workItem.id;
    },
    useWorkItemFeatures() {
      return Boolean(this.glFeatures?.workItemFeaturesField);
    },
    agentPlanVariables() {
      return {
        id: this.workItemId,
        useWorkItemFeatures: this.useWorkItemFeatures,
        // Skip resolving readinessScore while workplan_score is disabled.
        includeReadinessScore: this.useScore,
      };
    },
    shouldPollPlan() {
      return (
        this.isRunActive || GENERATION_STATUSES_ACTIVE.includes(this.agentPlan?.generationStatus)
      );
    },
    isLoadingPlan() {
      return this.$apollo.queries.agentPlan.loading && !this.agentPlan;
    },
    useScore() {
      return Boolean(this.glFeatures?.workplanScore);
    },
    readinessScore() {
      return this.agentPlan?.readinessScore ?? null;
    },
    // The score is only produced after a workplan is generated, so there is nothing to
    // show until then. `useScore` stays flag-only because it also gates the query field.
    showScore() {
      return this.useScore && Number.isFinite(this.readinessScore);
    },
  },
  methods: {
    refetchAgentPlan() {
      this.$apollo.queries.agentPlan.refetch();
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-flex-col gl-gap-6 gl-py-6 md:gl-flex-row md:gl-flex-wrap md:gl-items-center md:gl-gap-8"
  >
    <work-plan
      class="gl-shrink-0"
      :work-item="workItem"
      :agent-plan="agentPlan"
      :is-loading="isLoadingPlan"
      :can-update="canUpdate"
      :work-item-web-url="workItemWebUrl"
      :is-in-drawer="isInDrawer"
      :is-panel-open="isPanelOpen"
      @request-panel="$emit('request-panel', $event)"
      @refetch-plan="refetchAgentPlan"
      @run-active="isRunActive = $event"
    />
    <work-item-confidence-score v-if="showScore && !isLoadingPlan" :score="readinessScore" />
  </div>
</template>
