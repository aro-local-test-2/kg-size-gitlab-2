<script>
import { GlSkeletonLoader } from '@gitlab/ui';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import AgentFlowList from 'ee/ai/duo_agents_platform/components/common/agent_flow_list.vue';
import AgentFlowFilteredSearch from 'ee/ai/duo_agents_platform/components/common/agent_flow_filtered_search.vue';
import {
  AGENT_PLATFORM_INDEX_COMPONENT_NAME,
  DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES,
} from 'ee/ai/duo_agents_platform/constants';
import NoCreditsBanner from '../../components/common/no_credits_banner.vue';
import UsageBillingForbiddenBanner from '../../components/common/usage_billing_forbidden_banner.vue';

export default {
  name: AGENT_PLATFORM_INDEX_COMPONENT_NAME,
  components: {
    AgentFlowFilteredSearch,
    AgentFlowList,
    GlSkeletonLoader,
    PageHeading,
    NoCreditsBanner,
    UsageBillingForbiddenBanner,
  },
  inject: {
    isSidePanelView: { default: false },
    creditsAvailable: { default: true },
    billingForbidden: { default: false },
  },
  props: {
    hasInitialWorkflows: {
      required: true,
      type: Boolean,
    },
    initialSort: {
      required: true,
      type: String,
    },
    initialFilters: {
      required: false,
      type: Object,
      default: () => ({}),
    },
    isLoadingWorkflows: {
      required: true,
      type: Boolean,
    },
    workflows: {
      required: true,
      type: Array,
    },
    workflowsPageInfo: {
      required: true,
      type: Object,
    },
  },
  emits: ['query-variables-updated'],
  data() {
    const { updatedAfter = null, ...filters } = this.initialFilters;
    return {
      searchVariables: { sort: this.initialSort, filters, updatedAfter },
    };
  },
  computed: {
    showEmptyState() {
      return !this.hasInitialWorkflows;
    },
  },
  methods: {
    handleSearchVariablesUpdated(searchVariables) {
      this.searchVariables = searchVariables;
      this.handlePagination(DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES);
    },
    handleNextPage() {
      const paginationVars = {
        before: null,
        after: this.workflowsPageInfo.endCursor,
        first: 20,
        last: null,
      };
      this.handlePagination(paginationVars);
    },
    handlePrevPage() {
      const paginationVars = {
        after: null,
        before: this.workflowsPageInfo.startCursor,
        first: null,
        last: 20,
      };
      this.handlePagination(paginationVars);
    },
    handlePagination(pagination) {
      this.$emit('query-variables-updated', { ...this.searchVariables, pagination });
    },
  },
};
</script>
<template>
  <div class="gl-min-h-full gl-flex-wrap gl-justify-center" data-testid="agent-sessions">
    <page-heading v-if="!isSidePanelView" :heading="s__('DuoAgentsPlatform|Sessions')" />
    <usage-billing-forbidden-banner v-if="!creditsAvailable && billingForbidden" />
    <no-credits-banner v-else-if="!creditsAvailable" />
    <agent-flow-filtered-search
      :has-initial-workflows="hasInitialWorkflows"
      :initial-sort="initialSort"
      :initial-filters="initialFilters"
      @search-variables-updated="handleSearchVariablesUpdated"
    />
    <div
      v-if="isLoadingWorkflows"
      class="gl-flex gl-w-full gl-flex-col gl-gap-5 gl-p-5"
      data-testid="loading-container"
    >
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
    </div>
    <agent-flow-list
      v-else
      :show-project-info="isSidePanelView"
      :show-empty-state="showEmptyState"
      :workflows="workflows"
      :workflows-page-info="workflowsPageInfo"
      @next-page="handleNextPage"
      @prev-page="handlePrevPage"
    />
  </div>
</template>
