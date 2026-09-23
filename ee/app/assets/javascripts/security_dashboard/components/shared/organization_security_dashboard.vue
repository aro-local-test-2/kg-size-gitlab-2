<script>
import { markRaw } from 'vue';
import { GlDashboardLayout, GlExperimentBadge } from '@gitlab/ui';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { setUrlParams, updateHistory } from '~/lib/utils/url_utility';
import { generateVulnerabilitiesForSeverityPanels } from 'ee/security_dashboard/utils/chart_generators';
import {
  PROJECT_TOKEN_DEFINITION,
  REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION,
} from './filtered_search/tokens/constants';
import FilteredSearch from './filtered_search/filtered_search.vue';
import VulnerabilitiesOverTimePanel from './vulnerabilities_over_time_panel.vue';
import RiskScorePanel from './risk_score_panel.vue';
import VulnerabilitiesByAgePanel from './vulnerabilities_by_age_panel.vue';
import VulnerabilitiesByIdentifierPanel from './vulnerabilities_by_identifier_panel.vue';
import MttrOverTimePanel from './mttr_over_time_panel.vue';
import SecurityDashboardDescription from './security_dashboard_description.vue';

const NAMESPACE = 'organization';

export default {
  name: 'OrganizationSecurityDashboard',
  components: {
    GlExperimentBadge,
    GlDashboardLayout,
    SecurityDashboardDescription,
    FilteredSearch,
  },
  mixins: [glFeatureFlagMixin()],
  data() {
    return {
      filters: {},
    };
  },
  computed: {
    dashboard() {
      const showMttr = Boolean(this.glFeatures?.securityDashboardMttrChart);

      return {
        panels: [
          ...generateVulnerabilitiesForSeverityPanels({
            namespace: NAMESPACE,
            filters: this.filters,
          }),
          {
            id: 'risk-score',
            component: markRaw(RiskScorePanel),
            componentProps: {
              namespace: NAMESPACE,
              filters: this.filters,
            },
            gridAttributes: {
              width: 5,
              height: 4,
              yPos: 1,
              xPos: 0,
            },
          },
          {
            id: 'vulnerabilities-over-time',
            component: markRaw(VulnerabilitiesOverTimePanel),
            componentProps: {
              namespace: NAMESPACE,
              filters: this.filters,
            },
            gridAttributes: {
              width: 7,
              height: 4,
              yPos: 1,
              xPos: 5,
            },
          },
          {
            id: 'vulnerabilities-by-age',
            component: markRaw(VulnerabilitiesByAgePanel),
            componentProps: {
              namespace: NAMESPACE,
              filters: this.filters,
            },
            gridAttributes: {
              width: 6,
              height: 4,
              yPos: 5,
              xPos: 0,
            },
          },
          {
            id: 'vulnerabilities-by-identifier',
            component: markRaw(VulnerabilitiesByIdentifierPanel),
            componentProps: {
              namespace: NAMESPACE,
              filters: this.filters,
            },
            gridAttributes: showMttr
              ? { width: 6, height: 4, yPos: 9, xPos: 0 }
              : { width: 6, height: 4, yPos: 5, xPos: 6 },
          },
          ...(showMttr
            ? [
                {
                  id: 'mttr-over-time',
                  component: markRaw(MttrOverTimePanel),
                  componentProps: {
                    namespace: NAMESPACE,
                    filters: this.filters,
                  },
                  gridAttributes: {
                    width: 6,
                    height: 4,
                    yPos: 5,
                    xPos: 6,
                  },
                },
              ]
            : []),
        ],
      };
    },
  },
  methods: {
    updateFilters(newFilters) {
      this.filters = newFilters;
    },
    updateUrlParams(params) {
      const url = setUrlParams(params, { url: window.location.href, decodeParams: true });
      if (url !== window.location.href) {
        updateHistory({ url, replace: true });
      }
    },
  },
  staticTokens: [PROJECT_TOKEN_DEFINITION, REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION],
};
</script>

<template>
  <gl-dashboard-layout :config="dashboard" data-testid="organization-security-dashboard">
    <template #title>
      <div class="gl-flex gl-items-center">
        <h1 class="gl-heading-1 gl-my-0">
          {{ s__('SecurityReports|Security dashboard') }}
        </h1>
        <gl-experiment-badge type="beta" data-testid="beta-badge" />
      </div>
    </template>
    <template #description>
      <security-dashboard-description />
    </template>
    <template #filters>
      <filtered-search
        :tokens="$options.staticTokens"
        @filters-changed="updateFilters"
        @url-params-changed="updateUrlParams"
      />
    </template>
    <template #panel="{ panel }">
      <component :is="panel.component" v-bind="panel.componentProps" />
    </template>
  </gl-dashboard-layout>
</template>
