<script>
import { GlBadge, GlLoadingIcon } from '@gitlab/ui';

export default {
  name: 'DuoSingleSelectOptions',
  components: { GlBadge, GlLoadingIcon },
  props: {
    options: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    submittingId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['select'],
};
</script>

<template>
  <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
    <li v-for="option in options" :key="option.id">
      <!-- `type="button"` so a card inside the reply form never submits it. -->
      <button
        type="button"
        class="gl-flex gl-min-h-8 gl-w-full gl-items-center gl-gap-3 gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-px-4 gl-py-3 gl-text-left"
        :class="
          disabled
            ? '!gl-cursor-not-allowed gl-bg-disabled gl-text-disabled'
            : 'gl-bg-default gl-text-default hover:gl-bg-subtle focus:gl-bg-subtle dark:gl-bg-neutral-700 dark:hover:gl-bg-neutral-600 dark:focus:gl-bg-neutral-600'
        "
        :disabled="disabled"
        data-testid="duo-question-option"
        @click="$emit('select', option)"
      >
        <gl-loading-icon v-if="submittingId === option.id" size="sm" class="gl-shrink-0" />
        <span class="gl-grow">
          <span class="gl-flex gl-items-center gl-gap-3">
            <span class="gl-grow">{{ option.label }}</span>
            <gl-badge
              v-if="option.recommended"
              :variant="disabled ? 'neutral' : 'info'"
              class="gl-shrink-0"
              >{{ s__('WorkItemDuoQuestion|Recommended') }}</gl-badge
            >
          </span>
          <span
            v-if="option.description"
            class="gl-mt-1 gl-block gl-text-sm"
            :class="disabled ? 'gl-text-disabled' : 'gl-text-subtle'"
            >{{ option.description }}</span
          >
        </span>
      </button>
    </li>
  </ul>
</template>
