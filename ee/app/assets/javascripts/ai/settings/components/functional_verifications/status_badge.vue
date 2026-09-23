<script>
import { GlBadge } from '@gitlab/ui';
import { s__ } from '~/locale';
import { FUNCTIONAL_VERIFICATION_STATUS } from './constants';

export default {
  name: 'FunctionalVerificationStatusBadge',
  components: {
    GlBadge,
  },
  props: {
    status: {
      type: String,
      required: true,
    },
  },
  computed: {
    badge() {
      switch (this.status) {
        case FUNCTIONAL_VERIFICATION_STATUS.RUNNING:
          return { variant: 'info', icon: 'status-running', text: s__('AiPowered|Running') };
        case FUNCTIONAL_VERIFICATION_STATUS.PASSED:
          return {
            variant: 'success',
            icon: 'check-circle-filled',
            text: s__('AiPowered|Passed'),
          };
        case FUNCTIONAL_VERIFICATION_STATUS.FAILED:
          return { variant: 'danger', icon: 'error', text: s__('AiPowered|Failed') };
        case FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN:
          return { variant: 'neutral', icon: 'dash-circle', text: s__('AiPowered|Not run') };
        default:
          return null;
      }
    },
  },
};
</script>

<template>
  <span role="status" class="gl-inline-flex" data-testid="functional-verification-status-badge">
    <gl-badge v-if="badge" :variant="badge.variant" :icon="badge.icon">{{ badge.text }}</gl-badge>
  </span>
</template>
