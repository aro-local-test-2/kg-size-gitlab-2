<script>
import { GlBadge } from '@gitlab/ui';
import { getTimeago } from '~/lib/utils/datetime_utility';
import { s__, sprintf } from '~/locale';
import {
  REPOSITORY_HEALTH_STATUS_HEALTHY,
  REPOSITORY_HEALTH_STATUS_UNHEALTHY,
  REPOSITORY_HEALTH_STATUS_UNKNOWN,
} from '../../constants';

const REPOSITORY_HEALTH_STATUSES = {
  [REPOSITORY_HEALTH_STATUS_HEALTHY]: {
    label: s__('ArtifactRegistry|Healthy'),
    variant: 'success',
    icon: 'status-success',
  },
  [REPOSITORY_HEALTH_STATUS_UNHEALTHY]: {
    label: s__('ArtifactRegistry|Unhealthy'),
    variant: 'danger',
    icon: 'status-failed',
  },
  [REPOSITORY_HEALTH_STATUS_UNKNOWN]: {
    label: s__('ArtifactRegistry|Unknown'),
    variant: 'neutral',
    icon: 'severity-unknown',
  },
};

export default {
  name: 'ArtifactRegistryConnectionIndicator',
  i18n: {
    lastVerified: s__('ArtifactRegistry|Last verified: %{time}'),
    neverVerified: s__('ArtifactRegistry|Last verified: not yet checked'),
    verdictAndTime: s__('ArtifactRegistry|%{verdict}. Last verified: %{time}'),
    verdictNeverVerified: s__('ArtifactRegistry|%{verdict}. Last verified: not yet checked'),
  },
  components: {
    GlBadge,
  },
  props: {
    healthStatus: {
      type: String,
      required: true,
    },
    lastHealthCheckedAt: {
      type: String,
      required: false,
      default: null,
    },
    inline: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    layoutClasses() {
      return this.inline ? 'gl-items-center gl-gap-3' : 'gl-flex-col gl-items-start gl-gap-2';
    },
    treatment() {
      return (
        REPOSITORY_HEALTH_STATUSES[this.healthStatus] ??
        REPOSITORY_HEALTH_STATUSES[REPOSITORY_HEALTH_STATUS_UNKNOWN]
      );
    },
    timeAgo() {
      return getTimeago().format(this.lastHealthCheckedAt);
    },
    lastVerified() {
      if (!this.lastHealthCheckedAt) return this.$options.i18n.neverVerified;

      return sprintf(this.$options.i18n.lastVerified, { time: this.timeAgo }, false);
    },
    accessibleName() {
      const verdict = this.treatment.label;

      if (!this.lastHealthCheckedAt) {
        return sprintf(this.$options.i18n.verdictNeverVerified, { verdict }, false);
      }

      return sprintf(this.$options.i18n.verdictAndTime, { verdict, time: this.timeAgo }, false);
    },
  },
};
</script>

<template>
  <div
    role="status"
    :aria-label="accessibleName"
    class="gl-flex"
    :class="layoutClasses"
    data-testid="connection-indicator"
  >
    <gl-badge :variant="treatment.variant" :icon="treatment.icon">{{ treatment.label }}</gl-badge>

    <p class="gl-mb-0 gl-text-sm gl-text-subtle" data-testid="connection-last-verified">
      {{ lastVerified }}
    </p>
  </div>
</template>
