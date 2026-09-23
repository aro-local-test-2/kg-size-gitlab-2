<script>
import { defineAsyncComponent } from 'vue';
import { GlButton } from '@gitlab/ui';
import ExploreAnalyticsDashboardDetails from '~/explore/analytics_dashboards/pages/details.vue';

export default {
  name: 'ExploreAnalyticsDashboardDetailsEE',
  components: {
    ExploreAnalyticsDashboardDetails,
    GlButton,
    AnalyzeWithDuoButton: defineAsyncComponent(
      () => import('../components/analyze_with_duo_button.vue'),
    ),
  },
  computed: {
    editPath() {
      return { name: 'dashboard-edit', params: { slug: this.$route.params.slug } };
    },
  },
};
</script>
<template>
  <explore-analytics-dashboard-details>
    <template #actions="{ isSystemDashboard }">
      <gl-button
        v-if="!isSystemDashboard"
        icon="pencil"
        :to="editPath"
        data-testid="dashboard-edit-button"
      >
        {{ __('Edit') }}
      </gl-button>
    </template>
    <template
      #filter-actions="{
        namespaceFullPath,
        filters,
        panels,
        duoPrompts,
        isProject,
        isSystemDashboard,
      }"
    >
      <analyze-with-duo-button
        v-if="isSystemDashboard"
        class="gl-basis-full md:gl-basis-auto md:gl-self-end"
        :namespace-full-path="namespaceFullPath"
        :filters="filters"
        :panels="panels"
        :config-prompts="duoPrompts"
        :is-project="isProject"
      />
    </template>
  </explore-analytics-dashboard-details>
</template>
