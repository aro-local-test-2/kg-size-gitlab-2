<script>
import { GlBadge, GlPopover } from '@gitlab/ui';
import { s__ } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import getMcpServersQuery from 'ee/ai/governance/graphql/queries/get_mcp_servers.query.graphql';
import DashboardListCard from './dashboard_list_card.vue';

const LIMIT = 5;

// AiCatalogMcpServerBlockStatus GraphQL enum value for an allowed server; any
// other value (BLOCKED / BLOCKED_BY_ANCESTOR) means the server is blocked.
const STATUS_ACTIVE = 'ACTIVE';

// MCP servers are tools, not agents, so there is no agent class to segment
// them by. The card deliberately ignores the dashboard agent-class filter.
export default {
  name: 'McpServerActivityCard',
  components: {
    DashboardListCard,
    GlBadge,
    GlPopover,
  },
  inject: {
    groupFullPath: { default: '' },
    projectFullPath: { default: '' },
  },
  apollo: {
    mcpServers: {
      query: getMcpServersQuery,
      variables() {
        // Block status is scoped to the most-specific container: the project on
        // a project page, otherwise the group. Exactly one path is sent.
        const scope = this.projectFullPath
          ? { projectFullPath: this.projectFullPath, groupFullPath: null }
          : { groupFullPath: this.groupFullPath, projectFullPath: null };

        return { ...scope, first: LIMIT };
      },
      update(data) {
        this.hasError = false;
        return data.aiCatalogMcpServers?.nodes || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      mcpServers: [],
      hasError: false,
    };
  },
  computed: {
    loading() {
      return this.$apollo.queries.mcpServers.loading;
    },
    servers() {
      return (this.mcpServers || []).map((server) => {
        const authorized = server.blockStatus === STATUS_ACTIVE;

        return {
          id: server.id,
          name: server.name,
          description: server.description || '',
          descriptionId: `mcp-server-description-${getIdFromGraphQLId(server.id)}`,
          statusText: authorized ? this.$options.i18n.active : this.$options.i18n.blocked,
          statusVariant: authorized ? 'success' : 'danger',
        };
      });
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.servers.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load MCP servers.') : '';
    },
  },
  i18n: {
    title: s__('AiGovernance|MCP servers'),
    viewAll: s__('AiGovernance|View MCP registry'),
    empty: s__('AiGovernance|No MCP servers found.'),
    active: s__('AiGovernance|Active'),
    blocked: s__('AiGovernance|Blocked'),
    footnote: s__('AiGovernance|Shows the current registry, not filtered by date range.'),
  },
  viewAllHref: '?tab=mcp-registry',
};
</script>

<template>
  <dashboard-list-card
    :title="$options.i18n.title"
    :view-all-text="$options.i18n.viewAll"
    :view-all-href="$options.viewAllHref"
    :loading="loading"
    :error-text="errorText"
    :is-empty="isEmpty"
    :empty-text="$options.i18n.empty"
    :footnote="$options.i18n.footnote"
  >
    <li
      v-for="server in servers"
      :key="server.id"
      class="gl-border-b gl-flex gl-items-center gl-justify-between gl-gap-3 gl-border-section gl-p-4 last:gl-border-b-0"
      data-testid="mcp-server-row"
    >
      <span class="gl-flex gl-min-w-0 gl-flex-col">
        <span class="gl-truncate gl-font-bold">{{ server.name }}</span>
        <template v-if="server.description">
          <span
            :id="server.descriptionId"
            tabindex="0"
            class="gl-truncate gl-text-sm gl-text-subtle"
            data-testid="mcp-server-description"
          >
            {{ server.description }}
          </span>
          <gl-popover
            :target="server.descriptionId"
            :title="server.name"
            data-testid="mcp-server-description-popover"
          >
            {{ server.description }}
          </gl-popover>
        </template>
      </span>
      <gl-badge :variant="server.statusVariant" data-testid="mcp-server-status-badge">
        {{ server.statusText }}
      </gl-badge>
    </li>
  </dashboard-list-card>
</template>
