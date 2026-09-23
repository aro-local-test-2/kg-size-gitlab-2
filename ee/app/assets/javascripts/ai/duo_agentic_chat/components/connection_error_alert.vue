<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';

export default {
  name: 'ConnectionErrorAlert',
  components: { GlAlert, GlButton },
  emits: ['retry'],
  i18n: {
    title: s__('DuoAgenticChat|Connection lost'),
    description: s__('DuoAgenticChat|GitLab Duo will resume once reconnected.'),
    retryButton: s__('DuoAgenticChat|Reconnect'),
  },
};
</script>

<template>
  <gl-alert
    variant="danger"
    :dismissible="false"
    :title="$options.i18n.title"
    data-testid="connection-error-alert"
  >
    <p>{{ $options.i18n.description }}</p>
    <template #actions>
      <span>
        <gl-button
          variant="confirm"
          category="primary"
          size="small"
          data-testid="retry-button"
          @click="$emit('retry')"
        >
          {{ $options.i18n.retryButton }}
        </gl-button>
      </span>
    </template>
  </gl-alert>
</template>
