<script>
import { GlButton, GlLoadingIcon, GlTooltipDirective } from '@gitlab/ui';
import getCloudConnectorHealthStatus from 'ee/usage_quotas/add_on/graphql/cloud_connector_health_check.query.graphql';
import { fetchPolicies } from '~/lib/graphql';
import { __, s__ } from '~/locale';
import HealthCheckCard from 'ee/vue_shared/components/health_check_card.vue';
import { probesByCategory } from '../utils';
import HealthCheckListCategory from './health_check_list_category.vue';
import HealthCheckListLoader from './health_check_list_loader.vue';

export default {
  name: 'HealthCheckList',
  components: {
    GlButton,
    GlLoadingIcon,
    HealthCheckListLoader,
    HealthCheckListCategory,
    HealthCheckCard,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  data() {
    return {
      healthStatus: null,
      probes: [],
      isLoading: true,
      expanded: false,
    };
  },
  computed: {
    healthCheckUI() {
      if (this.isLoading) {
        return {
          title: this.$options.i18n.updating,
          icon: 'status-health',
          variant: 'disabled',
        };
      }

      if (this.healthStatus) {
        return {
          title: this.$options.i18n.noHealthProblems,
          icon: 'check-circle-filled',
          variant: 'success',
        };
      }

      return {
        title: this.$options.i18n.problemsWithSetup,
        icon: 'error',
        variant: 'danger',
      };
    },
    probesByCategory() {
      return probesByCategory(this.probes);
    },

    healthStatusText() {
      return this.healthStatus
        ? this.$options.i18n.healthCheckSucceeded
        : this.$options.i18n.healthCheckFailed;
    },
    expandText() {
      if (this.isLoading) {
        return this.$options.i18n.loadingTests;
      }

      return this.expanded ? this.$options.i18n.hideResults : this.healthStatusText;
    },
  },
  created() {
    this.runHealthCheck();
  },
  methods: {
    toggleExpanded() {
      this.expanded = !this.expanded;
    },
    onRunHealthCheckClick() {
      this.expanded = true;

      this.runHealthCheck();
    },
    async runHealthCheck() {
      this.probes = [];
      this.isLoading = true;
      try {
        const { data } = await this.$apollo.query({
          query: getCloudConnectorHealthStatus,
          fetchPolicy: fetchPolicies.NETWORK_ONLY,
        });
        this.healthStatus = data?.cloudConnectorStatus?.success || false;
        this.probes = data?.cloudConnectorStatus?.probeResults || [];
      } catch (error) {
        this.healthStatus = false;
        this.probes = [];
      } finally {
        this.isLoading = false;
      }
    },
    downloadReport() {
      const cleanedProbes = this.probes.map(({ __typename, ...probe }) => probe);
      const reportData = JSON.stringify(cleanedProbes, null, 2);
      const blob = new Blob([reportData], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'health_check_report.json';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    },
  },
  i18n: {
    healthCheckSucceeded: s__('CodeSuggestions|GitLab Duo should be operational.'),
    healthCheckFailed: s__('CodeSuggestions|Not operational. Resolve issues to use GitLab Duo.'),
    loadingTests: s__('CodeSuggestions|Tests are running'),
    runHealthCheck: s__('CodeSuggestions|Run health check'),
    hideResults: __('Hide results'),
    updating: s__('CodeSuggestions|Updating…'),
    noHealthProblems: s__('CodeSuggestions|No health problems detected'),
    problemsWithSetup: s__('CodeSuggestions|Problems detected with setup'),
    downloadReport: s__('CodeSuggestions|Download Report'),
  },
};
</script>
<template>
  <health-check-card
    :title="healthCheckUI.title"
    :icon="healthCheckUI.icon"
    :icon-variant="healthCheckUI.variant"
    :title-muted="isLoading"
    :expanded="expanded"
    content-id="health-check-results"
    data-testid="health-check-card"
    @toggle="toggleExpanded"
  >
    <template #actions>
      <gl-button
        class="gl-w-full @sm/panel:gl-w-auto sm:-gl-my-2"
        :loading="isLoading"
        :disabled="isLoading"
        data-testid="run-health-check-button"
        @click="onRunHealthCheckClick"
        >{{ $options.i18n.runHealthCheck }}</gl-button
      >

      <gl-button
        class="has-tooltip gl-w-full @sm/panel:gl-w-auto"
        :disabled="isLoading"
        category="secondary"
        icon="download"
        :aria-label="$options.i18n.downloadReport"
        :title="$options.i18n.downloadReport"
        data-testid="download-report-button"
        @click="downloadReport"
      />
    </template>

    <template #expand-text>{{ expandText }}</template>

    <div class="gl-p-5">
      <health-check-list-loader v-if="isLoading" />
      <div v-else class="gl-font-monospace" data-testid="health-check-results">
        <health-check-list-category
          v-for="category in probesByCategory"
          :key="category.title"
          :category="category"
        />
      </div>
    </div>

    <template #footer>
      <gl-loading-icon v-if="isLoading" size="sm" class="gl-text-left" />
      <p v-else class="gl-mb-0" data-testid="health-check-footer-text">{{ healthStatusText }}</p>
    </template>
  </health-check-card>
</template>
