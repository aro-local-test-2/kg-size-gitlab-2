<script>
import { GlButton } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import {
  REPOSITORY_HEALTH_STATUS_UNKNOWN,
  REPOSITORY_PERMISSION_UPDATE_REPOSITORY,
} from '../../constants';
import testRepositoryConnectionMutation from '../../graphql/mutations/test_repository_connection.mutation.graphql';
import { permissionAllows } from '../../graphql/utils/permissions';
import ConnectionIndicator from '../components/connection_indicator.vue';

export default {
  name: 'ArtifactRegistryConnectionSection',
  i18n: {
    heading: s__('ArtifactRegistry|Connection'),
    test: s__('ArtifactRegistry|Test'),
    testing: s__('ArtifactRegistry|Testing'),
    empty: s__('ArtifactRegistry|No connection information available.'),
    unavailable: s__(
      'ArtifactRegistry|The Artifact Registry service is unavailable. Please try again.',
    ),
  },
  components: {
    ConnectionIndicator,
    GlButton,
  },
  props: {
    name: {
      type: String,
      required: true,
    },
    settings: {
      type: Object,
      required: false,
      default: null,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      testing: false,
      probedVerdict: null,
    };
  },
  computed: {
    verdict() {
      if (this.probedVerdict) return this.probedVerdict;
      if (!this.settings) return null;

      return {
        healthStatus: this.settings.lastHealthStatus ?? REPOSITORY_HEALTH_STATUS_UNKNOWN,
        lastHealthCheckedAt: this.settings.lastHealthCheckedAt ?? null,
      };
    },
    testText() {
      return this.testing ? this.$options.i18n.testing : this.$options.i18n.test;
    },
    canTest() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_UPDATE_REPOSITORY);
    },
  },
  methods: {
    async testConnection() {
      if (this.testing) return;

      this.testing = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: testRepositoryConnectionMutation,
          variables: { input: { name: this.name } },
        });

        const { lastHealthStatus, lastHealthCheckedAt, errors } = data.testConnection;

        if (errors.length) throw new Error(errors.join(' '));

        this.probedVerdict = { healthStatus: lastHealthStatus, lastHealthCheckedAt };
      } catch (error) {
        createAlert({ message: this.$options.i18n.unavailable, error, captureError: true });
      } finally {
        this.testing = false;
      }
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-3">
    <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h2 class="gl-heading-5 gl-mb-3">{{ $options.i18n.heading }}</h2>

      <gl-button
        v-if="canTest"
        category="tertiary"
        size="small"
        :loading="testing"
        :disabled="testing"
        data-testid="connection-test"
        @click="testConnection"
      >
        {{ testText }}
      </gl-button>
    </div>

    <connection-indicator
      v-if="verdict"
      :health-status="verdict.healthStatus"
      :last-health-checked-at="verdict.lastHealthCheckedAt"
    />

    <p v-else class="gl-mb-0 gl-text-subtle" data-testid="connection-empty">
      {{ $options.i18n.empty }}
    </p>
  </div>
</template>
