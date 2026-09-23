<script>
import { GlButton, GlIcon } from '@gitlab/ui';

export default {
  name: 'ThreadLoadErrorEmptyState',
  components: {
    GlButton,
    GlIcon,
  },
  emits: ['retry-thread-load', 'new-chat'],
};
</script>

<template>
  <div
    class="gl-flex gl-w-full gl-flex-col gl-items-center gl-justify-center gl-gap-3 gl-py-8 gl-text-center"
    data-testid="thread-load-error-empty-state"
  >
    <gl-icon name="error" :size="24" variant="danger" />
    <h2 class="gl-heading-2 gl-my-0">{{ s__('DuoAgenticChat|Chat could not be loaded') }}</h2>
    <p class="gl-mb-2 gl-text-subtle">
      {{ s__('DuoAgenticChat|Your messages are still saved. Try again, or start a new chat.') }}
    </p>
    <div class="gl-flex gl-flex-wrap gl-justify-center gl-gap-3">
      <gl-button
        icon="retry"
        variant="confirm"
        data-testid="thread-load-error-retry-button"
        @click="$emit('retry-thread-load')"
      >
        {{ s__('DuoAgenticChat|Retry') }}
      </gl-button>
      <gl-button data-testid="thread-load-error-new-chat-button" @click="$emit('new-chat')">
        {{ s__('DuoAgenticChat|New chat') }}
      </gl-button>
    </div>
  </div>
</template>
