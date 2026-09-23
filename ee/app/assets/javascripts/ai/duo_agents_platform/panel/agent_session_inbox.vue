<script>
import { GlBadge, GlButton, GlEmptyState, GlTab, GlTabs } from '@gitlab/ui';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import getUserAgentFlowInboxQuery from '../graphql/queries/get_user_agent_flow_inbox.query.graphql';
import AgentFlowFilteredSearch from '../components/common/agent_flow_filtered_search.vue';
import { DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES, INBOX_TAB_ALL } from '../constants';
import AgentSessionInboxTab from './agent_session_inbox_tab.vue';

const { first: PAGE_SIZE } = DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES;

// The connection has no count field, so a full page reads as "20+" rather than a total.
const TAB_COUNT_OVERFLOW = `${PAGE_SIZE}+`;

const nextPageVars = ({ endCursor }) => ({
  after: endCursor,
  before: null,
  first: PAGE_SIZE,
  last: null,
});

const prevPageVars = ({ startCursor }) => ({
  after: null,
  before: startCursor,
  first: null,
  last: PAGE_SIZE,
});

export default {
  name: 'AgentSessionInbox',
  components: {
    AgentFlowFilteredSearch,
    AgentSessionInboxTab,
    GlBadge,
    GlButton,
    GlEmptyState,
    GlTab,
    GlTabs,
  },
  data() {
    return {
      inbox: null,
      activeTab: INBOX_TAB_ALL,
      allPaginationVars: { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      needsDecisionPaginationVars: { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      currentSort: 'UPDATED_DESC',
      filterVariables: {},
      hasInitialWorkflows: false,
    };
  },
  apollo: {
    inbox: {
      query: getUserAgentFlowInboxQuery,
      context: { featureCategory: 'duo_agent_platform' },
      pollInterval: 10000,
      variables() {
        return {
          type: 'non_foundational_chat_agents',
          sort: this.currentSort,
          ...this.filterVariables,
          ...this.allQueryVars,
          ...this.needsDecisionQueryVars,
        };
      },
      // vue-apollo would fall back to `data.inbox`, which this query never selects:
      // it aliases two connections. Without the hook it errors and assigns nothing.
      update(data) {
        return data;
      },
      result({ data }) {
        // A latch rather than a derived value: the All tab's empty state has to
        // distinguish "never had rows" from "filtered down to none".
        const ndEdges = data?.needsDecision?.edges ?? [];
        const allEdges = data?.all?.edges ?? [];
        if (ndEdges.length > 0 || allEdges.length > 0) this.hasInitialWorkflows = true;
      },
      error(err) {
        createAlert({
          message: err.message || s__('DuoAgentsPlatform|Failed to fetch workflows'),
          captureError: true,
        });
      },
    },
  },
  computed: {
    needsDecisionWorkflows() {
      return this.inbox?.needsDecision?.edges?.map((e) => e.node) ?? [];
    },
    allWorkflows() {
      return this.inbox?.all?.edges?.map((e) => e.node) ?? [];
    },
    needsDecisionPageInfo() {
      return this.inbox?.needsDecision?.pageInfo ?? {};
    },
    allPageInfo() {
      return this.inbox?.all?.pageInfo ?? {};
    },
    allQueryVars() {
      const { first, after, last, before } = this.allPaginationVars;
      return {
        allFirst: first,
        allAfter: after,
        allLast: last,
        allBefore: before,
      };
    },
    needsDecisionQueryVars() {
      const { first, after, last, before } = this.needsDecisionPaginationVars;
      return {
        needsDecisionFirst: first,
        needsDecisionAfter: after,
        needsDecisionLast: last,
        needsDecisionBefore: before,
      };
    },
    isInboxLoading() {
      return this.$apollo.queries.inbox.loading && !this.inbox;
    },
    needsDecisionBadge() {
      return this.needsDecisionPageInfo.hasNextPage || this.needsDecisionPageInfo.hasPreviousPage
        ? TAB_COUNT_OVERFLOW
        : String(this.needsDecisionWorkflows.length);
    },
    hasActiveFilters() {
      return Object.keys(this.filterVariables).length > 0;
    },
    showDecisionEmptyState() {
      return this.needsDecisionWorkflows.length === 0 && !this.hasActiveFilters;
    },
    showAllEmptyState() {
      return !this.hasInitialWorkflows;
    },
  },
  methods: {
    handleSearchVariablesUpdated({ sort, filters, updatedAfter }) {
      this.currentSort = sort;
      this.filterVariables = {
        ...filters,
        ...(updatedAfter ? { updatedAfter } : {}),
      };
      this.resetPagination();
    },
    handleNextPage() {
      this.allPaginationVars = nextPageVars(this.allPageInfo);
    },
    handlePrevPage() {
      this.allPaginationVars = prevPageVars(this.allPageInfo);
    },
    handleDecisionNextPage() {
      this.needsDecisionPaginationVars = nextPageVars(this.needsDecisionPageInfo);
    },
    handleDecisionPrevPage() {
      this.needsDecisionPaginationVars = prevPageVars(this.needsDecisionPageInfo);
    },
    showAllTab() {
      this.handleTabChange(INBOX_TAB_ALL);
    },
    handleTabChange(tab) {
      this.activeTab = tab;
      this.resetPagination();
    },
    resetPagination() {
      this.allPaginationVars = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
      this.needsDecisionPaginationVars = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
    },
  },
};
</script>
<template>
  <div data-testid="agent-session-inbox">
    <agent-flow-filtered-search
      :has-initial-workflows="hasInitialWorkflows"
      :initial-sort="currentSort"
      @search-variables-updated="handleSearchVariablesUpdated"
    />
    <gl-tabs :value="activeTab" @input="handleTabChange">
      <gl-tab>
        <template #title>
          {{ s__('DuoAgentsPlatform|Needs a decision') }}
          <gl-badge
            v-if="!isInboxLoading"
            class="gl-tab-counter-badge"
            data-testid="needs-decision-tab-badge"
          >
            {{ needsDecisionBadge }}
          </gl-badge>
        </template>
        <agent-session-inbox-tab
          data-testid="needs-decision-tab"
          testid-prefix="needs-decision"
          :loading="isInboxLoading"
          :workflows="needsDecisionWorkflows"
          :page-info="needsDecisionPageInfo"
          :show-empty-state="showDecisionEmptyState"
          @next-page="handleDecisionNextPage"
          @prev-page="handleDecisionPrevPage"
        >
          <template #empty-state>
            <gl-empty-state
              :title="s__('DuoAgentsPlatform|Nothing needs you right now')"
              :description="
                s__(
                  'DuoAgentsPlatform|Your agents are grinding away. The moment one of them wants a decision, it lands here.',
                )
              "
            >
              <template #actions>
                <gl-button @click="showAllTab">
                  {{ s__('DuoAgentsPlatform|See what’s running') }}
                </gl-button>
              </template>
            </gl-empty-state>
          </template>
        </agent-session-inbox-tab>
      </gl-tab>
      <gl-tab>
        <template #title>
          {{ s__('DuoAgentsPlatform|All') }}
        </template>
        <agent-session-inbox-tab
          data-testid="all-tab"
          testid-prefix="all"
          :loading="isInboxLoading"
          :workflows="allWorkflows"
          :page-info="allPageInfo"
          :show-empty-state="showAllEmptyState"
          @next-page="handleNextPage"
          @prev-page="handlePrevPage"
        />
      </gl-tab>
    </gl-tabs>
  </div>
</template>
