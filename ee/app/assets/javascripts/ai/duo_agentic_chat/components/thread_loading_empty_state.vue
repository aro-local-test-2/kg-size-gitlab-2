<script>
import { GlLoadingIcon } from '@gitlab/ui';

export default {
  name: 'ThreadLoadingEmptyState',
  components: {
    GlLoadingIcon,
  },
};
</script>

<template>
  <div
    class="gl-flex gl-w-full gl-flex-col gl-items-center gl-justify-center gl-gap-3 gl-py-8 gl-text-center"
    data-testid="thread-loading-empty-state"
  >
    <gl-loading-icon size="lg" />
    <p class="gl-m-0 gl-text-subtle">{{ s__('DuoAgenticChat|Loading your conversation...') }}</p>
  </div>
</template>
