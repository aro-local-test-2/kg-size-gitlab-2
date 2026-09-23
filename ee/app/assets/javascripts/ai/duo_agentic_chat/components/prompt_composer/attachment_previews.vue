<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import { s__, sprintf } from '~/locale';

export default {
  name: 'AttachmentPreviews',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    attachments: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['remove'],
  methods: {
    removeLabel(attachment) {
      return sprintf(s__('DuoAgenticChat|Remove %{filename}'), { filename: attachment.filename });
    },
    sizeLabel(attachment) {
      return numberToHumanSize(attachment.byteSize);
    },
  },
};
</script>
<template>
  <ul
    v-if="attachments.length"
    class="gl-m-0 gl-flex gl-list-none gl-flex-wrap gl-gap-3 gl-px-4 gl-pt-4"
    data-testid="attachment-previews"
  >
    <li
      v-for="attachment in attachments"
      :key="attachment.id"
      class="gl-relative gl-flex gl-items-center gl-gap-2 gl-rounded-base gl-border-1 gl-border-solid gl-border-strong gl-bg-subtle gl-py-2 gl-pl-2 gl-pr-1"
      data-testid="attachment-preview"
    >
      <img
        :src="attachment.previewUrl"
        :alt="attachment.filename"
        class="gl-h-6 gl-w-6 gl-shrink-0 gl-rounded-small gl-object-cover"
      />
      <span class="gl-flex gl-min-w-0 gl-flex-col gl-leading-1">
        <span
          v-gl-tooltip
          :title="attachment.filename"
          class="gl-max-w-15 gl-truncate gl-text-sm"
          data-testid="attachment-filename"
          >{{ attachment.filename }}</span
        >
        <span class="gl-text-sm gl-text-subtle">{{ sizeLabel(attachment) }}</span>
      </span>
      <gl-button
        icon="close-xs"
        category="tertiary"
        size="small"
        :disabled="disabled"
        :aria-label="removeLabel(attachment)"
        data-testid="remove-attachment-button"
        @click="$emit('remove', attachment.id)"
      />
    </li>
  </ul>
</template>
