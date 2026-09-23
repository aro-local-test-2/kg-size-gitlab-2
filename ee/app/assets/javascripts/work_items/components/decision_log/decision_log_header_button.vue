<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'DecisionLogHeaderButton',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    count: {
      type: Number,
      required: false,
      default: 0,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['open', 'close'],
  methods: {
    onClick() {
      this.$emit(this.isPanelOpen ? 'close' : 'open');
    },
  },
};
</script>

<template>
  <gl-button
    v-gl-tooltip.bottom="s__('WorkItemDecisionLog|Decision log')"
    category="tertiary"
    size="small"
    icon="log"
    :selected="isPanelOpen"
    :aria-pressed="String(isPanelOpen)"
    data-testid="decision-log-header-button"
    @click="onClick"
  >
    <span class="gl-sr-only">{{ s__('WorkItemDecisionLog|Decision log') }}</span>
    <span v-if="count" class="gl-text-sm gl-font-semibold" data-testid="decision-log-count">
      {{ count }}
    </span>
  </gl-button>
</template>
