<script>
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import getUserAgentFlows from 'ee/ai/duo_agents_platform/graphql/queries/get_user_agent_flow.query.graphql';
import DuoAgentsPlatformIndex from 'ee/ai/duo_agents_platform/pages/index/duo_agents_platform_index.vue';
import { DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES } from 'ee/ai/duo_agents_platform/constants';
import {
  saveSessionsQueryVariables,
  getSessionsQueryVariables,
} from 'ee/ai/duo_agents_platform/utils/sessions_query_state';

const USER_SESSIONS_KEY = 'user';

export default {
  name: 'UserAgentsPlatformIndex',
  components: { DuoAgentsPlatformIndex },
  data() {
    const saved = getSessionsQueryVariables(USER_SESSIONS_KEY);
    const savedFilters = saved?.filters ?? {};

    return {
      workflows: [],
      workflowsPageInfo: {},
      currentSort: saved?.sort ?? 'UPDATED_DESC',
      hasInitialWorkflows: false,
      paginationVariables: saved?.pagination ?? { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      filterVariables: savedFilters,
      initialFilters: savedFilters,
    };
  },
  apollo: {
    workflows: {
      query: getUserAgentFlows,
      context: {
        featureCategory: 'duo_agent_platform',
      },
      pollInterval: 10000,
      variables() {
        return {
          ...this.paginationVariables,
          type: 'non_foundational_chat_agents',
          sort: this.currentSort,
          ...this.filterVariables,
        };
      },
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.map((w) => w.node) || [];
      },
      result({ data }) {
        this.workflowsPageInfo = data?.duoWorkflowWorkflows?.pageInfo || {};

        const workflows = data?.duoWorkflowWorkflows?.edges?.map((w) => w.node) || [];
        if (workflows.length > 0) {
          this.hasInitialWorkflows = true;
        }
      },
      error(error) {
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to fetch workflows'),
          captureError: true,
        });
      },
    },
  },
  computed: {
    isLoadingWorkflows() {
      return this.$apollo.queries.workflows.loading;
    },
  },
  methods: {
    handleQueryVariablesUpdate({ sort, pagination, filters, updatedAfter }) {
      this.currentSort = sort;
      this.paginationVariables = pagination;
      this.filterVariables = {
        ...filters,
        ...(updatedAfter && { updatedAfter }),
      };
      saveSessionsQueryVariables(USER_SESSIONS_KEY, {
        sort,
        pagination,
        filters: this.filterVariables,
      });
    },
  },
};
</script>
<template>
  <duo-agents-platform-index
    :has-initial-workflows="hasInitialWorkflows"
    :initial-sort="currentSort"
    :initial-filters="initialFilters"
    :is-loading-workflows="isLoadingWorkflows"
    :workflows="workflows"
    :workflows-page-info="workflowsPageInfo"
    class="gl-min-w-full"
    @query-variables-updated="handleQueryVariablesUpdate"
  />
</template>
