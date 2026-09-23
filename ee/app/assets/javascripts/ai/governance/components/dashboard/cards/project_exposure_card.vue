<script>
import { GlIcon, GlLink } from '@gitlab/ui';
import { s__, n__ } from '~/locale';
import getProjectExposureQuery from 'ee/ai/governance/graphql/queries/get_project_exposure.query.graphql';
import { AGENT_CLASS_ALL, TIMEFRAME_LAST_SEVEN_DAYS } from 'ee/ai/governance/constants';
import DashboardListCard from './dashboard_list_card.vue';

const LIMIT = 5;

export default {
  name: 'ProjectExposureCard',
  components: {
    DashboardListCard,
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
    topProjects: {
      query: getProjectExposureQuery,
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
        return (data.project ?? data.group)?.aiGovernanceMetrics?.topProjects || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      topProjects: [],
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    loading() {
      return this.$apollo.queries.topProjects.loading;
    },
    projects() {
      // AiGovernanceProjectActivity.project is nullable (user can't read the
      // project), so skip entries we can't resolve rather than throwing.
      return (this.topProjects || [])
        .filter((node) => node.project)
        .map((node) => ({
          id: node.project.id,
          name: node.project.name,
          sessions: n__('AiGovernance|%d session', 'AiGovernance|%d sessions', node.sessionCount),
          // Deep-links to the Audit events tab with the "Project" filter set
          // (the filtered search seeds itself from this param).
          href: `?tab=agent-artifacts&projectPath=${encodeURIComponent(node.project.fullPath)}`,
        }));
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.projects.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load project exposure.') : '';
    },
  },
  i18n: {
    title: s__('AiGovernance|Project exposure'),
    viewAll: s__('AiGovernance|View all projects'),
    empty: s__('AiGovernance|No recent project exposure.'),
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
      v-for="project in projects"
      :key="project.id"
      class="gl-border-b gl-border-section last:gl-border-b-0"
    >
      <gl-link
        :href="project.href"
        class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-p-4 gl-text-default hover:gl-bg-strong hover:gl-no-underline"
        data-testid="project-exposure-row"
      >
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <gl-icon name="project" class="gl-shrink-0 gl-text-subtle" />
          <span class="gl-truncate gl-font-bold">{{ project.name }}</span>
        </span>
        <span class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
          {{ project.sessions }}
          <gl-icon name="chevron-right" />
        </span>
      </gl-link>
    </li>
  </dashboard-list-card>
</template>
