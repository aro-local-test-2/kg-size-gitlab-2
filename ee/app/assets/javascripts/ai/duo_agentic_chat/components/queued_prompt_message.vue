<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { __, s__ } from '~/locale';

export default {
  name: 'QueuedPromptMessage',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    content: {
      type: String,
      required: true,
    },
  },
  emits: ['remove'],
  i18n: {
    QUEUED_LABEL: s__('DuoAgenticChat|Queued'),
    REMOVE_LABEL: s__('DuoAgenticChat|Remove queued prompt'),
    REMOVE_TOOLTIP: __('Remove'),
  },
};
</script>
<template>
  <div class="gl-flex gl-flex-col gl-items-end" data-testid="queued-prompt-message">
    <div class="gl-flex gl-items-center gl-gap-2">
      <gl-button
        v-gl-tooltip
        category="tertiary"
        variant="default"
        icon="close"
        size="small"
        :title="$options.i18n.REMOVE_TOOLTIP"
        :aria-label="$options.i18n.REMOVE_LABEL"
        data-testid="queued-prompt-remove-button"
        @click="$emit('remove')"
      />
      <div class="duo-chat-queued-message gl-rounded-2xl gl-p-4 gl-italic gl-break-anywhere">
        {{ content }}
      </div>
    </div>
    <span class="gl-mt-1 gl-text-sm gl-text-subtle" data-testid="queued-prompt-label">
      {{ $options.i18n.QUEUED_LABEL }}
    </span>
  </div>
</template>
