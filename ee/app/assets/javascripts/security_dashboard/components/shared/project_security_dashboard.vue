<script>
import { GlDashboardLayout } from '@gitlab/ui';
import { markRaw } from 'vue';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { setUrlParams, updateHistory } from '~/lib/utils/url_utility';
import { generateVulnerabilitiesForSeverityPanels } from 'ee/security_dashboard/utils/chart_generators';
import {
  SINGLE_SELECT_TRACKED_REF_TOKEN_DEFINITION,
  REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION,
} from './filtered_search/tokens/constants';
import FilteredSearch from './filtered_search/filtered_search.vue';
import VulnerabilitiesOverTimePanel from './vulnerabilities_over_time_panel.vue';
import ProjectRiskScorePanel from './project_risk_score_panel.vue';
import VulnerabilitiesByAgePanel from './vulnerabilities_by_age_panel.vue';
import VulnerabilitiesByIdentifierPanel from './vulnerabilities_by_identifier_panel.vue';
import AgenticAdoptionFunnelPanel from './agentic_adoption_funnel_panel.vue';
import MttrOverTimePanel from './mttr_over_time_panel.vue';
import SecurityDashboardDescription from './security_dashboard_description.vue';
import PdfExportButton from './pdf_export_button.vue';

export default {
  name: 'ProjectSecurityDashboard',
  components: {
    GlDashboardLayout,
    SecurityDashboardDescription,
    FilteredSearch,
    PdfExportButton,
    ProjectRiskScorePanel,
    VulnerabilitiesByAgePanel,
    VulnerabilitiesByIdentifierPanel,
  },
  mixins: [glFeatureFlagMixin()],
  inject: {
    defaultBranchContext: {
      default: () => null,
    },
  },
  data() {
    return {
      filters: {},
    };
  },
  computed: {
    filteredSearchTokens() {
      const tokens = [REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION];

      if (this.defaultBranchContext && this.glFeatures?.vulnerabilitiesAcrossContexts) {
        tokens.push(SINGLE_SELECT_TRACKED_REF_TOKEN_DEFINITION);
      }

      return tokens;
    },
    dashboard() {
      const showMttr = Boolean(this.glFeatures?.securityDashboardMttrChart);

      return {
        panels: [
          ...generateVulnerabilitiesForSeverityPanels({
            namespace: 'project',
            filters: this.filters,
          }),
          {
            id: 'agentic-adoption-funnel',
            component: markRaw(AgenticAdoptionFunnelPanel),
            componentProps: {
              namespace: 'project',
              filters: this.filters,
            },
            gridAttributes: {
              width: 12,
              height: 2,
              yPos: 1,
              xPos: 0,
            },
          },
          {
            id: 'total-risk-score',
            component: markRaw(ProjectRiskScorePanel),
            componentProps: {
              filters: this.filters,
            },
            gridAttributes: {
              width: 5,
              height: 4,
              yPos: 3,
              xPos: 0,
            },
          },

          {
            id: 'vulnerabilities-over-time',
            component: markRaw(VulnerabilitiesOverTimePanel),
            componentProps: {
              namespace: 'project',
              filters: this.filters,
            },
            gridAttributes: {
              width: 7,
              height: 4,
              yPos: 3,
              xPos: 5,
            },
          },
          {
            id: 'vulnerabilities-by-age',
            component: markRaw(VulnerabilitiesByAgePanel),
            componentProps: {
              namespace: 'project',
              filters: this.filters,
            },
            gridAttributes: {
              width: 6,
              height: 4,
              yPos: 7,
              xPos: 0,
            },
          },
          {
            id: 'vulnerabilities-by-identifier',
            component: markRaw(VulnerabilitiesByIdentifierPanel),
            componentProps: {
              namespace: 'project',
              filters: this.filters,
            },
            gridAttributes: showMttr
              ? { width: 6, height: 4, yPos: 11, xPos: 0 }
              : { width: 6, height: 4, yPos: 7, xPos: 6 },
          },
          ...(showMttr
            ? [
                {
                  id: 'mttr-over-time',
                  component: markRaw(MttrOverTimePanel),
                  componentProps: {
                    namespace: 'project',
                    filters: this.filters,
                  },
                  gridAttributes: {
                    width: 6,
                    height: 4,
                    yPos: 7,
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
};
</script>

<template>
  <gl-dashboard-layout :config="dashboard" data-testid="project-security-dashboard">
    <template #title>
      <div class="gl-flex gl-w-full gl-items-center gl-justify-between">
        <h1 class="gl-heading-1 gl-my-0">{{ s__('SecurityReports|Security dashboard') }}</h1>
        <pdf-export-button />
      </div>
    </template>
    <template #description>
      <security-dashboard-description />
    </template>
    <template #filters>
      <filtered-search
        :tokens="filteredSearchTokens"
        @filters-changed="updateFilters"
        @url-params-changed="updateUrlParams"
      />
    </template>
    <template #panel="{ panel }">
      <component :is="panel.component" v-bind="panel.componentProps" />
    </template>
  </gl-dashboard-layout>
</template>
