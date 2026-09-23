<script>
import { GlAlert, GlSprintf } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';

export default {
  name: 'ExploreDashboardsAlert',
  components: {
    GlAlert,
    GlSprintf,
    UserCalloutDismisser,
  },
  props: {
    exploreDashboardsPath: {
      type: String,
      required: true,
    },
  },
  calloutFeatureName: 'explore_analytics_dashboards_promo',
  // TODO: repoint once the Explore docs land, tracked in
  // https://gitlab.com/gitlab-org/gitlab/-/work_items/589513
  helpPageUrl: helpPagePath('user/analytics/analytics_dashboards'),
};
</script>

<template>
  <user-callout-dismisser :feature-name="$options.calloutFeatureName">
    <template #default="{ dismiss, shouldShowCallout }">
      <gl-alert
        v-if="shouldShowCallout"
        variant="tip"
        :title="s__('Analytics|Try analytics dashboards in Explore')"
        :primary-button-text="s__('Analytics|Go to Explore')"
        :primary-button-link="exploreDashboardsPath"
        :secondary-button-text="s__('Analytics|Learn more')"
        :secondary-button-link="$options.helpPageUrl"
        data-testid="explore-dashboards-alert"
        @dismiss="dismiss"
      >
        <gl-sprintf
          :message="
            s__(
              'Analytics|The analytics dashboards page is being rebuilt and moved to the %{boldStart}Explore%{boldEnd} page to give you visibility across your entire organization.',
            )
          "
        >
          <template #bold="{ content }">
            <strong>{{ content }}</strong>
          </template>
        </gl-sprintf>
      </gl-alert>
    </template>
  </user-callout-dismisser>
</template>
