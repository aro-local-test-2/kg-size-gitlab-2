<script>
import { GlButton, GlIcon } from '@gitlab/ui';

export default {
  name: 'ReadinessRow',
  components: {
    GlButton,
    GlIcon,
  },
  props: {
    row: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <li
    data-testid="readiness-row"
    class="gl-flex gl-items-center gl-gap-3 gl-border-t-1 gl-border-t-default gl-px-5 gl-py-3 gl-border-t-solid"
  >
    <!-- The icon is the only thing carrying the state visually, so it needs the label. -->
    <gl-icon
      :name="row.icon"
      :size="16"
      :variant="row.variant"
      :aria-label="row.stateLabel"
      class="gl-shrink-0"
    />
    <div class="gl-min-w-0 gl-flex-1">
      <div class="gl-text-sm gl-font-bold">{{ row.label }}</div>
      <div v-if="row.detail" class="gl-text-sm gl-text-subtle">{{ row.detail }}</div>
    </div>
    <gl-button v-if="row.action && row.href" :href="row.href" size="small" category="secondary">{{
      row.action
    }}</gl-button>
  </li>
</template>
