<script>
import { GlButton } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { n__, s__ } from '~/locale';
import DuoReadinessRow from '~/pages/projects/shared/permissions/components/duo_readiness_row.vue';
import {
  STATUS_DONE,
  STATUS_TODO,
  STATUS_ERROR,
  STATUS_LOADING,
} from '~/pages/projects/shared/permissions/constants';
import duoMcpServersCountQuery from '../graphql/duo_mcp_servers_count.query.graphql';

export default {
  name: 'DuoMcpRow',
  components: { GlButton, DuoReadinessRow },
  props: {
    mcp: {
      type: Object,
      required: true,
    },
    projectFullPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      serversCount: null,
      loadFailed: false,
    };
  },
  apollo: {
    serversCount: {
      query: duoMcpServersCountQuery,
      variables() {
        return { fullPath: this.projectFullPath };
      },
      update(data) {
        return data.project?.duoMcpServersCount ?? null;
      },
      error() {
        this.loadFailed = true;
      },
    },
  },
  computed: {
    loading() {
      return this.$apollo.queries.serversCount.loading;
    },
    // A null count inside a successful response means the field was redacted by
    // authorization, so it reads as a failed check rather than as zero servers.
    errored() {
      return !this.loading && (this.loadFailed || this.serversCount === null);
    },
    connected() {
      return this.serversCount > 0;
    },
    status() {
      if (this.loading) return STATUS_LOADING;
      if (this.errored) return STATUS_ERROR;

      return this.connected ? STATUS_DONE : STATUS_TODO;
    },
    description() {
      if (this.loading || this.errored || !this.connected) {
        return this.$options.descriptions[this.status];
      }

      return n__(
        'DuoAgentPlatform|%d MCP server is connected. Agents can use it in this project.',
        'DuoAgentPlatform|%d MCP servers are connected. Agents can use them in this project.',
        this.serversCount,
      );
    },
  },
  methods: {
    retry() {
      this.loadFailed = false;
      this.$apollo.queries.serversCount.refetch();
    },
  },
  docsPath: helpPagePath('user/gitlab_duo/model_context_protocol/ai_catalog_mcp_servers.md'),
  descriptions: {
    [STATUS_LOADING]: s__('DuoAgentPlatform|Checking connected MCP servers.'),
    [STATUS_ERROR]: s__('DuoAgentPlatform|Could not check for connected MCP servers.'),
    [STATUS_TODO]: s__(
      'DuoAgentPlatform|Experiment. Agents can connect to tools your team already uses, such as Jira or Linear.',
    ),
  },
  i18n: {
    title: s__('DuoAgentPlatform|MCP servers'),
    viewServers: s__('DuoAgentPlatform|View servers'),
    howToConnect: s__('DuoAgentPlatform|How to connect'),
    checkAgain: s__('DuoAgentPlatform|Check again'),
  },
};
</script>

<template>
  <duo-readiness-row
    :title="$options.i18n.title"
    :description="description"
    :status="status"
    data-testid="mcp-row"
  >
    <gl-button
      v-if="connected"
      category="tertiary"
      size="small"
      :href="mcp.serversPath"
      data-testid="mcp-view-servers-button"
    >
      {{ $options.i18n.viewServers }}
    </gl-button>
    <gl-button
      v-else-if="errored"
      category="secondary"
      size="small"
      icon="retry"
      data-testid="mcp-retry-button"
      @click="retry"
    >
      {{ $options.i18n.checkAgain }}
    </gl-button>
    <gl-button
      v-else
      category="secondary"
      size="small"
      icon="external-link"
      :href="$options.docsPath"
      target="_blank"
      :disabled="loading"
      data-testid="mcp-how-to-connect-button"
    >
      {{ $options.i18n.howToConnect }}
    </gl-button>
  </duo-readiness-row>
</template>
