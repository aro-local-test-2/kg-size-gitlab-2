<script>
import { GlButton, GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { s__, sprintf } from '~/locale';
import FunctionalVerificationStatusBadge from './status_badge.vue';
import { FUNCTIONAL_VERIFICATION_STATUS, MODEL_PROVIDERS } from './constants';
import { getModelConfigurationPath } from './utils';

export default {
  name: 'FunctionalVerificationCheck',
  components: {
    GlButton,
    GlIcon,
    GlLink,
    GlSprintf,
    TimeAgoTooltip,
    FunctionalVerificationStatusBadge,
  },
  inject: {
    duoInstanceModelSelectionPath: { default: '' },
  },
  props: {
    name: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: true,
    },
    status: {
      type: String,
      required: true,
    },
    model: {
      type: Object,
      required: false,
      default: null,
    },
    lastRunAt: {
      type: String,
      required: false,
      default: null,
    },
    errorText: {
      type: String,
      required: false,
      default: '',
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['run'],
  computed: {
    isRunning() {
      return this.status === FUNCTIONAL_VERIFICATION_STATUS.RUNNING;
    },
    isCheckDisabled() {
      return this.disabled;
    },
    // "Run" alone is not self-describing when there are several checks.
    runAriaLabel() {
      return sprintf(s__('AiPowered|Run %{checkName} verification'), { checkName: this.name });
    },
    modelConfigurationPath() {
      return getModelConfigurationPath(this.duoInstanceModelSelectionPath);
    },
    modelText() {
      if (!this.model) {
        return '';
      }

      if (this.model.provider === MODEL_PROVIDERS.SELF_HOSTED) {
        return sprintf(s__('AiPowered|%{name} (self-hosted)'), { name: this.model.name });
      }

      if (this.model.provider === MODEL_PROVIDERS.GITLAB_MANAGED) {
        return s__('AiPowered|GitLab-managed model');
      }

      return s__('AiPowered|Disabled');
    },
  },
};
</script>

<template>
  <article class="gl-border-b gl-border-subtle">
    <div :class="{ 'gl-opacity-5': isCheckDisabled }">
      <div class="gl-flex gl-items-center gl-gap-4 gl-px-5 gl-py-4">
        <div class="gl-min-w-0 gl-grow">
          <h3 class="gl-my-1 gl-text-base gl-font-bold" data-testid="check-name">{{ name }}</h3>
          <p class="gl-mb-0 gl-text-sm gl-text-subtle">{{ description }}</p>

          <p
            v-if="modelText"
            class="gl-mb-0 gl-mt-1 gl-flex gl-flex-wrap gl-items-center gl-gap-x-2 gl-gap-y-1 gl-text-xs gl-text-subtle @sm/panel:gl-text-sm"
          >
            <gl-icon name="cloud-gear" variant="subtle" :size="12" />
            <span data-testid="check-model">{{ modelText }}</span>
            <gl-link
              v-if="modelConfigurationPath"
              :class="[
                'gl-text-xs @sm/panel:gl-text-sm',
                { 'gl-cursor-not-allowed hover:gl-cursor-not-allowed': isCheckDisabled },
              ]"
              :href="modelConfigurationPath"
              :disabled="isCheckDisabled"
            >
              {{ s__('AiPowered|Configure') }}
            </gl-link>
          </p>
        </div>

        <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-4">
          <div v-if="!isCheckDisabled" class="gl-flex gl-flex-col gl-items-end gl-gap-1">
            <functional-verification-status-badge :status="status" />
            <span v-if="lastRunAt" class="gl-text-sm gl-text-subtle">
              <gl-sprintf :message="s__('AiPowered|Last run %{timeAgo}')">
                <template #timeAgo><time-ago-tooltip :time="lastRunAt" /></template>
              </gl-sprintf>
            </span>
          </div>

          <gl-button
            size="small"
            category="secondary"
            :disabled="isCheckDisabled || isRunning"
            :aria-label="runAriaLabel"
            data-testid="run-check-button"
            @click="$emit('run')"
            >{{ s__('AiPowered|Run') }}</gl-button
          >
        </div>
      </div>

      <div
        v-if="errorText"
        class="gl-mx-5 gl-mb-4 gl-flex gl-items-start gl-gap-3 gl-rounded-base gl-bg-feedback-danger gl-px-4 gl-py-3 gl-text-sm gl-text-feedback-danger"
        data-testid="check-error"
      >
        <gl-icon name="error" variant="danger" class="gl-mt-1 gl-shrink-0" />
        <span class="gl-font-monospace">{{ errorText }}</span>
      </div>
    </div>
  </article>
</template>
