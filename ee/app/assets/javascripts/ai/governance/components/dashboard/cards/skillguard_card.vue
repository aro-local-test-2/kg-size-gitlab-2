<script>
import { GlBadge, GlIcon, GlLink } from '@gitlab/ui';
import { s__, n__, sprintf, formatNumber } from '~/locale';
import { groupSecurityVulnerabilitiesPath } from 'ee/lib/utils/path_helpers/group';
import { projectSecurityVulnerabilityReportIndexPath } from 'ee/lib/utils/path_helpers/project';
import getSkillguardSummaryQuery from 'ee/ai/governance/graphql/queries/get_skillguard_summary.query.graphql';
import {
  SKILLGUARD_SCANNER_ID,
  SKILLGUARD_IDENTIFIER_NAME,
  SKILLGUARD_SEVERITIES,
  SKILLGUARD_VERDICT_LABELS,
} from 'ee/ai/governance/constants';
import DashboardListCard from './dashboard_list_card.vue';

const ROW_LIMIT = 5;

export default {
  name: 'SkillguardCard',
  components: {
    DashboardListCard,
    GlBadge,
    GlIcon,
    GlLink,
  },
  inject: {
    projectId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  apollo: {
    skillguard: {
      query: getSkillguardSummaryQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          scanner: [SKILLGUARD_SCANNER_ID],
          limit: ROW_LIMIT,
        };
      },
      update(data) {
        const namespace = this.isProjectMode ? data.project : data.group;

        return {
          counts: namespace?.vulnerabilitySeveritiesCount || {},
          skills: namespace?.vulnerabilities?.nodes || [],
        };
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      skillguard: { counts: {}, skills: [] },
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectId);
    },
    loading() {
      return this.$apollo.queries.skillguard.loading;
    },
    // Present severities only, so the bar has no zero-width segment.
    presentSeverities() {
      return SKILLGUARD_SEVERITIES.map((key) => ({
        key,
        count: this.skillguard.counts?.[key] || 0,
      })).filter(({ count }) => count > 0);
    },
    totalFlagged() {
      return this.presentSeverities.reduce((sum, { count }) => sum + count, 0);
    },
    // Share of the flagged total, not of all skills scanned: safe skills are never
    // published as findings, so no scanned denominator exists.
    riskBarSegments() {
      return this.presentSeverities.map(({ key, count }) => ({
        key,
        style: { width: `${(count / this.totalFlagged) * 100}%` },
      }));
    },
    countsLabel() {
      return this.presentSeverities
        .map(({ key, count }) =>
          sprintf(this.$options.i18n.verdictCount, {
            count: formatNumber(count),
            verdict: SKILLGUARD_VERDICT_LABELS[key] || key,
          }),
        )
        .join(' · ');
    },
    totalLabel() {
      return sprintf(
        n__(
          'AiGovernance|%{count} flagged skill',
          'AiGovernance|%{count} flagged skills',
          this.totalFlagged,
        ),
        { count: formatNumber(this.totalFlagged) },
      );
    },
    skills() {
      return this.skillguard.skills.map((skill) => ({
        id: skill.id,
        name: skill.title,
        // Nullable on VulnerabilityType; avoids a `severity-undefined` icon and class.
        severity: skill.severity?.toLowerCase() || 'unknown',
        severityLabel:
          SKILLGUARD_VERDICT_LABELS[skill.severity?.toLowerCase() || 'unknown'] ||
          skill.severity?.toLowerCase() ||
          'unknown',
        projectName: skill.project?.name || '',
        href: skill.vulnerabilityPath,
      }));
    },
    // The filtered search seeds each token from a query param named after it. The
    // scopes differ in route and available token: group has no scanner token, so
    // `?scanner=` would be silently dropped there and it filters by identifier.
    viewAllHref() {
      const [path, query] = this.isProjectMode
        ? [
            projectSecurityVulnerabilityReportIndexPath(this.projectFullPath),
            { scanner: SKILLGUARD_SCANNER_ID },
          ]
        : [
            groupSecurityVulnerabilitiesPath(this.groupFullPath),
            { identifier: SKILLGUARD_IDENTIFIER_NAME },
          ];

      return `${path}?${new URLSearchParams(query).toString()}`;
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.skills.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load SkillGuard results.') : '';
    },
  },
  i18n: {
    title: s__('AiGovernance|Most risky skills'),
    scanner: s__('AiGovernance|SkillGuard'),
    viewAll: s__('AiGovernance|View all skills'),
    empty: s__('AiGovernance|No skills have been flagged by SkillGuard.'),
    verdictCount: s__('AiGovernance|%{count} %{verdict}'),
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
  >
    <template #title-badge>
      <gl-badge>{{ $options.i18n.scanner }}</gl-badge>
    </template>

    <li class="gl-border-b gl-border-section gl-p-4" data-testid="skillguard-summary">
      <div class="gl-flex gl-h-3 gl-overflow-hidden gl-rounded-pill gl-bg-strong">
        <div
          v-for="segment in riskBarSegments"
          :key="segment.key"
          :class="`severity-bg-${segment.key}`"
          :style="segment.style"
          :data-testid="`risk-bar-${segment.key}`"
        ></div>
      </div>
      <div class="gl-mt-3 gl-flex gl-items-center gl-justify-between gl-gap-3 gl-text-sm">
        <span data-testid="severity-counts">{{ countsLabel }}</span>
        <span class="gl-shrink-0 gl-text-subtle" data-testid="total-flagged">{{ totalLabel }}</span>
      </div>
    </li>

    <li
      v-for="skill in skills"
      :key="skill.id"
      class="gl-border-b gl-border-section last:gl-border-b-0"
    >
      <gl-link
        :href="skill.href"
        class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-p-4 gl-text-default hover:gl-bg-strong hover:gl-no-underline"
        data-testid="skillguard-row"
      >
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <gl-icon
            :name="`severity-${skill.severity}`"
            :size="12"
            :class="`gl-shrink-0 severity-text-${skill.severity}`"
            :aria-label="skill.severityLabel"
            data-testid="skill-severity-icon"
          />
          <span class="gl-truncate gl-font-bold" data-testid="skill-name">{{ skill.name }}</span>
        </span>
        <span class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
          <span data-testid="skill-project">{{ skill.projectName }}</span>
          <gl-icon name="chevron-right" />
        </span>
      </gl-link>
    </li>
  </dashboard-list-card>
</template>
