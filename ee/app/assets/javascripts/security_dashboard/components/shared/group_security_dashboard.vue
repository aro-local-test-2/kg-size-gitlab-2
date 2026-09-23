<script>
import { markRaw } from 'vue';
import { GlDashboardLayout } from '@gitlab/ui';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { setUrlParams, updateHistory } from '~/lib/utils/url_utility';
import { generateVulnerabilitiesForSeverityPanels } from 'ee/security_dashboard/utils/chart_generators';
import getSecurityCategoriesAndAttributes from 'ee/security_configuration/graphql/group_security_categories_and_attributes.query.graphql';
import { getAttributeCategoryTokens } from 'ee/security_dashboard/utils/attribute_utils';
import {
  PROJECT_TOKEN_DEFINITION,
  REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION,
} from './filtered_search/tokens/constants';
import FilteredSearch from './filtered_search/filtered_search.vue';
import VulnerabilitiesOverTimePanel from './vulnerabilities_over_time_panel.vue';
import RiskScorePanel from './risk_score_panel.vue';
import VulnerabilitiesByAgePanel from './vulnerabilities_by_age_panel.vue';
import VulnerabilitiesByIdentifierPanel from './vulnerabilities_by_identifier_panel.vue';
import AgenticAdoptionFunnelPanel from './agentic_adoption_funnel_panel.vue';
import MttrOverTimePanel from './mttr_over_time_panel.vue';
import SecurityDashboardDescription from './security_dashboard_description.vue';
import PdfExportButton from './pdf_export_button.vue';

export default {
  name: 'GroupSecurityDashboard',
  components: {
    GlDashboardLayout,
    SecurityDashboardDescription,
    FilteredSearch,
    PdfExportButton,
  },
  mixins: [glFeatureFlagMixin()],
  inject: ['groupFullPath'],
  data() {
    return {
      filters: {},
      securityCategories: [],
    };
  },
  apollo: {
    securityCategories: {
      query: getSecurityCategoriesAndAttributes,
      variables() {
        return {
          fullPath: this.groupFullPath,
        };
      },
      update: (data) => data?.group?.securityCategories,
      error() {
        createAlert({ message: s__('SecurityReports|Failed to load Security attributes.') });
      },
    },
  },
  computed: {
    dashboard() {
      const showMttr = Boolean(this.glFeatures?.securityDashboardMttrChart);

      return {
        panels: [
          ...generateVulnerabilitiesForSeverityPanels({
            namespace: 'group',
            filters: this.filters,
          }),
          {
            id: 'agentic-adoption-funnel',
            component: markRaw(AgenticAdoptionFunnelPanel),
            componentProps: {
              namespace: 'group',
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
            id: 'risk-score',
            component: markRaw(RiskScorePanel),
            componentProps: {
              namespace: 'group',
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
              namespace: 'group',
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
              namespace: 'group',
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
              namespace: 'group',
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
                    namespace: 'group',
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
    tokens() {
      return [
        ...this.$options.staticTokens,
        ...getAttributeCategoryTokens(this.securityCategories),
      ];
    },
    isLoading() {
      return this.$apollo.queries.securityCategories?.loading;
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
  <gl-dashboard-layout :config="dashboard" data-testid="group-security-dashboard">
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
        v-if="!isLoading"
        :tokens="tokens"
        @filters-changed="updateFilters"
        @url-params-changed="updateUrlParams"
      />
    </template>
    <template #panel="{ panel }">
      <component :is="panel.component" v-if="!isLoading" v-bind="panel.componentProps" />
    </template>
  </gl-dashboard-layout>
</template>
