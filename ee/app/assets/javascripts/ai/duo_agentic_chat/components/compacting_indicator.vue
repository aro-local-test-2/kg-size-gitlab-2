<script>
import { GlLoadingIcon } from '@gitlab/ui';

export default {
  name: 'CompactingIndicator',
  components: {
    GlLoadingIcon,
  },
};
</script>

<template>
  <div
    class="gl-mt-5 gl-flex gl-w-full gl-items-center gl-gap-3 gl-rounded-full gl-bg-strong gl-px-4 gl-py-3 gl-text-sm gl-text-subtle"
    data-testid="compacting-indicator"
  >
    <gl-loading-icon size="sm" inline />
    <span>{{ s__('DuoAgenticChat|Compacting…') }}</span>
  </div>
</template>
