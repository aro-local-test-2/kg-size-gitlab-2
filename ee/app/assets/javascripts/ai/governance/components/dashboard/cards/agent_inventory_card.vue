<script>
import { GlIcon } from '@gitlab/ui';
import { s__, n__ } from '~/locale';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_GROUP, TYPENAME_PROJECT } from '~/graphql_shared/constants';
import { joinPaths } from '~/lib/utils/url_utility';
import getDashboardConfiguredAgentsQuery from 'ee/ai/governance/graphql/queries/get_dashboard_configured_agents.query.graphql';
import getConnectedAgentsQuery from 'ee/ai/governance/graphql/queries/get_connected_agents.query.graphql';
import {
  AGENT_CLASS_ALL,
  AGENT_CLASS_INTERNAL_DAP,
  AGENT_CLASS_EXTERNAL,
} from 'ee/ai/governance/constants';
import DashboardListCard from './dashboard_list_card.vue';

// Show the top agents by usage. The backend sorts and limits (#619188), so we
// request the display count directly, already ordered by 30-day usage.
const DISPLAY_LIMIT = 5;
const USAGE_SORT = 'USAGE_COUNT_DESC';
const AGENT_ITEM_TYPE = 'AGENT';

export default {
  name: 'AgentInventoryCard',
  components: {
    DashboardListCard,
    GlIcon,
  },
  inject: {
    groupId: { default: null },
    projectId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  props: {
    agentClass: {
      type: String,
      required: false,
      default: AGENT_CLASS_ALL,
    },
  },
  apollo: {
    // Catalog items are Duo Agent Platform agents by definition, so the
    // catalog has no agent-class argument and is skipped for Connected.
    configuredItems: {
      query: getDashboardConfiguredAgentsQuery,
      variables() {
        const base = {
          itemTypes: [AGENT_ITEM_TYPE],
          first: DISPLAY_LIMIT,
          sort: USAGE_SORT,
          // Match the "View all agents" page so foundational (GitLab-maintained)
          // agents show alongside the group's own agents.
          includeFoundationalConsumers: true,
        };

        return this.isProjectMode
          ? { ...base, projectId: convertToGraphQLId(TYPENAME_PROJECT, this.projectId) }
          : { ...base, groupId: convertToGraphQLId(TYPENAME_GROUP, this.groupId) };
      },
      skip() {
        return this.agentClass === AGENT_CLASS_EXTERNAL;
      },
      update(data) {
        this.hasError = false;
        return data.aiCatalogConfiguredItems?.nodes || [];
      },
      error() {
        this.hasError = true;
      },
    },
    // Connected (external) agents never appear in the catalog, so they come
    // from the metrics registry instead. It returns [] for INTERNAL_DAP.
    connectedAgents: {
      query: getConnectedAgentsQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          limit: DISPLAY_LIMIT,
          agentClass: this.agentClass,
        };
      },
      skip() {
        return this.agentClass === AGENT_CLASS_INTERNAL_DAP;
      },
      update(data) {
        this.hasError = false;
        return (data.project ?? data.group)?.aiGovernanceMetrics?.connectedAgents || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      configuredItems: [],
      connectedAgents: [],
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      // Base this on projectId, since that is what the query variables use to
      // build the ProjectID; keeps the mode decision and the query consistent.
      return Boolean(this.projectId);
    },
    loading() {
      return (
        this.$apollo.queries.configuredItems.loading || this.$apollo.queries.connectedAgents.loading
      );
    },
    catalogRows() {
      // Already ordered by usage and limited by the backend; render as-is.
      return (this.configuredItems || [])
        .filter((node) => node.item)
        .map((node) => ({
          id: node.id,
          icon: 'tanuki-ai',
          name: node.item.name,
          // Project disambiguates same-named agents across projects; fall back
          // to the description when a project is not available.
          subtitle: node.item.project?.nameWithNamespace || node.item.description || '',
        }));
    },
    connectedRows() {
      return (this.connectedAgents || []).map((node) => ({
        id: `connected-${node.agentType}`,
        icon: 'connected',
        name: node.agentType,
        subtitle: [
          n__('AiGovernance|%d machine', 'AiGovernance|%d machines', node.activeCount),
          n__('AiGovernance|%d user', 'AiGovernance|%d users', node.userCount),
        ].join(' · '),
      }));
    },
    // Reading off the computed rows rather than the raw query results keeps a
    // skipped query's stale data out of the card after the class changes.
    agents() {
      if (this.agentClass === AGENT_CLASS_INTERNAL_DAP) {
        return this.catalogRows.slice(0, DISPLAY_LIMIT);
      }

      if (this.agentClass === AGENT_CLASS_EXTERNAL) {
        return this.connectedRows.slice(0, DISPLAY_LIMIT);
      }

      // There are only ever a handful of connected agent types, so listing
      // them first still leaves room for the catalog agents.
      return [...this.connectedRows, ...this.catalogRows].slice(0, DISPLAY_LIMIT);
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.agents.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load agent inventory.') : '';
    },
    viewAllHref() {
      const namespacePath = this.isProjectMode
        ? this.projectFullPath
        : joinPaths('groups', this.groupFullPath);

      return joinPaths('/', namespacePath, '-', 'automate', 'agents');
    },
  },
  i18n: {
    title: s__('AiGovernance|AI agent inventory'),
    viewAll: s__('AiGovernance|View all agents'),
    empty: s__('AiGovernance|No agents configured yet.'),
    footnote: s__('AiGovernance|Usage rankings are always based on the last 30 days.'),
  },
};
</script>

<template>
  <dashboard-list-card
    :title="$options.i18n.title"
    :view-all-text="$options.i18n.viewAll"
    :view-all-href="viewAllHref"
    :loading="loading"
    :error-text="errorText"
    :is-empty="isEmpty"
    :empty-text="$options.i18n.empty"
    :footnote="$options.i18n.footnote"
  >
    <li
      v-for="agent in agents"
      :key="agent.id"
      class="gl-border-b gl-flex gl-items-center gl-gap-3 gl-border-section gl-p-4 last:gl-border-b-0"
      data-testid="agent-inventory-row"
    >
      <gl-icon :name="agent.icon" class="gl-shrink-0 gl-text-subtle" />
      <span class="gl-min-w-0">
        <span class="gl-block gl-truncate gl-font-bold" data-testid="agent-name">{{
          agent.name
        }}</span>
        <span class="gl-block gl-truncate gl-text-sm gl-text-subtle">{{ agent.subtitle }}</span>
      </span>
    </li>
  </dashboard-list-card>
</template>
