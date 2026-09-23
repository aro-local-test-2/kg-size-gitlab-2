<script>
import { GlAvatar, GlIcon, GlLink } from '@gitlab/ui';
import { s__, n__ } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import getDeveloperActivityQuery from 'ee/ai/governance/graphql/queries/get_developer_activity.query.graphql';
import { AGENT_CLASS_ALL, TIMEFRAME_LAST_SEVEN_DAYS } from 'ee/ai/governance/constants';
import DashboardListCard from './dashboard_list_card.vue';

const LIMIT = 5;

export default {
  name: 'DeveloperActivityCard',
  components: {
    DashboardListCard,
    GlAvatar,
    GlIcon,
    GlLink,
  },
  inject: {
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  props: {
    agentClass: {
      type: String,
      required: false,
      default: AGENT_CLASS_ALL,
    },
    timeframe: {
      type: String,
      required: false,
      default: TIMEFRAME_LAST_SEVEN_DAYS,
    },
  },
  apollo: {
    topUsers: {
      query: getDeveloperActivityQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          limit: LIMIT,
          agentClass: this.agentClass,
          timeframe: this.timeframe,
        };
      },
      update(data) {
        return (data.project ?? data.group)?.aiGovernanceMetrics?.topUsers || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      topUsers: [],
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    loading() {
      return this.$apollo.queries.topUsers.loading;
    },
    users() {
      // AiGovernanceUserActivity.user is nullable (deleted/inaccessible user),
      // so skip entries we can't resolve rather than throwing on node.user.
      return (this.topUsers || [])
        .filter((node) => node.user)
        .map((node) => ({
          id: node.user.id,
          entityId: getIdFromGraphQLId(node.user.id),
          name: node.user.name,
          sessions: n__('AiGovernance|%d session', 'AiGovernance|%d sessions', node.sessionCount),
          // Deep-links to the Audit events tab with the "Triggered by" filter set
          // (the filtered search seeds itself from this param).
          href: `?tab=agent-artifacts&triggeredByUserId=${encodeURIComponent(node.user.id)}`,
        }));
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.users.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load developer activity.') : '';
    },
  },
  i18n: {
    title: s__('AiGovernance|Developer activity'),
    viewAll: s__('AiGovernance|View all users'),
    empty: s__('AiGovernance|No recent developer activity.'),
  },
  viewAllHref: '?tab=agent-artifacts',
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
  >
    <li
      v-for="user in users"
      :key="user.id"
      class="gl-border-b gl-border-section last:gl-border-b-0"
    >
      <gl-link
        :href="user.href"
        class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-p-4 gl-text-default hover:gl-bg-strong hover:gl-no-underline"
        data-testid="developer-activity-row"
      >
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <gl-avatar :entity-id="user.entityId" :entity-name="user.name" :size="24" />
          <span class="gl-truncate gl-font-bold">{{ user.name }}</span>
        </span>
        <span class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
          {{ user.sessions }}
          <gl-icon name="chevron-right" />
        </span>
      </gl-link>
    </li>
  </dashboard-list-card>
</template>
