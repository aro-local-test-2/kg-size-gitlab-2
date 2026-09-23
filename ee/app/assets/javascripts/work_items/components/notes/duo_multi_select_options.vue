<script>
import { GlBadge } from '@gitlab/ui';
import MultipleChoiceSelector from '~/vue_shared/components/multiple_choice_selector.vue';
import MultipleChoiceSelectorItem from '~/vue_shared/components/multiple_choice_selector_item.vue';

export default {
  name: 'DuoMultiSelectOptions',
  components: { GlBadge, MultipleChoiceSelector, MultipleChoiceSelectorItem },
  props: {
    options: {
      type: Array,
      required: true,
    },
    checkedIds: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input'],
  computed: {
    optionRows() {
      const checked = new Set(this.checkedIds);

      return this.options.map((option) => ({ ...option, isChecked: checked.has(option.id) }));
    },
  },
};
</script>

<template>
  <multiple-choice-selector
    :checked="checkedIds"
    class="duo-question-options"
    @input="$emit('input', $event)"
  >
    <multiple-choice-selector-item
      v-for="option in optionRows"
      :key="option.id"
      :value="option.id"
      :description="option.description"
      :disabled="disabled"
      class="duo-question-option gl-flex gl-min-h-8 gl-items-center"
      :class="[
        { 'is-checked': option.isChecked },
        disabled
          ? 'gl-cursor-not-allowed'
          : 'gl-cursor-pointer gl-bg-default focus-within:gl-bg-subtle hover:gl-bg-subtle dark:gl-bg-neutral-700 dark:focus-within:gl-bg-neutral-600 dark:hover:gl-bg-neutral-600',
      ]"
      data-testid="duo-question-option"
    >
      <span class="gl-flex gl-w-full gl-items-start gl-gap-3">
        <span class="gl-grow gl-font-normal">{{ option.label }}</span>
        <gl-badge
          v-if="option.recommended"
          :variant="disabled ? 'neutral' : 'info'"
          class="gl-shrink-0"
          >{{ s__('WorkItemDuoQuestion|Recommended') }}</gl-badge
        >
      </span>
    </multiple-choice-selector-item>
  </multiple-choice-selector>
</template>
