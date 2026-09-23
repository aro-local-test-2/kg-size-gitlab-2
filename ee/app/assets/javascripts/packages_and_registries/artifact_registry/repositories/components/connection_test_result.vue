<script>
import { GlIcon } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { CONNECTION_TEST_MESSAGES } from '../../constants';

export default {
  name: 'ArtifactRegistryConnectionTestResult',
  i18n: {
    httpStatus: s__('ArtifactRegistry|Upstream responded with %{status}'),
  },
  components: {
    GlIcon,
  },
  props: {
    // Named for Artifact Registry's own field. It reports whether the upstream was reachable:
    // any status below 500 counts, so it is not a statement about the credentials.
    passed: {
      type: Boolean,
      required: true,
    },
    httpStatus: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    treatment() {
      return this.passed
        ? { icon: 'check-circle', variant: 'success', message: CONNECTION_TEST_MESSAGES.reachable }
        : { icon: 'error', variant: 'danger', message: CONNECTION_TEST_MESSAGES.unreachable };
    },
    hasHttpStatus() {
      return this.httpStatus !== null;
    },
    httpStatusText() {
      return sprintf(this.$options.i18n.httpStatus, { status: this.httpStatus }, false);
    },
  },
};
</script>

<template>
  <p class="gl-mb-0 gl-flex gl-items-center gl-gap-2 gl-text-sm">
    <gl-icon :name="treatment.icon" :variant="treatment.variant" />

    <span>{{ treatment.message }}</span>

    <span v-if="hasHttpStatus" class="gl-text-subtle" data-testid="connection-upstream-status">
      {{ httpStatusText }}
    </span>
  </p>
</template>
