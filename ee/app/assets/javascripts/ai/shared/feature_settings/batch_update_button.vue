<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'BatchUpdateButton',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    tooltipTitle: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['batch-update'],
};
</script>
<template>
  <div
    v-gl-tooltip="{ title: tooltipTitle, boundary: 'viewport' }"
    data-testid="model-batch-assignment-tooltip"
  >
    <gl-button category="secondary" :disabled="disabled" @click="$emit('batch-update')">
      {{ __('Apply to all') }}
    </gl-button>
  </div>
</template>
