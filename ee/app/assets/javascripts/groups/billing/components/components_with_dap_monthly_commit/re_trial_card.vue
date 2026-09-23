<script>
import { GlButton, GlIcon } from '@gitlab/ui';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import { InternalEvents } from '~/tracking';
import { __, s__ } from '~/locale';

export default {
  name: 'ReTrialCard',
  components: {
    GlButton,
    GlIcon,
    UserGroupCalloutDismisser,
  },
  mixins: [InternalEvents.mixin()],
  inject: {
    eligibleForRetrial: {
      default: false,
    },
    canStartTrial: {
      default: false,
    },
    trialActive: {
      default: false,
    },
    retrialCardDismissed: {
      default: false,
    },
    retrialCardFeatureName: {
      default: '',
    },
    groupId: {
      default: null,
    },
    startTrialPath: {
      default: '',
    },
  },
  computed: {
    shouldRender() {
      return (
        this.eligibleForRetrial &&
        this.canStartTrial &&
        !this.trialActive &&
        !this.retrialCardDismissed
      );
    },
    benefits() {
      return [
        s__('BillingPlans|Advanced security & compliance'),
        s__('BillingPlans|GitLab Duo Agent Platform'),
        s__('BillingPlans|Higher compute & seat limits'),
      ];
    },
    dismissLabel() {
      return __('Dismiss');
    },
  },
  methods: {
    handleDismiss(dismiss) {
      this.trackEvent('dismiss_retrial_card_group_billing');
      dismiss();
    },
  },
};
</script>

<template>
  <user-group-callout-dismisser
    v-if="shouldRender"
    :feature-name="retrialCardFeatureName"
    :group-id="groupId"
    skip-query
  >
    <template #default="{ dismiss, shouldShowCallout }">
      <div
        v-if="shouldShowCallout"
        class="gl-border gl-relative gl-mt-6 gl-rounded-xl gl-bg-subtle gl-p-5"
        data-testid="re-trial-card"
      >
        <div class="gl-flex gl-flex-col gl-gap-5">
          <div class="gl-flex gl-flex-col gl-gap-3">
            <h3 class="gl-heading-3 gl-mb-0">
              {{ s__('BillingPlans|Start a GitLab Ultimate trial') }}
            </h3>

            <p class="gl-mb-0 gl-text-subtle">
              {{
                s__(
                  'BillingPlans|Try everything GitLab Ultimate offers for your group. Free for 30 days, no credit card required.',
                )
              }}
            </p>
          </div>

          <ul class="gl-mb-0 gl-flex gl-list-none gl-flex-wrap gl-gap-x-11 gl-gap-y-3 gl-pl-0">
            <li v-for="benefit in benefits" :key="benefit" class="gl-flex gl-items-center gl-gap-2">
              <gl-icon name="check" variant="info" />
              <span>{{ benefit }}</span>
            </li>
          </ul>

          <gl-button
            class="gl-self-start"
            :href="startTrialPath"
            referrerpolicy="no-referrer-when-downgrade"
            data-event-tracking="click_start_trial_on_retrial_card_group_billing"
            data-testid="re-trial-card-cta"
            >{{ s__('BillingPlans|Start a free trial') }}</gl-button
          >
        </div>

        <gl-button
          class="gl-absolute gl-right-3 gl-top-3"
          category="tertiary"
          icon="close"
          :aria-label="dismissLabel"
          data-testid="re-trial-card-dismiss"
          @click="handleDismiss(dismiss)"
        />
      </div>
    </template>
  </user-group-callout-dismisser>
</template>
