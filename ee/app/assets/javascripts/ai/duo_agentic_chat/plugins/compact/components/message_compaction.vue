<script>
export default {
  name: 'MessageCompaction',
};
</script>

<template>
  <div
    class="gl-flex gl-items-center gl-gap-4 gl-text-sm gl-text-subtle"
    data-testid="compaction-delimiter"
  >
    <hr class="gl-border-t gl-my-0 gl-grow gl-border-default" />
    <span>{{ s__('DuoAgenticChat|Conversation compacted') }}</span>
    <hr class="gl-border-t gl-my-0 gl-grow gl-border-default" />
  </div>
</template>
