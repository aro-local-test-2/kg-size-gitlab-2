<script>
import { GlAlert, GlBadge, GlLoadingIcon } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { sprintf, s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  GATE_LABELS,
  GATE_STATE,
  STEP_CATEGORIES,
  STEP_CATEGORY_LABELS,
  STEP_CATEGORY_LABEL_FALLBACK,
  STEP_STATE_LABELS,
  STEP_STATE_VARIANTS,
} from 'ee/cd/constants';
import cdRolloutApprovalGatesQuery from 'ee/cd/graphql/applications/flow/cd_rollout_approval_gates.query.graphql';

export default {
  name: 'StepSidePanel',
  components: {
    GlAlert,
    GlBadge,
    GlLoadingIcon,
    DynamicPanel,
    MountingPortal,
    TimeAgo,
  },
  props: {
    rolloutId: {
      type: String,
      required: true,
    },
    step: {
      type: Object,
      required: true,
    },
  },
  emits: ['close'],
  data() {
    return {
      gates: [],
      gateLoadError: false,
    };
  },
  apollo: {
    gates: {
      query: cdRolloutApprovalGatesQuery,
      variables() {
        return { id: this.rolloutId };
      },
      skip() {
        return !this.isApproval;
      },
      update: (data) => data?.organization?.cdRollout?.gates ?? [],
      error(error) {
        this.gateLoadError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isDeploy() {
      return this.step.category === STEP_CATEGORIES.DEPLOY;
    },
    isApproval() {
      return this.step.category === STEP_CATEGORIES.APPROVE;
    },
    isTrigger() {
      return this.step.category === STEP_CATEGORIES.TRIGGER;
    },
    heading() {
      if (this.isTrigger && this.step.releaseName) {
        return sprintf(
          s__('ContinuousDeployment|Release %{name}'),
          { name: this.step.releaseName },
          false,
        );
      }

      return this.step.title;
    },
    eyebrow() {
      return STEP_CATEGORY_LABELS[this.step.category] ?? STEP_CATEGORY_LABEL_FALLBACK;
    },
    stateLabel() {
      return this.isTrigger ? '' : STEP_STATE_LABELS[this.step.state];
    },
    stateVariant() {
      return STEP_STATE_VARIANTS[this.step.state];
    },
    isLoadingGates() {
      return this.$apollo.queries.gates.loading;
    },
    gate() {
      return this.gates.find(({ step }) => step?.id === this.step.id);
    },
    isGatePending() {
      return this.gate?.state === GATE_STATE.PENDING;
    },
    authorLabel() {
      if (!this.step.author) {
        return '';
      }

      return sprintf(s__('ContinuousDeployment|Bundled by @%{user}'), { user: this.step.author });
    },
    resolution() {
      if (!this.gate?.resolvedAt) {
        return '';
      }

      const user = this.gate.resolvedBy?.username;

      if (!user) {
        return GATE_LABELS[this.gate.state];
      }

      const message =
        this.gate.state === GATE_STATE.APPROVED
          ? s__('ContinuousDeployment|@%{user} approved')
          : s__('ContinuousDeployment|@%{user} rejected');

      return sprintf(message, { user }, false);
    },
  },
};
</script>

<template>
  <mounting-portal mount-to="#contextual-panel-portal" append>
    <dynamic-panel @close="$emit('close')">
      <template #header>
        <div class="gl-flex gl-w-full gl-items-center gl-justify-between gl-gap-3 gl-py-3">
          <div>
            <p
              class="gl-mb-2 gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-status-brand"
              data-testid="step-category"
            >
              {{ eyebrow }}
            </p>
            <h3 class="gl-my-0 gl-flex gl-flex-wrap gl-items-center gl-gap-2 gl-text-base">
              <span data-testid="step-title">{{ heading }}</span>
              <template v-if="step.environment">
                <span aria-hidden="true" class="gl-text-subtle">·</span>
                <span class="gl-text-sm gl-font-normal gl-text-subtle" data-testid="step-env">
                  {{ step.environment.name }}
                </span>
              </template>
            </h3>
          </div>

          <gl-badge v-if="stateLabel" :variant="stateVariant" data-testid="step-state">
            {{ stateLabel }}
          </gl-badge>
        </div>
      </template>

      <gl-alert v-if="step.error" variant="danger" :dismissible="false" data-testid="step-error">
        {{ step.error }}
      </gl-alert>

      <section v-if="isDeploy" class="gl-mt-4">
        <h4 class="gl-mb-3 gl-text-xs gl-uppercase gl-tracking-wider gl-text-subtle">
          {{ s__('ContinuousDeployment|Changed services') }}
        </h4>

        <ul
          v-if="step.services?.length"
          role="list"
          class="gl-mb-0 gl-list-none gl-pl-0"
          data-testid="changed-services-list"
        >
          <li
            v-for="name in step.services"
            :key="name"
            class="gl-mt-2 gl-font-monospace gl-text-sm first:gl-mt-0"
          >
            {{ name }}
          </li>
        </ul>

        <p v-else class="gl-mb-0 gl-text-sm gl-italic gl-text-subtle">
          {{ s__('ContinuousDeployment|No version changes in this deploy.') }}
        </p>
      </section>

      <section v-else-if="isTrigger" class="gl-mt-4">
        <p
          v-if="authorLabel"
          class="gl-mb-0 gl-text-sm gl-text-subtle"
          data-testid="release-author"
        >
          {{ authorLabel }}
        </p>
      </section>

      <section v-else-if="isApproval" class="gl-mt-4">
        <gl-alert
          v-if="gateLoadError"
          variant="danger"
          data-testid="panel-gate-load-error"
          @dismiss="gateLoadError = false"
        >
          {{ s__('ContinuousDeployment|Failed to load the approval gate. Refresh to try again.') }}
        </gl-alert>
        <gl-loading-icon v-else-if="isLoadingGates" size="sm" />

        <template v-else>
          <p v-if="resolution" class="gl-mb-0 gl-text-sm" data-testid="gate-resolution">
            {{ resolution }}
            <time-ago :time="gate.resolvedAt" class="gl-text-subtle" />
          </p>
          <p
            v-else-if="isGatePending"
            class="gl-mb-0 gl-text-sm gl-text-subtle"
            data-testid="gate-pending"
          >
            {{ s__('ContinuousDeployment|Waiting for approval.') }}
          </p>

          <p
            v-if="gate?.reason"
            class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle"
            data-testid="gate-reason"
          >
            {{ gate.reason }}
          </p>

          <p
            v-if="gate?.resolutionReason"
            class="gl-mb-0 gl-mt-2 gl-text-sm gl-italic gl-text-subtle"
            data-testid="gate-resolution-reason"
          >
            {{ gate.resolutionReason }}
          </p>
        </template>
      </section>
    </dynamic-panel>
  </mounting-portal>
</template>
